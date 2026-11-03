package com.nublime.vpn

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.net.VpnService
import android.os.PowerManager
import android.provider.Settings
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "com.nublime.vpn/vpn"
        private const val STATUS_CHANNEL = "com.nublime.vpn/status"
        // WO-5: cumulative traffic counters, pushed every second while a listener is attached.
        private const val STATS_CHANNEL = "com.nublime.vpn/stats"
        // Business-layer channels (kept from the original app wiring):
        private const val METHOD_CHANNEL = "com.nublime.app/method"
        private const val PLATFORM_CHANNEL = "com.nublime.app/platform"
        private const val VPN_REQUEST = 1001
        private const val VPN_PERMISSION_REQUEST = 1002
        private var pendingStartConfig: String? = null
        /** §4.3: attempt id assigned at acceptance, kept for the post-permission start path. */
        private var pendingStartSessionId: String = ""
        // R36-A05: 权限弹窗往返期间必须保留分应用配置，否则授权后这次启动会退回全量代理。
        private var pendingPerAppMode: String = "off"
        private var pendingPerAppPackages: ArrayList<String> = arrayListOf()
        private var pendingPermissionResult: Result? = null
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // EventChannel: push connection status events (Starting/Started/Stopping/Stopped)
        // to Dart's watchStatus() stream. Stream-driven (not polling).
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, STATUS_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    XrayVpnService.statusSink = events
                    // §4.2: replay the SAME state object the live events maintain (phase + last error
                    // are preserved; replay is no longer derived from the isRunning boolean).
                    val st = XrayVpnService.currentState
                    android.util.Log.d("StatusBridge", "onListen replay phase=${st.phase} session=${st.sessionId} seq=${st.seq}")
                    events?.success(
                        mapOf(
                            "status" to st.phase,
                            "alert" to if (st.errorCode != null) "startFailed" else null,
                            "message" to null,
                            "errorCode" to st.errorCode,
                            "sessionId" to st.sessionId,
                            "seq" to st.seq,
                            "replay" to true,   // §6: marks an authoritative snapshot (not a live event)
                        )
                    )
                }

                override fun onCancel(arguments: Any?) {
                    XrayVpnService.statusSink = null
                }
            })

        // WO-5: traffic stats channel. Kotlin pushes CUMULATIVE counters (hev TProxyGetStats)
        // once per second while a listener is attached; Dart computes bytes/s. Sampling runs
        // only while the tunnel's service is alive and a listener exists — it is observability,
        // never a liveness verdict (the counters must not gate connection health).
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, STATS_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    XrayVpnService.statsSink = events
                    XrayVpnService.activeInstance?.let {
                        it.startStatsSampling()
                        android.util.Log.d("StatsBridge", "onListen session=${XrayVpnService.currentState.sessionId}")
                    }
                }

                override fun onCancel(arguments: Any?) {
                    XrayVpnService.statsSink = null
                }
            })

        // Core VPN bridge (start/stop/isRunning/checkPermission)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call: MethodCall, result: Result ->
                when (call.method) {
                    "startVpn" -> handleStartVpn(call, result)
                    "stopVpn" -> {
                        // F5 (Astra): the stop intent carries the session it is stopping, so the
                        // service's shutdown path can tell a user stop from a stale teardown when
                        // logging/publishing; a stop landing during Connecting is a user cancel.
                        //
                        // Astra R24 (STALE_STOP_SID): an OPTIONAL explicit target. Callers that
                        // pass nothing (every production path — stop()/restart()) keep the
                        // previous behaviour exactly: the live session is stopped. The argument
                        // exists only for the fault-injection build, which addresses an
                        // already-superseded session from inside the app because an external
                        // adb stop intent is refused by Android's exported-permission check.
                        // An empty/absent argument is explicitly treated as "current", so no
                        // accidental empty sid can ever stop an arbitrary session.
                        val requestedSid = call.argument<String>("sessionId")
                        val stopIntent = Intent(this, XrayVpnService::class.java)
                            .putExtra("action", "stop")
                            .putExtra("sessionId",
                                if (requestedSid.isNullOrEmpty()) XrayVpnService.currentSessionId
                                else requestedSid)
                        startService(stopIntent)
                        result.success("VPN stopped")
                    }
                    "isRunning" -> result.success(XrayVpnService.isRunning)
                    // §5: authoritative current snapshot — lets Dart recover state after a
                    // start receipt even if live events arrived (and were dropped) beforehand.
                    "statusSnapshot" -> {
                        val st = XrayVpnService.currentState
                        result.success(
                            mapOf(
                                "status" to st.phase,
                                "alert" to if (st.errorCode != null) "startFailed" else null,
                                // §5.2: carry the failure reason so Dart can surface a diagnosable
                                // message; the errorCode is a fixed enum name, never payload/config.
                                "message" to st.errorCode,
                                "errorCode" to st.errorCode,
                                "sessionId" to st.sessionId,
                                "seq" to st.seq,
                                "replay" to true,
                            )
                        )
                    }
                    "checkPermission" -> result.success(VpnService.prepare(this) == null)
                    else -> result.notImplemented()
                }
            }

        // Business-layer method channel: VPN permission request (connect gate)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call: MethodCall, result: Result ->
                when (call.method) {
                    "requestVpnPermission" -> handleRequestVpnPermission(result)
                    "openVpnSettings" -> {
                        // 跳系统 VPN 列表页（用户需找到 WildLime 点右侧箭头进详情页开 Always-on/Lockdown）。
                        // 实测 ACTION_VPN_SETTINGS 是本机可用的最深层级入口；AOSP 的
                        // Settings$VpnAppDetailsActivity 在 MIUI 14 不可用（落到设置总入口）。
                        startActivity(Intent(Settings.ACTION_VPN_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        result.success(true)
                    }
                    // 读取系统级断网保护的**真实**状态。设置页里那个开关曾经只是个本地
                    // useState，拨了什么都不做 —— 用户以为开了保护，其实流量照常泄漏。
                    // 真值只在 Settings.Secure 里：always_on_vpn_app / always_on_vpn_lockdown。
                    "getAlwaysOnVpnState" -> {
                        try {
                            // 注意：Settings.Secure.ALWAYS_ON_VPN_APP / ALWAYS_ON_VPN_LOCKDOWN 这两个
                            // 常量在公开 SDK 里是 @SystemApi（编译期 Unresolved reference），
                            // 但对应的键名是稳定的系统设置键，按字面量读取。
                            val alwaysOnApp = Settings.Secure.getString(
                                contentResolver, "always_on_vpn_app"
                            )
                            val lockdownRaw = Settings.Secure.getString(
                                contentResolver, "always_on_vpn_lockdown"
                            )
                            result.success(
                                mapOf(
                                    "supported" to true,
                                    "alwaysOnApp" to alwaysOnApp,
                                    "isThisApp" to (alwaysOnApp != null && alwaysOnApp == packageName),
                                    "lockdown" to (lockdownRaw == "1" || "true".equals(lockdownRaw, true)),
                                )
                            )
                        } catch (e: Exception) {
                            // 部分 ROM 屏蔽该键的读取 —— 如实返回"读不到"，不要假装已开启。
                            result.success(
                                mapOf(
                                    "supported" to false,
                                    "error" to (e.message ?: e.javaClass.simpleName),
                                )
                            )
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // Business-layer platform channel: battery optimization (MIUI background survival)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PLATFORM_CHANNEL)
            .setMethodCallHandler { call: MethodCall, result: Result ->
                when (call.method) {
                    "is_ignoring_battery_optimizations" -> {
                        val pm = getSystemService(POWER_SERVICE) as PowerManager
                        result.success(pm.isIgnoringBatteryOptimizations(packageName))
                    }
                    "request_ignore_battery_optimizations" -> {
                        val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                        intent.data = Uri.parse("package:$packageName")
                        startActivity(intent)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun handleRequestVpnPermission(result: Result) {
        val intent = VpnService.prepare(this)
        if (intent != null) {
            // Needs authorization — show system dialog, resolve when it returns.
            pendingPermissionResult = result
            startActivityForResult(intent, VPN_PERMISSION_REQUEST)
        } else {
            result.success(true)
        }
    }

    private fun handleStartVpn(call: MethodCall, result: Result) {
        val config = call.argument<String>("config") ?: run {
            result.error("CONFIG", "missing config", null)
            return
        }

        // R36-A05：分应用代理以前只存在于 Dart 偏好里，Kotlin 侧从未消费 —— UI 勾了等于没勾。
        // Dart 在 startVpn 里带上模式与包名，这里原样透传给 service（权限弹窗路径也要保留，
        // 否则用户在弹窗里点"允许"之后这次启动就退回全量代理了）。
        val perAppMode = call.argument<String>("perAppMode") ?: "off"
        val perAppPackages = call.argument<List<String>>("perAppPackages") ?: emptyList()

        // §4.3: assign an immutable attempt id at command acceptance; it is carried all the way
        // into the service, so the acceptance receipt and the real attempt share one identifier.
        val sid = java.util.UUID.randomUUID().toString().replace("-", "").substring(0, 12)
        pendingStartSessionId = sid

        val intent = VpnService.prepare(this)
        if (intent != null) {
            pendingStartConfig = config
            pendingPerAppMode = perAppMode
            pendingPerAppPackages = ArrayList(perAppPackages)
            startActivityForResult(intent, VPN_REQUEST)
            result.success(
                mapOf(
                    "accepted" to false,
                    "permissionRequired" to true,
                    "sessionId" to sid,
                )
            )
        } else {
            startVpnService(config, sid, perAppMode, perAppPackages)
            // R01: command ACCEPTANCE only — never a connection-success signal.
            result.success(
                mapOf(
                    "accepted" to true,
                    "sessionId" to sid,
                )
            )
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        when (requestCode) {
            VPN_PERMISSION_REQUEST -> {
                pendingPermissionResult?.success(resultCode == Activity.RESULT_OK)
                pendingPermissionResult = null
            }
            VPN_REQUEST -> {
                val config = pendingStartConfig
                val sid = pendingStartSessionId
                val mode = pendingPerAppMode
                val pkgs = ArrayList(pendingPerAppPackages)
                pendingStartConfig = null
                pendingStartSessionId = ""
                pendingPerAppMode = "off"
                pendingPerAppPackages = arrayListOf()
                if (resultCode == Activity.RESULT_OK && config != null) {
                    startVpnService(config, sid, mode, pkgs)
                }
            }
        }
    }

    private fun startVpnService(
        config: String,
        sessionId: String,
        perAppMode: String,
        perAppPackages: List<String>
    ) {
        val intent = Intent(this, XrayVpnService::class.java)
        intent.putExtra("xray_config", config)
        // §4.3: the attempt id is assigned here (command acceptance) and carried into the service.
        intent.putExtra("sessionId", sessionId)
        // R36-A05: 分应用名单随启动一起下发。
        intent.putExtra("per_app_mode", perAppMode)
        intent.putStringArrayListExtra("per_app_packages", ArrayList(perAppPackages))
        startService(intent)
    }
}
