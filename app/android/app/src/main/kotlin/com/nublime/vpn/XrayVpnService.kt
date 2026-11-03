package com.nublime.vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Build
import java.io.InputStream
import java.util.concurrent.TimeUnit
import java.net.InetSocketAddress
import java.net.Socket
import javax.net.ssl.SSLSocket
import javax.net.ssl.SSLSocketFactory
import org.json.JSONArray
import org.json.JSONObject
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import java.io.File
import java.io.FileDescriptor
import java.io.FileWriter
import java.security.SecureRandom
import io.flutter.plugin.common.EventChannel

class XrayVpnService : VpnService() {

    companion object {
        const val CHANNEL_ID = "xray_vpn"
        const val NOTIFY_ID = 1
        @Volatile var isRunning = false

        // EventChannel sink for pushing status events to Dart (watchStatus stream).
        // Set by MainActivity when the EventChannel is listened to; null when no listener.
        @Volatile var statusSink: EventChannel.EventSink? = null
        /**
         * WO-5: sink for the traffic-stats EventChannel. Set by MainActivity's onListen and
         * cleared on Cancel; the sampler pushes only while non-null.
         */
        @Volatile var statsSink: EventChannel.EventSink? = null
        /** R01: last/current attempt id, readable by MainActivity for consistent replay. */
        @Volatile var currentSessionId: String = ""

        /**
         * R01 §4.2: single source of truth for the visible session state.
         * Live events and subscription replay both read/write this object
         * (replay is no longer derived from the isRunning boolean).
         */
        data class SessionState(
            val sessionId: String,
            val phase: String,
            val errorCode: String?,
            val seq: Long,
        )

        @Volatile var currentState = SessionState("", "Stopped", null, 0)

        /**
         * §5.4: sequence lives with the shared snapshot (companion), NOT with a Service instance —
         * a recreated Service must continue the same monotonic sequence so Dart's filter keeps working.
         */
        private val seqCounter = java.util.concurrent.atomic.AtomicLong(0)

        /** WO-5: the ONE stats sampler for this process (survives service recreation). */
        @Volatile private var companionStatsThread: Thread? = null
        const val STATS_SAMPLE_MS = 1000L

        // §8-2 readiness/health budget: bounded overall deadline, per-try timeout, small retry
        // budget, and a bounded fallback target list. No direct-connection fallback exists.
        const val PROBE_TOTAL_MS = 12000L
        // DEVICE CALIBRATION (2026-10-07): a per-try bound must exist (Astra PER_TRY: one
        // silent target may not consume the whole round budget), but it must also FIT a
        // real remote handshake THROUGH the tunnel: SOCKS auth + connect + TLS through the
        // VLESS/Reality path measures 1-3s per stage on-device; a 3s try budget turned every
        // healthy probe into a false PROBE_FAILED (real-network run 2026-10-07, sessions
        // 36c377523ec1 / a0a1752122cd). 6s keeps the per-try guarantee (2 targets × ≤3 tries
        // still bounded by the 12s TOTAL deadline) while leaving room for a real handshake.
        const val PROBE_SINGLE_MS = 6000
        const val PROBE_RETRIES = 3
        const val PROBE_SETTLE_MS = 600L      // let the freshly-started core bind its SOCKS port
        const val PROBE_RETRY_GAP_MS = 600L
        const val HEALTH_INTERVAL_MS = 10000L
        /** §6 boundary 1: how long a new core start waits for the previous stop to be confirmed. */
        const val CORE_HANDOFF_TIMEOUT_MS = 10000L
        /**
         * Test hook (same stub pattern as the other seams): when set, replaces the REAL data-path
         * probe so offline harnesses can exercise the ready/failed branches deterministically.
         * Production leaves it null → the real SOCKS+TLS probe runs.
         */
        @Volatile var probeHook: (() -> Boolean)? = null

        /**
         * R20 §4 test seam (visibility-only, no behavior change): JVM fixtures observe the
         * single-flight stop coordinator's states. stopTokensSnapshot() is retained for the
         * R19-era fixtures, mapped onto the new coordinator: a token "exists" while either
         * resource's stop is Stopping (the fence the old fixtures asserted).
         */
        fun stopTokensSnapshot(): Set<String> {
            val out = mutableSetOf<String>()
            if (hevStopState.get() is StopPhase.Stopping) out.add("hev")
            if (coreStopState.get() is StopPhase.Stopping) out.add("core")
            return out
        }

        val PROBE_TARGET_PRIMARY = "www.gstatic.com" to 443
        val PROBE_TARGET_FALLBACK = "api.ipify.org" to 443

        /**
         * F1 (Astra R11): process-level ownership of the native hev tunnel and the Xray core.
         * Each is set to the attempt id that successfully started it and released ONLY by that
         * attempt's own cleanup, so an old generation's cleanup can never globally stop a newer
         * generation's tunnel or core (Astra F1: nativeOwner=none while B/Started). These live on
         * the companion (process-wide) so they survive Service instance recreation.
         */
        @Volatile var hevOwner: String? = null
        @Volatile var nativeCoreOwner: String? = null

        /**
         * F1: process-level pointer to the ACTIVE service instance. An old instance's async
         * destroy cleanup must never run a global stop after a newer instance took over —
         * the destroy-time global branch is skipped unless THIS instance is still the active one.
         */
        @Volatile var activeInstance: XrayVpnService? = null

        /**
         * Astra 10-09 §3.1 (CROSS_DESTROY): nativeLock and coreStopPending MUST be process-level.
         * When they were instance fields, two Service instances held two different locks and two
         * unrelated stop flags — A's hung onDestroy stopXray did not exclude a new instance's
         * start, and B's core was then killed by the late old stop. One process, ONE native
         * execution lock and ONE stop-confirmation flag, shared by every instance.
         */
        val processNativeLock = java.util.concurrent.locks.ReentrantLock()
        @Volatile var processCoreStopPending = false

        /**
         * Astra R21 §5 (HEV_RETRY_RECOVERY): after a hev stop lands in Unconfirmed, hevOwner
         * is already null, so every stop entry gated on `hevOwner != null` is unreachable —
         * the block could never be cleared (next connections CONFLICT forever). The fix is an
         * explicit, controlled RECOVERY RECORD: while a resource's stop state is Unconfirmed,
         * any LIVE stop command (attempt cleanup or no-attempt shutdown/destroy) MUST offer a
         * retry — admitStop already permits Unconfirmed→Stopping. The record is what makes
         * the retry REACHABLE; it is not the block itself (the block is the StopPhase).
         * Cleared only when a stop is CONFIRMED (trusted confirmation lifts the block).
         */
        @Volatile var hevStopNeedsRetry: Boolean = false
        @Volatile var coreStopNeedsRetry: Boolean = false

        /**
         * R21 §4: the immutable stop CONTEXT a caller carries into the coordinator. Admission
         * re-verifies this INSIDE the lock for EACH resource (same atomic decision as the
         * registration): single-flight limits CONCURRENCY, it does not grant an old caller
         * permission to stop a NEWER generation's resources (stale-no-attempt-destroy: the
         * old onDestroy checked activeInstance/epoch BEFORE acquiring the lock, then waited,
         * and by the time it entered, B had taken over — the stop was still admitted).
         */
        class StopContext(val expectedInstance: XrayVpnService?, val stopEpoch: Long)

        /**
         * Astra R20 §4/§5/§6: per-resource SINGLE-FLIGHT stop state machine.
         *  - Per RESOURCE (hev / core), one operation executes at a time; a second stop
         *    request for the same resource WAITS for the first result and reuses it.
         *  - The terminal state is committed by operation identity (opId), never by session.
         *  - UNCONFIRMED (reply false / threw / unparseable / hev stop exception) is a
         *    TAKEOVER BLOCK for the resource; a LIVE stop command may retry (admitStop
         *    permits Unconfirmed→Stopping) and a CONFIRMED retry lifts the block (R21 §5).
         */
        private sealed class StopPhase {
            object Idle : StopPhase()
            /** A stop invoke is executing; [opId] is the identity of THAT operation. */
            class Stopping(val opId: Long) : StopPhase()
            /** The executing stop returned but could not confirm the resource is stopped. */
            object Unconfirmed : StopPhase()
            object Confirmed : StopPhase()
        }

        /** Process-wide single-flight state per resource. Guarded by processNativeLock. */
        private val hevStopState = java.util.concurrent.atomic.AtomicReference<StopPhase>(StopPhase.Idle)
        private val coreStopState = java.util.concurrent.atomic.AtomicReference<StopPhase>(StopPhase.Idle)
        private val stopOpCounter = java.util.concurrent.atomic.AtomicLong(0)

        /**
         * Single-flight stop admission (nativeLock held). Returns (opId, mustExecute):
         *  - another operation is Stopping for this resource → (its opId, false): WAIT and
         *    reuse its result;
         *  - a previous stop left the resource UNCONFIRMED → (this caller's new opId, true):
         *    one more real attempt is allowed (conservative retry, still fenced);
         *  - otherwise → (new opId, true): this caller executes the stop.
         */
        private fun admitStop(state: java.util.concurrent.atomic.AtomicReference<StopPhase>): Pair<Long, Boolean> {
            val cur = state.get()
            if (cur is StopPhase.Stopping) return Pair(cur.opId, false)
            val opId = stopOpCounter.incrementAndGet()
            state.set(StopPhase.Stopping(opId))
            return Pair(opId, true)
        }

        /**
         * Result commit by operation identity (nativeLock held). Only the operation whose
         * opId still owns the Stopping phase may commit; a stale late return commits nothing.
         * Returns true if THIS operation's result was committed.
         */
        private fun commitStop(
            state: java.util.concurrent.atomic.AtomicReference<StopPhase>,
            opId: Long,
            confirmed: Boolean,
        ): Boolean {
            val cur = state.get()
            if (cur !is StopPhase.Stopping || cur.opId != opId) return false
            state.set(if (confirmed) StopPhase.Confirmed else StopPhase.Unconfirmed)
            return true
        }

        /**
         * Astra R20 §5: UNCONFIRMED hev stop is a takeover block for hev too — not just
         * hevOwner=null. Cleared only by a later confirmed stop or by a successful NEW hev
         * start after the state was Confirmed... but a start may never run while UNCONFIRMED
         * (fail closed), so in practice the block persists until a confirmed stop lands.
         */
        /**
         * R21 §5: takeover block = the StopPhase is Unconfirmed OR a retry is still owed
         * (needsRetry tracks the same fact for entries that cannot see the phase atomically;
         * both are set together and cleared together on a CONFIRMED stop).
         */
        private fun hevStopTakeoverBlocked(): Boolean =
            hevStopState.get() is StopPhase.Unconfirmed || hevStopNeedsRetry
        /**
         * R22-F6: the core start gate (runXray) now REFERENCES this predicate instead of an
         * inline equivalent — one source of truth for the core takeover-block criteria
         * (pending flag + Unconfirmed phase + needsRetry record). Astra flagged the dead
         * function + dual-source drift risk; this is the "make the gate reference it" option.
         */
        private fun coreStopTakeoverBlocked(): Boolean =
            processCoreStopPending || coreStopState.get() is StopPhase.Unconfirmed || coreStopNeedsRetry

        /**
         * Astra 10-09 §3.2 (LATE_SHUTDOWN): the tail of any stop/destroy (stopForeground /
         * stopSelf / isRunning=false / "Stopped" publication) must verify it still owns the
         * CURRENT generation before mutating process-wide visible state. The epoch increments
         * whenever any instance begins a new stop or a new attempt registers; a stale shutdown
         * re-checks its captured epoch before publishing.
         */
        val stopEpochCounter = java.util.concurrent.atomic.AtomicLong(0)

        /**
         * Astra 10-09 §3.4 (STOP_FALSE): "stopXray returned" is not "core stopped". The reply
         * JSON is parsed with the SAME strict parser used for start replies; success=false or
         * an unparseable reply leaves coreStopPending set (the next start fails closed with
         * CONFLICT) instead of silently admitting a new core over a possibly-running one.
         * The real libXray stopXray reply contract is verified by XrayInvokeParser on the
         * actual response samples — no invented semantics.
         */
        fun parseStopReply(reply: String): Boolean {
            val parsed = XrayInvokeParser.parse(reply)
            return parsed is XrayInvokeResult.Accepted
        }
        }

    // Push a status event to Dart via the EventChannel (no-op if no listener).
    /** Legacy entry point (no attempt context, e.g. shutdown). Delegates to the snapshot path. */
    private fun emitStatus(
        status: String,
        alert: String? = null,
        message: String? = null,
        errorCode: String? = null,
    ) = emitStatusFor(null, status, alert, message, errorCode)

    private var tunFd: Int = -1
    /** Per-attempt session identifier (R01): every event carries the session it belongs to. */
    private var sessionId: String = ""
    /** R36-A05: 分应用代理配置，随每次 start intent 下发并被冻结。 */
    @Volatile private var perAppMode: String = "off"
    @Volatile private var perAppPackages: List<String> = emptyList()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var vpnPfd: ParcelFileDescriptor? = null

    // JNI bindings for hev-socks5-tunnel (package hev.htproxy, class TProxyService)
    private fun hevStart(configPath: String, fd: Int) = hev.htproxy.TProxyService.TProxyStartService(configPath, fd)
    private fun hevStop() = hev.htproxy.TProxyService.TProxyStopService()

    /**
     * F4 (Astra §4.4) — the hev worker's REAL lifecycle signal, verified against the device
     * .so physical artifact:
     *
     *   device .so  SHA-256 f78341ad668b0067ae35f872339b047cd8b51d8988c5c98f89af4c85d98c5ce1
     *   BuildID     96120cab57cdc4cb3136d2416e97646876597a85  (arm64-v8a, stripped)
     *   JNI_OnLoad @0x1fb00 → RegisterNatives(table @0x5aff0, 4 entries):
     *     TProxyIsRunning '()Z'  fn=0x1fdd4  → ldar of an atomic run flag (worker thread state)
     *     TProxyGetStats  '()[J' fn=0x1fdec  → hev_socks5_tunnel_stats → long[4] (tx/rx)
     *
     * (This supersedes the withdrawn R15 "dead declaration" conclusion, which was disproved by
     *  the registry dump above — the methods ARE registered and callable.)
     *
     * A missing symbol on some other build returns null (unavailable) instead of a false verdict:
     * an absent signal must degrade the check, never revoke a healthy tunnel.
     */
    private fun hevWorkerAlive(): Boolean? = try {
        hev.htproxy.TProxyService.TProxyIsRunning()
    } catch (_: Throwable) { null }

    private fun hevStatsSnapshot(): LongArray? = try {
        hev.htproxy.TProxyService.TProxyGetStats()
    } catch (_: Throwable) { null }

    /**
     * WO-5: cumulative traffic counters pushed to Dart once per second.
     *
     * Counter layout — VERIFIED against the upstream JNI wrapper that registers these
     * natives (hev-socks5-tunnel src/hev-jni.c, native_get_stats):
     *   array[0]=tx_packets  array[1]=tx_bytes  array[2]=rx_packets  array[3]=rx_bytes
     * (hev_socks5_tunnel_stats() fills them in that order; the shipped .so registers the
     * same table — TProxyGetStats '()[J'. Re-confirmed on device: a 20 MB download grows
     * index 3 only.)
     *
     * Discipline: stats are observability, never a liveness verdict — an idle tunnel
     * legitimately shows flat counters, so they must not gate connection health
     * (same rule as the health monitor's comment).
     */
    fun startStatsSampling() {
        if (companionStatsThread?.isAlive == true) return
        val t = Thread {
            log("stats sampling started")
            while (true) {
                val sink = statsSink ?: break          // no listener → nothing to push
                if (!isRunning) break                  // tunnel down → stop (Dart renders idle)
                val s = hevStatsSnapshot()
                if (s != null && s.size >= 4) {
                    val payload = mapOf<String, Any>(
                        "txBytes" to s[1],
                        "rxBytes" to s[3],
                        "txPackets" to s[0],
                        "rxPackets" to s[2],
                        "tsMs" to android.os.SystemClock.elapsedRealtime(),
                    )
                    // EventSink is @UiThread: this sampler runs on its own thread, so the push
                    // MUST hop to the main looper (device 2026-10-27: a direct call crashed the
                    // app with "Methods marked with @UiThread must be executed on the main
                    // thread" 20 ms after the listener attached).
                    mainHandler.post {
                        if (statsSink != null && isRunning) {
                            try { statsSink?.success(payload) } catch (_: Throwable) { /* listener torn down */ }
                        }
                    }
                }
                try { Thread.sleep(STATS_SAMPLE_MS) } catch (_: InterruptedException) { break }
            }
            log("stats sampling stopped (sink=${statsSink != null} running=$isRunning)")
        }
        t.isDaemon = true
        companionStatsThread = t
        t.start()
    }

    override fun onCreate() {
        super.onCreate()
        // F1: register this instance as the process-active service. An older instance's async
        // destroy cleanup checks this before any global stop, so a recreated service's cores
        // are never stopped by the instance they replaced.
        XrayVpnService.activeInstance = this
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Handle explicit stop command
        if (intent?.getStringExtra("action") == "stop") {
            // Astra R18.1 §5 (STALE_STOP_SID): the stop intent carries the session the caller
            // wants stopped. The two commands have DIFFERENT semantics:
            //   - empty sid          → "stop CURRENT" (explicit user stop of whatever is live)
            //   - non-empty sid      → "stop THAT session": if it names an ALREADY-SUPERSEDED
            //     session, the command is STALE and must NOT stop the current generation.
            // The previous code only logged the sid and unconditionally shut down the current
            // attempt — an old A's stop command was interpreted as "stop B". The sid is now
            // VALIDATED against the live attempt in the same coordination critical section
            // that captures the victim: stale commands return without touching B.
            val stopSid = intent.getStringExtra("sessionId") ?: ""
            val currentSid = XrayVpnService.currentSessionId
            if (stopSid.isNotEmpty() && currentSid.isNotEmpty() && stopSid != currentSid) {
                // Astra R19 §5 (STALE_STOP_FRAMEWORK): the stale branch previously called
                // stopSelf(startId) believing it "consumes the message". Android's startId is
                // the FRAMEWORK start-request counter, not a business session id: an old A's
                // stop command can carry the LATEST startId, and stopSelf(latest) asks the
                // framework to stop the service's started lifecycle — killing the very
                // service still running B. A stale command must change NOTHING about the
                // current connection or the service lifecycle: log and return. The Intent is
                // consumed by returning from onStartCommand; no framework call is made.
                log("stale stop command ignored: requested session='$stopSid' is not the live one (current='$currentSid')")
                return START_NOT_STICKY
            }
            log("stop command received for session='$stopSid' (current='$currentSid')")
            shutdown()
            return START_NOT_STICKY
        }
        startForeground(NOTIFY_ID, buildNotification("VPN connecting..."))
        val config = intent?.getStringExtra("xray_config")
        if (config == null) { stopSelf(); return START_NOT_STICKY }
        // R36-A05: 分应用名单在启动时冻结，供 establishTun 使用。每次 start 覆盖上一次，
        // 保证"上次选的包"不会泄漏到这次连接里。
        perAppMode = intent.getStringExtra("per_app_mode") ?: "off"
        perAppPackages = intent.getStringArrayListExtra("per_app_packages") ?: emptyList()
        // §4.1: register the immutable attempt AT THE COMMAND ENTRY, then hand the SAME object to
        // the task — a stop that lands before the task runs invalidates it, and the task can never
        // acquire a fresh identity by re-reading a mutable field.
        val requested = intent.getStringExtra("sessionId")
        val sid = if (requested.isNullOrEmpty()) {
            java.util.UUID.randomUUID().toString().replace("-", "").substring(0, 12)
        } else requested
        sessionId = sid                     // last-accepted id, for replay/logging only
        val attempt = beginAttempt(sid)
        currentSessionId = attempt.id
        Thread { runAttempt(attempt, config) }.start()
        return START_STICKY
    }

    /**
     * Register-only command entry: the attempt exists and is owned, but the task has not been
     * scheduled yet. Used to exercise the dispatch window (queued, not yet running).
     */
    private fun commandStartQueued(config: String, requestedId: String?): Attempt =
        commandStart(config, requestedId, false)

    /** Command-entry point used by tests/adapters: registers and (optionally) starts the task. */
    private fun commandStart(config: String, requestedId: String?, startTask: Boolean = true): Attempt {
        val sid = if (requestedId.isNullOrEmpty()) {
            java.util.UUID.randomUUID().toString().replace("-", "").substring(0, 12)
        } else requestedId
        sessionId = sid
        val attempt = beginAttempt(sid)
        currentSessionId = attempt.id
        if (startTask) Thread { runAttempt(attempt, config) }.start()
        return attempt
    }

    private fun shutdown() {
        log("stop requested")
        // Astra 10-09 §3.2 (LATE_SHUTDOWN): capture the stop generation at entry. The TAIL of
        // this shutdown (handle clearing, foreground, stopSelf, isRunning, "Stopped") re-checks
        // the epoch before touching process-wide state; a newer attempt that registered while
        // this stop was blocked mid-cleanup keeps its own visible state and lifecycle.
        val stopEpoch = stopEpochCounter.incrementAndGet()
        // §6: capture the attempt being stopped, invalidate it (so nothing may publish or start
        // afterwards), then release exactly that attempt's resources — the same path a failure
        // termination uses, so the two can no longer diverge.
        val victim: Attempt?
        val victimPublishedTerminal: Boolean
        synchronized(attemptLock) {
            victim = currentAttempt
            currentAttempt?.valid = false
            currentAttempt?.terminated = true
            currentAttempt = null
            // [F1] R30-F1: if the failure path already published this session's terminal
            // (it won the lock before the user stop landed), the clean "Stopped" at the
            // tail must be skipped — two terminals can invert arrival order at Dart and
            // defeat the user-stop dialog suppression (device 2026-10-20: spurious
            // "data path lost" dialog on a successful disconnect).
            victimPublishedTerminal = victim?.terminalPublished == true
        }
        // [F1] R30-F1: if the failure terminal already landed, a post-terminal "Stopping"
        // would regress the state machine (Dart would end at Disconnecting, not Stopped) —
        // gate it with the same exactly-one-terminal rule.
        if (!victimPublishedTerminal) emitStatus("Stopping")
        try { victim?.let { releaseAttemptResources(it) } ?: run {
            // F1: no attempt context — stop only what the process still owns, and only while
            // THIS instance is still the active one. A stale cleanup must never globally stop
            // a newer generation's tunnel or core (Astra F1).
            // R20 §6 (NO_ATTEMPT_LOCK): the same single-flight coordinator as the attempt
            // path — decide+register under the lock, invoke OUTSIDE it, confirm under it.
            // No native call ever happens while processNativeLock is held.
            // R21 §4: the CONTEXT is captured at call time and re-verified INSIDE the lock at
            // each resource's admission — an old caller that waited behind the lock loses the
            // authority to stop a newer generation's resources (stale-no-attempt-destroy).
            stopAllNativeNoAttempt("shutdown", StopContext(this@XrayVpnService, stopEpoch))
            try { vpnPfd?.close() } catch (_: Exception) {}
        } } catch (e: Exception) { log("release error: ${e.javaClass.simpleName}") }
        // Astra 10-09 §3.2: generation re-check — if a NEWER stop/attempt happened while this
        // shutdown was mid-cleanup, THIS stop may not overwrite its visible state, clear its
        // handles, or kill the service lifecycle it owns.
        val stillCurrentStop = stopEpochCounter.get() == stopEpoch &&
            (victim != null || activeInstance === this@XrayVpnService)
        synchronized(attemptLock) {
            if (victim == null && stillCurrentStop) vpnPfd = null
            if (stillCurrentStop) tunFd = -1
        }
        if (!stillCurrentStop) {
            log("stale shutdown tail skipped: generation superseded (epoch $stopEpoch)")
            return
        }
        log("vpn handle released")
        stopForeground(true)
        stopSelf()
        isRunning = false
        if (victimPublishedTerminal) {
            // [F1] R30-F1: the failure path already published this session's terminal —
            // exactly one terminal per session; the clean duplicate is skipped.
            log("[F1] clean terminal skipped: failure terminal already published for this session")
        } else {
            emitStatus("Stopped")
        }
        log("stop finished")
    }

    /**
     * R01 §4.2: immutable identity + validity flag for ONE startup attempt.
     * - [valid]      : this attempt is still the current session (false once superseded/stopped)
     * - [terminated] : this attempt may no longer make progress (set when it is being torn down)
     * Lifecycle termination and terminal-state publication are handled by the coordinator
     * (`terminateFailedAttempt`) so a failed attempt still owns exactly one final snapshot (§4).
     */
    private class Attempt(val id: String) {
        @Volatile var valid = true
        @Volatile var terminated = false
        /** §4.2: credentials and config path belong to THIS attempt, never to service globals. */
        val creds: LocalCreds = LocalCreds()
        val hevConfigPath: String get() = "hev_config_$id.yml"
        val xrayConfigPath: String get() = "actual_config_$id.json"
        /** §6: the health monitor OWNED by this attempt. A stale attempt may only cancel its own. */
        @Volatile var healthThread: Thread? = null
        /** §6: sockets opened by this attempt's probes; closed on invalidation (not on GC/timeout). */
        @Volatile var probeSocket: java.net.Socket? = null
        /** §6: the tun handle THIS attempt installed, plus the fd it exposed (for exact release). */
        @Volatile var ownPfd: ParcelFileDescriptor? = null
        @Volatile var ownFd: Int = -1
        /**
         * [F1] R30-F1: exactly-one-terminal guard. A session's terminal state ("Stopped")
         * must be published exactly once — by the failure path OR by the user-stop path,
         * never both. The device race (2026-10-20): the health monitor published a failure
         * terminal just before the user stop invalidated the attempt, then shutdown()
         * published a second, clean "Stopped"; either arrival order at Dart defeats the
         * user-stop dialog suppression. Set under attemptLock by whichever path publishes
         * first; the other path must skip.
         */
        @Volatile var terminalPublished = false
    }

    /** Per-attempt local SOCKS credentials (replaces the shared proxyPort/User/Pass fields). */
    private class LocalCreds {
        var port: Int = 0
        var user: String = ""
        var pass: String = ""
    }

    /** Serialises attempt transitions AND global-resource operations (hev/Xray/PFD). */
    private val attemptLock = Any()
    @Volatile private var currentAttempt: Attempt? = null

    // Astra 10-09 §3.1: the native execution lock and the stop-confirmation flag are
    // PROCESS-LEVEL (companion). A recreated Service instance must share them with every
    // other instance, or an old instance's hung stop cannot exclude a new instance's start.
    private val nativeLock get() = processNativeLock
    private val coreStopPending get() = processCoreStopPending
    private fun setCoreStopPending(v: Boolean) { processCoreStopPending = v }

    /**
     * Astra R20 §6 (NO_ATTEMPT_LOCK): the no-attempt stop path used by shutdown and
     * onDestroy when no attempt context exists. Same coordinator protocol as the attempt
     * path — decide+register under nativeLock, invoke OUTSIDE the lock, confirm under
     * the lock. Single-flight: if a stop for the resource is already executing, WAIT for
     * its result instead of issuing a duplicate native call (the old path both held the
     * process lock across the invoke AND duplicated stops).
     */
    /**
     * Astra R21 §4 (STALE_NO_ATTEMPT): the caller carries an IMMUTABLE StopContext (the
     * instance and stop epoch it believes it is acting for). Admission re-verifies the
     * context INSIDE the lock, for EACH resource, as part of the SAME atomic decision as
     * the single-flight registration — the old code checked activeInstance/epoch once
     * before acquiring the lock, waited, and then admitted the stop even though B had
     * taken over while it waited. Single-flight bounds concurrency; the in-lock context
     * re-check is what bounds AUTHORITY.
     *
     * Astra R21 §5 (HEV_RETRY_RECOVERY): the same live entry also drives the retry for a
     * resource whose previous stop landed Unconfirmed (its owner is already null, so
     * owner-gated entries can never reach it): if the retry CONFIRMS, the takeover block
     * is lifted; if it fails again, the block stays.
     */
    private fun stopAllNativeNoAttempt(reason: String, ctx: StopContext) {
        // hev — admission re-checks the caller's context INSIDE the lock.
        val hevAdmission: Pair<Long, Boolean>
        nativeLock.lock()
        try {
            val ctxStillValid = activeInstance === ctx.expectedInstance &&
                stopEpochCounter.get() == ctx.stopEpoch
            // Stop the hev tunnel only when the process still owns one AND the caller's
            // generation is still the current one. A stale no-attempt cleanup must never
            // stop a newer generation's worker (Astra R21 stale-no-attempt-destroy).
            val stopIsOurs = ctxStillValid && hevOwner != null
            // R21 §5: an Unconfirmed hev stop with a cleared owner still needs a LIVE stop
            // command to retry — that retry is the only reachable recovery path.
            val retryNeeded = ctxStillValid && hevOwner == null && hevStopNeedsRetry
            if (stopIsOurs || retryNeeded) {
                hevAdmission = admitStop(hevStopState)
                if (hevAdmission.second && stopIsOurs) hevOwner = null
            } else {
                hevAdmission = Pair(-1L, false)
            }
        } finally {
            nativeLock.unlock()
        }
        if (hevAdmission.second) {
            var hevConfirmed = false
            try { hevConfirmed = hevStop() } catch (e: Exception) { log("$reason hevStop: ${e.javaClass.simpleName}") }
            nativeLock.lock()
            try {
                if (commitStop(hevStopState, hevAdmission.first, hevConfirmed)) {
                    // R21 §5: the takeover block lifts ONLY on a CONFIRMED stop.
                    hevStopNeedsRetry = !hevConfirmed
                }
            } finally { nativeLock.unlock() }
        } else if (hevAdmission.first != -1L) {
            val wUntil = System.currentTimeMillis() + CORE_HANDOFF_TIMEOUT_MS
            while (hevStopState.get() is StopPhase.Stopping && System.currentTimeMillis() < wUntil) {
                try { Thread.sleep(10) } catch (_: InterruptedException) { break }
            }
        }
        // core — same protocol: context re-checked inside the lock, invoke outside it.
        val coreAdmission: Pair<Long, Boolean>
        nativeLock.lock()
        try {
            val ctxStillValid = activeInstance === ctx.expectedInstance &&
                stopEpochCounter.get() == ctx.stopEpoch
            val stopIsOurs = ctxStillValid && nativeCoreOwner != null
            val retryNeeded = ctxStillValid && nativeCoreOwner == null && coreStopNeedsRetry
            if (stopIsOurs || retryNeeded) {
                coreAdmission = admitStop(coreStopState)
                if (coreAdmission.second && stopIsOurs) processCoreStopPending = true
            } else {
                coreAdmission = Pair(-1L, false)
            }
        } finally {
            nativeLock.unlock()
        }
        if (coreAdmission.second) {
            var coreConfirmed = false
            try {
                val reply = libXray.LibXray.invoke("""{"apiVersion":1,"method":"stopXray"}""")
                coreConfirmed = parseStopReply(reply)
            } catch (e: Exception) { log("$reason stopXray: ${e.javaClass.simpleName}") }
            nativeLock.lock()
            try {
                if (commitStop(coreStopState, coreAdmission.first, coreConfirmed)) {
                    if (coreConfirmed) {
                        if (coreAdmissionNeedsOwnerClear()) nativeCoreOwner = null
                        processCoreStopPending = false
                        coreStopNeedsRetry = false
                    } else {
                        coreStopNeedsRetry = true
                    }
                }
            } finally { nativeLock.unlock() }
        } else if (coreAdmission.first != -1L) {
            val wUntil = System.currentTimeMillis() + CORE_HANDOFF_TIMEOUT_MS
            while (coreStopState.get() is StopPhase.Stopping && System.currentTimeMillis() < wUntil) {
                try { Thread.sleep(10) } catch (_: InterruptedException) { break }
            }
        }
    }

    /** Core owner clear after a confirmed stop is safe only when the caller's ctx still owns it. */
    private fun coreAdmissionNeedsOwnerClear(): Boolean {
        // After a CONFIRMED stop the global core is down; clearing the owner is bookkeeping
        // for the generation that ran the stop. The in-lock admission already re-checked the
        // caller's context; a confirmed stop may clear the CURRENT owner unconditionally —
        // the core is provably stopped, so no newer generation can be killed by the clear.
        return true
    }



    /**
     * Astra 10-09 §3.1: the former INSTANCE-level ReentrantLock and coreStopPending live on the
     * companion now (processNativeLock / processCoreStopPending, see above). The comment block
     * that described their old semantics is superseded — one process, one lock, one flag.
     *
     * Native STARTS use tryLock(CORE_HANDOFF_TIMEOUT_MS) and fail closed with CONFLICT.
     * Native STOPS (release path, destroy, global stop) keep blocking lock() — teardown must
     * complete and must never be starved by a start.
     *
     * Ordering is always attemptLock → nativeLock; never the reverse (no lock-order cycle).
     */

    private fun beginAttempt(id: String): Attempt = synchronized(attemptLock) {
        // Registering never waits for native teardown; only starting a core does (§6 boundary 1).
        // Astra 10-09 §3.2: a NEW attempt is a new generation — any older stop whose tail is
        // still mid-cleanup loses the right to publish Stopped / clear handles / stopSelf.
        stopEpochCounter.incrementAndGet()
        currentAttempt?.valid = false
        val a = Attempt(id)
        currentAttempt = a
        a
    }

    private fun isActive(a: Attempt): Boolean = synchronized(attemptLock) {
        a.valid && !a.terminated && currentAttempt === a
    }

    /** §6: ownership test for callers that ALREADY hold attemptLock. */
    private fun attemptIsCurrentLocked(a: Attempt): Boolean = a.valid && !a.terminated && currentAttempt === a

    /** §6: ownership test used by resource installation (never called while holding attemptLock). */
    private fun attemptIsCurrent(a: Attempt): Boolean = synchronized(attemptLock) {
        a.valid && !a.terminated && currentAttempt === a
    }

    /** Called on stop/destroy: no attempt may publish or touch resources afterwards.
     *  F1 (Astra R11): returns the captured victim — the destroy path must capture the attempt
     *  BEFORE it is dropped; reading currentAttempt after invalidation always yields null and
     *  forced every destroy into the global-stop branch (Astra F1 cross-instance destroy). */
    private fun invalidateCurrentAttempt(): Attempt? {
        val victim: Attempt?
        synchronized(attemptLock) {
            victim = currentAttempt
            currentAttempt?.valid = false
            currentAttempt?.terminated = true
            currentAttempt = null
        }
        // §6: cancel only the resources OWNED by the invalidated attempt (its own monitor and its
        // own probe socket) — never a shared/unowned field that a new generation may have installed.
        victim?.let {
            it.healthThread?.interrupt()
            it.healthThread = null
            try { it.probeSocket?.close() } catch (_: Exception) {}
            it.probeSocket = null
        }
        return victim
    }

    /**
     * §4/§5.3: coordinator-owned termination. Ownership check, resource release and the terminal
     * snapshot commit all happen under ONE lock, in that order — so the failure state is actually
     * published (the old code invalidated the attempt first and then filtered its own terminal event).
     */
    private fun terminateFailedAttempt(
        a: Attempt,
        alert: String,
        message: String?,
        errorCode: String?,
    ): Boolean {
        // §6: retract the user-visible readiness promise IMMEDIATELY, before any native call.
        // A blocking stopXray must not keep the UI showing Started (Astra: BLOCKING_CORE_STOP).
        val published: Boolean
        synchronized(attemptLock) {
            if (!a.valid || currentAttempt !== a) {
                log("terminate skipped: attempt ${a.id} is not current")
                return false
            }
            // [F1] R30-F1: exactly-one-terminal — a second termination of the same attempt
            // (failure path + user stop racing) must not publish a second terminal.
            if (a.terminalPublished) {
                log("terminate skipped: attempt ${a.id} terminal already published")
                return false
            }
            a.terminalPublished = true
            // 1. stop further progress of THIS attempt
            a.terminated = true
            // 2. commit the terminal snapshot here (NOT via commitLocked — the attempt is already
            //    marked terminated, and this termination still owns exactly one final snapshot).
            val snapshot = SessionState(a.id, "Stopped", errorCode, seqCounter.incrementAndGet())
            currentState = snapshot
            isRunning = false
            log("emitStatus: Stopped attempt=${a.id} errorCode=$errorCode (terminal)")
            mainHandler.post {
                try {
                    statusSink?.success(
                        mapOf(
                            "status" to snapshot.phase,
                            "alert" to alert,
                            "message" to message,
                            "errorCode" to snapshot.errorCode,
                            "sessionId" to snapshot.sessionId,
                            "seq" to snapshot.seq,
                        )
                    )
                } catch (e: Exception) { log("terminate post error: $e") }
            }
            published = true
        }
        // 3. release the attempt's resources for real, OFF the ownership lock. The new generation
        //    is not allowed to take the native core over until this cleanup is confirmed (§6), so
        //    ownership of the OLD resources is retained here rather than dropped silently.
        val cleaned = releaseAttemptResources(a)
        try { stopForeground(true) } catch (_: Exception) {}
        log("terminate done attempt=${a.id} errorCode=$errorCode cleaned=$cleaned")
        return published
    }

    /**
     * §6: stop this attempt's native resources (hev + core + its tun handle) and report whether the
     * core stop was confirmed. Runs off the ownership lock so a blocking JNI call cannot stall
     * attempt registration. Confirmed completion is what allows a new generation to take over.
     */
    private fun releaseAttemptResources(a: Attempt): Boolean {
        // Astra 10-09 §3.3 (HUNG_STOP_B): THIS attempt's own resources — monitor, probe socket
        // and its TUN handle — are released BEFORE entering the global native lock. They belong
        // to the attempt, not to the global core; a hung previous stopXray must not keep this
        // attempt's TUN handle alive after its terminal state is already published.
        a.healthThread?.interrupt()          // only THIS attempt's monitor
        a.healthThread = null
        try { a.probeSocket?.close() } catch (_: Exception) {}   // unblock a blocked probe read
        a.probeSocket = null
        try { a.ownPfd?.close() } catch (_: Exception) {}
        a.ownPfd = null
        var coreStopped = true
        // Astra R20 §4/§5/§6: single-flight per-resource stop coordinator. Same-attempt
        // concurrent stops (failure cleanup + active shutdown) now WAIT for the first
        // operation's result instead of issuing a second invoke under a shared token.
        // The hev and core invokes stay OUTSIDE nativeLock (no native call under the lock).
        nativeLock.lock()
        val hevWasOurs: Boolean
        val hevRetryOurs: Boolean
        var hevAdmission: Pair<Long, Boolean> = Pair(-1L, false)
        try {
            hevWasOurs = hevOwner == a.id
            // R21 §5 (HEV_RETRY_RECOVERY): a live attempt cleanup is ALSO a reachable retry
            // entry for an Unconfirmed hev stop whose owner was already cleared — without
            // this, no stop entry could ever clear the block (owner-gated entries only).
            hevRetryOurs = !hevWasOurs && hevStopNeedsRetry
            if (hevWasOurs) {
                hevOwner = null
                hevAdmission = admitStop(hevStopState)
            } else if (hevRetryOurs) {
                hevAdmission = admitStop(hevStopState)
            }
        } finally {
            nativeLock.unlock()
        }
        if (hevWasOurs || hevRetryOurs) {
            if (hevAdmission.second) {
                // THIS operation executes the global hevStop — outside the lock.
                var hevConfirmed = false
                try {
                    hevConfirmed = hevStop()
                } catch (e: Exception) {
                    log("cleanup hevStop: ${e.javaClass.simpleName}")
                    // R20 §5: an EXCEPTION is an UNCONFIRMED stop — the resource's real state
                    // is unknown, so it becomes a takeover block. Never treat as success.
                    hevConfirmed = false
                }
                nativeLock.lock()
                try {
                    // R20 §5: hevStop's Boolean return is honored — false means the stop was
                    // not confirmed by the native layer; exception and false both land in
                    // Unconfirmed, which blocks hev takeover (fail closed).
                    // R21 §5: the retry record follows the commit — cleared only on CONFIRMED.
                    if (commitStop(hevStopState, hevAdmission.first, hevConfirmed)) {
                        hevStopNeedsRetry = !hevConfirmed
                    }
                } finally {
                    nativeLock.unlock()
                }
            } else {
                // Single-flight wait: another operation is stopping hev — wait (bounded) for
                // ITS result and reuse it; never issue a second hevStop invoke.
                val wUntil = System.currentTimeMillis() + CORE_HANDOFF_TIMEOUT_MS
                while (hevStopState.get() is StopPhase.Stopping && System.currentTimeMillis() < wUntil) {
                    try { Thread.sleep(10) } catch (_: InterruptedException) { break }
                }
            }
        }
        var stopReply: String? = null
        var stopThrew: Boolean = false
        var snapshotOwner: String? = null
        var coreAdmission: Pair<Long, Boolean> = Pair(-1L, false)
        nativeLock.lock()
        try {
            if (nativeCoreOwner == a.id) {
                snapshotOwner = a.id
                setCoreStopPending(true)
                coreAdmission = admitStop(coreStopState)
            }
        } finally {
            nativeLock.unlock()
        }
        if (snapshotOwner != null) {
            if (coreAdmission.second) {
                // THIS operation executes the global stopXray — outside the lock.
                try {
                    stopReply = libXray.LibXray.invoke("""{"apiVersion":1,"method":"stopXray"}""")
                } catch (e: Exception) {
                    stopThrew = true
                    log("cleanup stopXray: ${e.javaClass.simpleName}")
                }
                nativeLock.lock()
                try {
                    val confirmed = !stopThrew && stopReply != null && parseStopReply(stopReply)
                    // Astra 10-09 §3.4: "returned" is not "stopped" — parse the reply. The
                    // commit is operation-bounded: only THIS opId still owns the Stopping
                    // phase. coreStopPending carries UNCONFIRMED forward to the next start
                    // (fail closed with CONFLICT).
                    if (commitStop(coreStopState, coreAdmission.first, confirmed)) {
                        if (confirmed) {
                            nativeCoreOwner = null
                            setCoreStopPending(false)
                            coreStopNeedsRetry = false
                        } else {
                            coreStopped = false
                            setCoreStopPending(true)
                            coreStopNeedsRetry = true
                        }
                    } else {
                        // A superseding operation owns the phase (our invoke was a late
                        // duplicate) — leave owner bookkeeping to it.
                        log("cleanup stopXray: stop phase superseded during invoke; not committing")
                    }
                } finally {
                    nativeLock.unlock()
                }
            } else {
                // Single-flight wait: reuse the in-flight core stop's result.
                val wUntil = System.currentTimeMillis() + CORE_HANDOFF_TIMEOUT_MS
                while (coreStopState.get() is StopPhase.Stopping && System.currentTimeMillis() < wUntil) {
                    try { Thread.sleep(10) } catch (_: InterruptedException) { break }
                }
            }
        }
        synchronized(attemptLock) {
            // Only clear the service-level handles if they still belong to THIS attempt.
            if (currentAttempt === null || currentAttempt === a) {
                if (vpnPfd != null && (a.ownPfd == null)) vpnPfd = null
                if (tunFd == a.ownFd) tunFd = -1
            }
        }
        return coreStopped
    }

    /**
     * §5.3: commit a phase transition and its visible state atomically, then emit the frozen event.
     */
    private fun commitLocked(
        a: Attempt?,
        status: String,
        alert: String?,
        message: String?,
        errorCode: String?,
    ): Boolean {
        if (a != null && (!a.valid || a.terminated)) return false
        val sid = a?.id ?: sessionId
        val snapshot = SessionState(sid, status, errorCode, seqCounter.incrementAndGet())
        currentState = snapshot
        log("emitStatus: $status attempt=$sid errorCode=$errorCode")
        mainHandler.post {
            try {
                statusSink?.success(
                    mapOf(
                        "status" to snapshot.phase,
                        "alert" to alert,
                        "message" to message,
                        "errorCode" to snapshot.errorCode,
                        "sessionId" to snapshot.sessionId,
                        "seq" to snapshot.seq,
                    )
                )
            } catch (e: Exception) {
                log("emitStatus post error: $e")
            }
        }
        return true
    }

    /**
     * Publish a state event for [a]. Uses an immutable snapshot captured at emit time so the event
     * can never be labelled with a newer attempt's id after being queued (§4.2 item 1).
     */
    private fun emitStatusFor(
        a: Attempt?,
        status: String,
        alert: String? = null,
        message: String? = null,
        errorCode: String? = null,
    ) {
        // commit owns the ordering; a filtered attempt simply produces no event.
        synchronized(attemptLock) {
            val ok = commitLocked(a, status, alert, message, errorCode)
            if (!ok) log("skip stale event: attempt ${a?.id} invalid/terminated")
        }
    }

    /**
     * §4.1: the background task executes an attempt that was ALREADY registered at the command
     * entry. It never registers a new attempt and never re-reads the mutable session id, so a stop
     * that happened before this task was scheduled (or a later command that rewrote the shared
     * field) cannot give this task a new identity.
     */
    private fun runAttempt(attempt: Attempt, xrayJson: String) {
        if (!isActive(attempt)) {
            log("task skipped: attempt ${attempt.id} is not active at task entry")
            return
        }
        emitStatusFor(attempt, "Starting")
        try {
            if (!isActive(attempt)) {
                log("abort: attempt ${attempt.id} invalid before startup")
                return
            }
            runStartup(attempt, xrayJson)
        } catch (t: Throwable) {
            // §4: one controlled termination path for the entire startup, including its final state.
            log("startup exception: ${t.javaClass.simpleName}")
            terminateFailedAttempt(attempt, "startFailed", "internal startup error", "INTERNAL_ERROR")
        }
    }

    private fun runStartup(attempt: Attempt, xrayJson: String) {
        // 1. Establish TUN — the established fd first belongs to THIS attempt locally; it is only
        // installed as the current resource after ownership is confirmed under the lock (§5.2).
        val tun = establishTun(attempt)
        if (tun == null) {
            if (isActive(attempt)) {
                terminateFailedAttempt(attempt, "startFailed", "tun setup failed", "TUN_FAILED")
            }
            return
        }
        if (!isActive(attempt)) {
            // stale result: close our own handle, never touch the current resource
            try { tun.pfd.close() } catch (_: Exception) {}
            log("late tun discarded for attempt ${attempt.id}")
            return
        }
        updateNotification("TUN: ${tun.summary}")

        // 2. Generate ephemeral credentials for local SOCKS5 bridge (owned by THIS attempt)
        generateProxyCredentials(attempt)
        if (!isActive(attempt)) { log("abort: attempt ${attempt.id} invalid after credentials"); return }

        // 3. Write hev config to an ATTEMPT-SCOPED path (a stale attempt never rewrites the
        //    file another attempt is using). Exceptions are caught by the runAttempt wrapper.
        val hevConfig = File(filesDir, attempt.hevConfigPath)
        hevConfig.writeText(buildHevConfig(attempt))

        // 4. Start hev tun2socks — native execution and the hev OWNERSHIP TRANSITION run under
        //    the PROCESS-level nativeLock (F1: the release path's owned hevStop must be atomic
        //    against a concurrent start). Ownership is re-checked under attemptLock in a SHORT
        //    critical section, and the JNI call happens OUTSIDE attemptLock (Astra 10-09 §3.4:
        //    "never hold attemptLock across a JNI call" — the previous code called hevStart
        //    inside the synchronized block). Lock-order is nativeLock → attemptLock and never
        //    the reverse, so no cycle exists.
        //    F2: BOUNDED acquisition — a hung previous stop must fail this start after the
        //    handoff budget with an explicit reason, not block forever.
        var hevOk = false
        // Astra R20 §4/§5: the hev start path fences on the SAME single-flight stop
        // coordinator as the core start: it must wait while EITHER resource's stop is
        // Stopping (an executing global stop may kill a freshly started worker), and it
        // must refuse (fail closed) while any prior stop left the resource UNCONFIRMED.
        // Registration is not blocked (登记≠启动); only the native invoke is.
        val hevWaitUntil = System.currentTimeMillis() + CORE_HANDOFF_TIMEOUT_MS
        while ((hevStopState.get() is StopPhase.Stopping || coreStopState.get() is StopPhase.Stopping) &&
            System.currentTimeMillis() < hevWaitUntil) {
            try { Thread.sleep(10) } catch (_: InterruptedException) { break }
        }
        val hevLockTaken = nativeLock.tryLock(CORE_HANDOFF_TIMEOUT_MS, java.util.concurrent.TimeUnit.MILLISECONDS)
        try {
            if (!hevLockTaken) {
                log("hev start aborted: native lock not available within budget (attempt ${attempt.id})")
            } else {
                // Fail closed — an executing stop on EITHER resource, or an UNCONFIRMED prior
                // hev stop (exception / false return / never confirmed), may not be taken
                // over by a fresh hev start. R20 §5: hevOwner=null alone is NOT a fence.
                if (hevStopState.get() is StopPhase.Stopping || coreStopState.get() is StopPhase.Stopping) {
                    log("hev start aborted: previous stop still in flight/unconfirmed (attempt ${attempt.id})")
                } else if (hevStopTakeoverBlocked()) {
                    log("hev start aborted: previous hev stop unconfirmed (attempt ${attempt.id})")
                } else {
                val stillCurrent = synchronized(attemptLock) { attemptIsCurrentLocked(attempt) }
                if (stillCurrent) {
                    val ok = hevStart(hevConfig.absolutePath, tunFd)
                    // F1: the hev tunnel belongs to THIS attempt the moment it starts.
                    hevOwner = if (ok) attempt.id else null
                    hevOk = ok
                    if (ok) {
                        // A successful new hev start is itself proof the takeover block no
                        // longer applies (the native layer accepted the new worker) — the
                        // Confirmed phase from the stop that preceded it stands.
                    }
                } else {
                    log("hev start skipped: attempt ${attempt.id} is stale")
                }
                }
            }
        } finally {
            if (hevLockTaken) nativeLock.unlock()
        }
        log("hev start: $hevOk")
        if (!isActive(attempt)) { log("abort: attempt ${attempt.id} invalid after hev"); return }
        if (!hevOk) {
            // Astra R20 §7.1 (hung-handoff error classification): a takeover CONFLICT (the
            // previous stop never confirmed within budget, so hevStart was NEVER CALLED) is
            // not an "hev start failed" — it is a handoff conflict, reported as CONFLICT.
            // HEV_FAILED remains reserved for a REAL hevStart invocation that failed.
            val blockedByStop = hevStopTakeoverBlocked() ||
                hevStopState.get() is StopPhase.Stopping || coreStopState.get() is StopPhase.Stopping
            if (blockedByStop) {
                updateNotification("handoff conflict")
                terminateFailedAttempt(attempt, "startFailed", "previous native stop not confirmed", "CONFLICT")
            } else {
                updateNotification("hev failed")
                terminateFailedAttempt(attempt, "startFailed", "hev start failed", "HEV_FAILED")
            }
            return
        }

        // 5. Start Xray (SOCKS5-in auth -> Reality out)
        val xrayResult = runXray(xrayJson, attempt)
        // §4.2 items 1/3: a result from a superseded or stopped attempt must not be published.
        if (!isActive(attempt)) {
            log("discard result of invalid attempt ${attempt.id}")
            return
        }
        if (xrayResult is XrayInvokeResult.Accepted) {
            // §8-2 state contract: core acceptance is NOT data-path readiness. Publish Started only
            // after this attempt's authenticated SOCKS path is proven usable.
            log("core accepted; probing data path attempt=${attempt.id}")
            val ready = probeDataPath(attempt)
            if (!isActive(attempt)) {
                log("abort: attempt ${attempt.id} invalid during readiness probe")
                return
            }
            if (ready) {
                // §5.3: the ready notification, the running flag and the snapshot commit belong to
                // the SAME critical section — a stop landing between them must not observe a torn state.
                synchronized(attemptLock) {
                    if (attempt.valid && !attempt.terminated && currentAttempt === attempt) {
                        updateNotification("Xray core ready")
                        isRunning = true
                        commitLocked(attempt, "Started", null, null, null)
                        // WO-5: sampling stops when the tunnel goes down; a reconnect must
                        // resume it (the stats EventChannel listener survives across sessions).
                        startStatsSampling()
                    }
                }
                startHealthMonitor(attempt)
            } else {
                log("data path probe failed for attempt ${attempt.id}")
                terminateFailedAttempt(attempt, "startFailed", "data path not ready", "PROBE_FAILED")
            }
        } else if (xrayResult is XrayInvokeResult.Failed) {
            log("xray start failed kind=${xrayResult.kind}")
            terminateFailedAttempt(attempt, "startFailed", xrayResult.safeMessage, xrayResult.kind.name)
        }
    }

    // ── §8-2 data-path readiness /持续健康 ─────────────────────────────────────

    /**
     * Verifies the data path actually works through THIS attempt's authenticated SOCKS inbound.
     * Bounded total deadline, per-attempt timeouts, a small retry budget and a bounded fallback
     * target list. There is deliberately NO direct-connection fallback: a probe that bypasses the
     * tunnel would prove nothing about the tunnel.
     *
     * Astra R18.1 §6/§9.3 (unified budget): the per-try budget covers the WHOLE try
     * (SOCKS + TLS) — the same deadline governs waiting AND the success verdict, and the
     * fallback target is guaranteed a fair share of the total budget: each TARGET gets at
     * most half of the total, so the primary target's consecutive timeouts can never starve
     * the fallback out of the round.
     */
    private fun probeDataPath(a: Attempt): Boolean {
        probeHook?.let { return it() }
        val targets = listOf(PROBE_TARGET_PRIMARY, PROBE_TARGET_FALLBACK)
        // §6.3: ONE monotonic deadline for the whole probe. Every attempt, target and gap derives its
        // own timeout from what is left of this budget, so retries cannot multiply the total.
        val deadlineNanos = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(PROBE_TOTAL_MS)
        try { Thread.sleep(PROBE_SETTLE_MS) } catch (_: InterruptedException) { return false }
        for ((host, port) in targets) {
            // §9.3: per-TARGET share of the remaining total — the primary may use at most half
            // of what is left when it starts, guaranteeing the fallback a fair window.
            val targetDeadline = minOf(
                deadlineNanos,
                System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(remainingMs(deadlineNanos).toLong() / 2),
            )
            var tries = 0
            while (tries < PROBE_RETRIES && remainingMs(targetDeadline) > 0) {
                tries++
                if (!isActive(a)) return false
                // §9.3: the slice covers the ENTIRE try — SOCKS stages AND TLS. The same
                // try deadline is used for the TLS watchdog join and for the success
                // verdict (socksProbeTlsWithin), so waiting and judgement share one budget.
                val slice = minOf(PROBE_SINGLE_MS.toLong(), remainingMs(targetDeadline).toLong())
                if (slice <= 0) break
                if (socksProbeTlsWithin(a, host, port, slice.toInt(), targetDeadline)) return true
                log("probe attempt ${a.id} target=$host try=$tries failed")
                val gap = minOf(PROBE_RETRY_GAP_MS, remainingMs(targetDeadline).toLong())
                if (gap <= 0) break
                try { Thread.sleep(gap) } catch (_: InterruptedException) { return false }
            }
        }
        return false
    }

    /**
     * §6 (Astra R08 §6.2/6.3/6.4): a TRUSTWORTHY readiness probe.
     *
     *  - Strict SOCKS5 per RFC 1928 / RFC 1929: this probe is an AUTHENTICATION probe, so it offers
     *    ONLY username/password (05 01 02) and rejects anything else, including a server that
     *    selects no-auth. Every response field is validated (VER/RSV/REP, and the bound-address
     *    length); lengths are read as UNSIGNED bytes.
     *  - Real total deadline on a monotonic clock: the remaining budget is recomputed for every
     *    connect/read/write/sleep phase, and re-checked before reporting success. SO_TIMEOUT only
     *    bounds one read and is therefore never treated as the total.
     *  - The socket belongs to the attempt: it is published so a stop can close it and unblock the
     *    read, instead of waiting for a timeout.
     */
    private fun socksProbeTls(a: Attempt, host: String, port: Int, timeoutMs: Int): Boolean =
        socksProbeTlsWithin(a, host, port, timeoutMs, System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(timeoutMs.toLong()))

    private fun socksProbeTlsWithin(a: Attempt, host: String, port: Int, timeoutMs: Int, deadlineNanos: Long): Boolean {
        // Astra 10-09 §5 (PER_TRY): the per-try timeout must actually bound THIS try. The old
        // code passed timeoutMs but then used only the WHOLE-ROUND deadline everywhere, so a
        // single silent target could consume the entire budget and starve retries/fallbacks.
        // Effective deadline = min(total deadline, this try's start + per-try budget).
        val tryDeadlineNanos = minOf(
            deadlineNanos,
            System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(timeoutMs.toLong()),
        )
        var sock: Socket? = null
        try {
            val budgetMs = remainingMs(tryDeadlineNanos)
            if (budgetMs <= 0) { log("probe: no budget left before connect"); return false }
            sock = Socket()
            a.probeSocket = sock            // §6: owned by the attempt, so a stop can unblock us
            sock.connect(InetSocketAddress("127.0.0.1", a.creds.port), budgetMs)

            // §6.2 RFC 1928 greeting: VER=05, NMETHODS=1, METHODS=[02 user/pass] ONLY.
            // Offering 00 (no-auth) would let the server silently downgrade the probe.
            val out = sock.getOutputStream()
            val inp = sock.getInputStream()
            writeAll(sock, out, byteArrayOf(0x05, 0x01, 0x02), tryDeadlineNanos)
            val greeting = ByteArray(2)
            if (!readFully(sock, inp, greeting, 2, tryDeadlineNanos)) return false
            if (u(greeting[0]) != 0x05) { log("probe: bad greeting VER ${u(greeting[0])}"); return false }
            if (u(greeting[1]) != 0x02) {
                // Includes 0x00 (server chose no-auth): an authentication probe must reject that.
                log("probe: server did not select user/pass auth (method ${u(greeting[1])})")
                return false
            }

            // §6.2 RFC 1929: VER=01, ULEN, UNAME, PLEN, PASSWD
            val un = a.creds.user.toByteArray()
            val pw = a.creds.pass.toByteArray()
            if (un.isEmpty() || un.size > 255 || pw.isEmpty() || pw.size > 255) {
                log("probe: credential length out of range"); return false
            }
            val auth = ByteArray(3 + un.size + pw.size)
            auth[0] = 0x01; auth[1] = un.size.toByte()
            un.copyInto(auth, 2)
            auth[2 + un.size] = pw.size.toByte()
            pw.copyInto(auth, 3 + un.size)
            writeAll(sock, out, auth, tryDeadlineNanos)
            val authRep = ByteArray(2)
            if (!readFully(sock, inp, authRep, 2, tryDeadlineNanos)) return false
            if (u(authRep[0]) != 0x01) { log("probe: bad auth reply VER ${u(authRep[0])}"); return false }
            if (u(authRep[1]) != 0x00) { log("probe: authentication rejected"); return false }

            // §6.2 RFC 1928 CONNECT: VER=05, CMD=01, RSV=00, ATYP=03 (domain), host, port
            val hb = host.toByteArray(Charsets.US_ASCII)
            if (hb.isEmpty() || hb.size > 255) { log("probe: host length out of range"); return false }
            val req = ByteArray(7 + hb.size)
            req[0] = 0x05; req[1] = 0x01; req[2] = 0x00; req[3] = 0x03
            req[4] = hb.size.toByte()
            hb.copyInto(req, 5)
            req[5 + hb.size] = (port ushr 8).toByte()
            req[6 + hb.size] = (port and 0xFF).toByte()
            writeAll(sock, out, req, tryDeadlineNanos)

            // §6.2 reply: VER=05, REP=00, RSV=00, then the bound address whose length we validate.
            val rep = ByteArray(4)
            if (!readFully(sock, inp, rep, 4, tryDeadlineNanos)) return false
            if (u(rep[0]) != 0x05) { log("probe: bad reply VER ${u(rep[0])}"); return false }
            if (u(rep[1]) != 0x00) { log("probe: connect rejected REP=${u(rep[1])}"); return false }
            if (u(rep[2]) != 0x00) { log("probe: bad reply RSV ${u(rep[2])}"); return false }
            val bound = when (u(rep[3])) {
                0x01 -> 4 + 2      // IPv4
                0x04 -> 16 + 2     // IPv6
                0x03 -> {
                    val l = ByteArray(1)
                    if (!readFully(sock, inp, l, 1, tryDeadlineNanos)) return false
                    val len = u(l[0])            // unsigned — a negative Byte here would under-count
                    len + 2
                }
                else -> { log("probe: bad ATYP ${u(rep[3])}"); return false }
            }
            if (bound <= 0 || !readFully(sock, inp, ByteArray(bound), bound, tryDeadlineNanos)) return false

            // TLS with hostname verification: proves a real remote endpoint answered through the path.
            // Astra R18.1 §6/§9.3 (TLS_SINGLE, unified budget): the per-try deadline covers the
            // WHOLE try — SOCKS stages AND TLS. Previously the watchdog waited on the TOTAL
            // deadline while the success verdict used the per-try one: a healthy handshake that
            // finished after the try budget was waited for, then REJECTED ("waited long, judged
            // short"). One deadline (tryDeadlineNanos) now governs the soTimeout, the watchdog
            // join AND the success verdict — waiting and judgement share one budget semantic.
            // The probe-level per-target share (probeDataPath) guarantees the fallback target a
            // fair window, so a per-try 6s bound cannot starve it.
            val ssl = (SSLSocketFactory.getDefault() as SSLSocketFactory)
                .createSocket(sock, host, port, true) as SSLSocket
            ssl.soTimeout = remainingMs(tryDeadlineNanos).coerceAtLeast(1)
            val params = ssl.sslParameters
            params.endpointIdentificationAlgorithm = "HTTPS"
            ssl.sslParameters = params
            val handshakeError = java.util.concurrent.atomic.AtomicReference<Throwable?>(null)
            val handshaker = Thread {
                try { ssl.startHandshake() } catch (t: Throwable) { handshakeError.set(t) }
            }.apply { isDaemon = true; start() }
            // Join with the remaining PER-TRY budget — the same budget the verdict uses.
            val joinBudget = remainingMs(tryDeadlineNanos).coerceAtLeast(1).toLong()
            handshaker.join(joinBudget)
            if (handshaker.isAlive) {
                log("probe: TLS handshake exceeded per-try budget; aborting socket")
                try { ssl.close() } catch (_: Exception) {}
                try { sock.close() } catch (_: Exception) {}
                handshaker.join(500)
                return false
            }
            handshakeError.get()?.let { throw it }
            ssl.close()
            // §6.3: the try deadline is authoritative — success is only reported while in budget.
            if (System.nanoTime() > tryDeadlineNanos) { log("probe: per-try budget expired after handshake"); return false }
            return true
        } catch (e: Exception) {
            log("probe error: ${e.javaClass.simpleName}")
            return false
        } finally {
            try { sock?.close() } catch (_: Exception) {}
            if (a.probeSocket === sock) a.probeSocket = null
        }
    }

    /** Unsigned byte value (RFC lengths are unsigned). */
    private fun u(b: Byte): Int = b.toInt() and 0xFF

    /** Remaining budget in ms on the monotonic clock, never negative. */
    private fun remainingMs(deadlineNanos: Long): Int {
        val left = (deadlineNanos - System.nanoTime()) / 1_000_000L
        return if (left <= 0) 0 else left.coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
    }

    /** Write with the remaining budget applied to the socket, so a write cannot outlive the total.
     *  F3 (Astra): the Socket is passed EXPLICITLY — the budget is applied to soTimeout on the
     *  real socket instead of reflecting the stream back to it (reflection was rejected on some
     *  OEM builds, silently disabling the deadline). */
    private fun writeAll(sock: Socket?, out: java.io.OutputStream, data: ByteArray, deadlineNanos: Long): Boolean {
        val budget = remainingMs(deadlineNanos)
        if (budget <= 0) return false
        try { sock?.soTimeout = budget } catch (_: Exception) {}
        out.write(data); out.flush()
        return true
    }

    /**
     * §6.3: read exactly [len] bytes within the TOTAL deadline. SO_TIMEOUT is refreshed from the
     * remaining budget before each read, so a slow drip cannot exceed the overall budget.
     * F3 (Astra): [sock] is passed explicitly — no private-field reflection to recover it.
     * Returns false on short read, timeout or expiry (never throws past the caller).
     */
    private fun readFully(sock: Socket?, inp: java.io.InputStream, buf: ByteArray, len: Int, deadlineNanos: Long): Boolean {
        var off = 0
        while (off < len) {
            val budget = remainingMs(deadlineNanos)
            if (budget <= 0) { log("probe: budget expired while reading"); return false }
            try { sock?.soTimeout = budget } catch (_: Exception) {}
            val n = try { inp.read(buf, off, len - off) } catch (e: Exception) {
                log("probe read failed: ${e.javaClass.simpleName}"); return false
            }
            if (n < 0) { log("probe: short read"); return false }
            off += n
        }
        return true
    }

    /**
     * §8-2 ongoing health: after Started, keep verifying the data path. Loss of readiness retracts
     * Connected with a diagnosable reason. Bound to the attempt — a stop/superseded attempt ends it.
     */
    /**
     * §6.1: is the tun2socks forwarding chain still alive?
     *
     * Returns (ok, reason). This deliberately does NOT rely on a null shared PFD field (which proved
     * nothing in Astra's CLOSED_PFD_HEV_STOPPED counter-example) and does NOT assume any unverified
     * hev JNI semantics. It uses only facts that are directly observable:
     *
     *  - the attempt's own descriptor must still be OPEN (a closed descriptor means the tunnel is
     *    gone, even if some object still references it)
     *  - the descriptor must still be a usable, non-errored tunnel: we query its link state through
     *    the kernel-visible interface name; if the interface can no longer be resolved, the tunnel
     *    is definitively down.
     *
     * A stopped-but-referenced hev that no longer forwards is caught by the data-path probe; a
     * closed/unresolvable tunnel is caught here. Neither signal alone is claimed to be sufficient.
     */
    private fun forwardingChainAlive(a: Attempt): Pair<Boolean, String> {
        val pfd = a.ownPfd
        if (pfd == null) return false to "tun handle released"
        val fd = a.ownFd
        if (fd < 0) return false to "tun fd invalid"
        // A closed descriptor is a definitive signal, unlike a null field.
        //
        // NOTE: do NOT reflect ParcelFileDescriptor.fd here — it is a hidden framework field and the
        // reflection is rejected on some OEM builds (observed on MIUI: the lookup threw, and a naive
        // catch-to-false silently revoked a healthy tunnel ~10s after Connected). We track the raw
        // descriptor ourselves (a.ownFd, set at establish time) and ask the kernel whether it is
        // still open via /proc/self/fd.
        val alive = java.io.File("/proc/self/fd/$fd").exists()
        if (!alive) return false to "tun handle closed"
        // Astra 10-09 §5 (FD_IDENTITY): an fd NUMBER being open proves nothing about the tunnel —
        // an ordinary file's fd passes the /proc check while the real TUN is long gone (Astra's
        // negative control: ordinaryFdOpen=true with the PFD closed and hev stopped still
        // reported healthy). A TUN handle is only healthy when the kernel actually exposes a
        // tun/ppp interface that is UP; there is deliberately NO fd-only pass-through branch.
        val nif = try {
            java.net.NetworkInterface.getNetworkInterfaces().toList().firstOrNull {
                it.name.startsWith("tun") || it.name.startsWith("ppp")
            }
        } catch (_: Throwable) { null }
        if (nif == null) return false to "no tun interface present"
        val up = try { nif.isUp } catch (_: Throwable) { false }
        if (!up) return false to "tun interface ${nif.name} down"
        return true to "tun ${nif.name} up"
    }

    private fun startHealthMonitor(a: Attempt) {
        val t = Thread {
            while (isActive(a)) {
                try { Thread.sleep(HEALTH_INTERVAL_MS) } catch (_: InterruptedException) { return@Thread }
                if (!isActive(a)) return@Thread
                // §6.1 (Astra CLOSED_PFD_HEV_STOPPED healthOk=true): a null shared field is NOT a
                // liveness signal — it is neither necessary nor sufficient. Readiness now requires
                // proof that the forwarding chain is still intact:
                //   1. this attempt's tun handle is still OPEN (not closed behind our back)
                //   2. the tunnel is still reporting link state (readable via the fd)
                //   3. the data path itself still answers (the authenticated SOCKS+TLS probe)
                val chain = forwardingChainAlive(a)
                if (!chain.first) {
                    log("health lost (${chain.second}) for attempt ${a.id}")
                    terminateFailedAttempt(a, "healthLost", chain.second, "HEALTH_LOST")
                    return@Thread
                }
                // F4 (Astra §4.4): the REAL hev worker signal (device-verified JNI registry,
                // see hevWorkerAlive). false = the worker thread has exited → definitive loss.
                // null = signal unavailable on this build → degrade to the remaining checks;
                // an absent signal must never revoke a healthy tunnel.
                val workerAlive = hevWorkerAlive()
                if (workerAlive == false) {
                    log("health lost (hev worker not running) for attempt ${a.id}")
                    terminateFailedAttempt(a, "healthLost", "hev worker stopped", "HEALTH_LOST")
                    return@Thread
                }
                if (!probeDataPath(a)) {
                    log("health lost (data path) for attempt ${a.id}")
                    terminateFailedAttempt(a, "healthLost", "data path lost", "HEALTH_LOST")
                    return@Thread
                }
                // Stats are recorded for observability only: an idle tunnel legitimately shows
                // no traffic growth, so the counters must never be used as a liveness verdict.
                val stats = hevStatsSnapshot()
                log("health ok attempt=${a.id} (chain=${chain.second}, hevWorker=${workerAlive ?: "unavailable"}, stats=${stats?.joinToString(",") ?: "n/a"})")
            }
        }
        t.isDaemon = true                     // never keeps the process alive on its own
        // §6: install only while this attempt is still current, and cancel only THIS attempt's
        // previous monitor. A stale attempt arriving late must never cancel the new one's monitor.
        val installed = synchronized(attemptLock) {
            if (attemptIsCurrent(a)) {
                a.healthThread?.interrupt()
                a.healthThread = t
                true
            } else false
        }
        if (!installed) {
            log("health monitor not installed: attempt ${a.id} is stale")
            return
        }
        t.start()
    }

    /** Established-TUN carrier: the fd is installed only after ownership confirmation (§5.2). */
    private class TunHandle(val pfd: ParcelFileDescriptor, val summary: String)

    private fun establishTun(attempt: Attempt): TunHandle? {
        val builder = Builder()
        builder.setSession("WildLime Xray")
        builder.addAddress("10.8.0.2", 24)
        // IPv6 必须一起纳入隧道。只宣告 IPv4 路由时，双栈网络上的 IPv6 流量会绕过 tun
        // 走运营商链路 —— 用户的真实 IPv6 地址直接暴露（典型 IPv6 泄漏）。
        // 隧道内没有 IPv6 出口时这些包会被丢弃（fail-closed），这比泄漏正确。
        builder.addAddress("fdfe:dcba:9876::1", 126)
        builder.addDnsServer("1.1.1.1")
        builder.addDnsServer("8.8.8.8")
        builder.addRoute("0.0.0.0", 0)
        // IPv6 进隧道（R36-IPv6 完整修复 2026-11-01）：
        // 服务端 xray 容器已接入 IPv6 网络 nublime-v6（2001:db8:0:1::/64/80），
        // freedom 出站 domainStrategy 由 UseIPv4 改为 UseIP，v6 字面量与仅 AAAA 域名都实测 200。
        // 因此这里恢复 ::/0，IPv6 不再泄漏到运营商链路。
        // 前置条件（缺一不可）：容器有 v6 地址 + 宿主 net.ipv6.conf.all.forwarding=1
        // + ufw6-before-forward 放行 nublime-v6（已写入 /etc/ufw/before6.rules 持久化）。
        builder.addRoute("::", 0)
        // 历史坑（4.1.33→4.1.38）：服务端容器无 v6 出口时把 ::/0 拉进隧道，会让 Chrome 的 v6 优先
        // 连接全部黑洞，表现为「已连接但所有网页 ERR_CONNECTION_CLOSED」。该坑已在服务端修完
        // （见上），所以这行现在是安全的；若哪天换了机房/重建了 docker 网络，务必先验
        // `docker exec nublime-xray ip -6 addr` 有地址、`ip -6 route` 有默认路由，再发版。
        // §6: original runtime parameters restored (blocking FD + MTU) — hev depends on them.
        // R36-MTU：1500 在真机（LTE/PPPoE 上游 MTU ~1400-1450）上会让隧道内的
        // TCP 大包被外层 DF 丢弃 → TLS 握手卡死，表现为「已连接但网页打不开 / ERR_CONNECTION_CLOSED」。
        // 1420 是 WireGuard/OpenVPN 长期验证过的保守值，留足 REALITY over TCP 的封装余量。
        builder.setMtu(1420)
        builder.setBlocking(true)
        // R36-A05：分应用代理真正接线。Android 的 Builder 不允许同一次建立里混用
        // allow-list 与 disallow-list，所以按模式二选一：
        //   include —— 只代理用户勾选的 App；本应用不在名单里 = 自身流量绕过隧道（防环）。
        //   exclude —— 勾选的 App 绕过隧道；本应用必须显式排除（防环）。
        // 名单为空时退回全量代理并记日志：空 allow-list 会把设备所有流量丢进黑洞。
        val mode = perAppMode
        val pkgs = perAppPackages.filter { it.isNotBlank() && it != packageName }
        if (mode == "include" && pkgs.isNotEmpty()) {
            var applied = 0
            for (pkg in pkgs) {
                try {
                    builder.addAllowedApplication(pkg)
                    applied++
                } catch (e: android.content.pm.PackageManager.NameNotFoundException) {
                    logPerApp("per-app: skipped unknown package $pkg")
                } catch (e: Exception) {
                    logPerApp("per-app: addAllowedApplication($pkg) failed: ${e.javaClass.simpleName}")
                }
            }
            logPerApp("per-app include: applied=$applied of ${pkgs.size}")
            if (applied == 0) {
                // 全部包名都失效（卸载/改名）→ 不建立空 allow-list 隧道（空名单会把所有流量丢进黑洞），
                // 退回全量代理并留痕，避免用户直接连不上。
                logPerApp("per-app include: no valid package left; falling back to full tunnel")
            }
        } else {
            if (mode == "include") {
                logPerApp("per-app include requested with empty list; falling back to full tunnel")
            }
            // §6: excluding this app is required to avoid a routing loop; a failure is NOT silently OK.
            try {
                builder.addDisallowedApplication(packageName)
            } catch (e: Exception) {
                log("addDisallowedApplication failed: ${e.javaClass.simpleName}")
                return null                       // treated as a setup failure (reported, not swallowed)
            }
            if (mode == "exclude" && pkgs.isNotEmpty()) {
                var applied = 0
                for (pkg in pkgs) {
                    try {
                        builder.addDisallowedApplication(pkg)
                        applied++
                    } catch (e: android.content.pm.PackageManager.NameNotFoundException) {
                        logPerApp("per-app: skipped unknown package $pkg")
                    } catch (e: Exception) {
                        log("per-app: addDisallowedApplication($pkg) failed: ${e.javaClass.simpleName}")
                    }
                }
                logPerApp("per-app exclude: bypassing $applied of ${pkgs.size}")
            }
        }
        val pfd = try { builder.establish() } catch (e: Exception) { log("establish threw: ${e.javaClass.simpleName}"); null }
            ?: return null
        // install only if we are still the current attempt, otherwise close our own handle
        val installed = synchronized(attemptLock) {
            if (attempt.valid && !attempt.terminated && currentAttempt === attempt) {
                // §6: a repeat start replaces the tun; the previous handle must be closed here or
                // its fd leaks (Android keeps the interface until GC). Close BEFORE overwriting.
                // Per Android's Builder contract, after a new interface is established the old
                // descriptor is STILL valid and must be closed explicitly — responsibility is not
                // transferred to GC.
                try { vpnPfd?.close() } catch (e: Exception) { log("replace pfd close: ${e.javaClass.simpleName}") }
                vpnPfd = pfd
                tunFd = pfd.fd
                attempt.ownPfd = pfd
                attempt.ownFd = pfd.fd
                true
            } else false
        }
        if (!installed) {
            try { pfd.close() } catch (_: Exception) {}
            return null
        }
        return TunHandle(pfd, "OK: fd=${pfd.fd}")
    }

    /** §4.2: credentials are generated into the ATTEMPT, never into service-level fields. */
    private fun generateProxyCredentials(attempt: Attempt) {
        val rnd = SecureRandom()
        attempt.creds.port = 20000 + rnd.nextInt(10000) // 20000-29999
        attempt.creds.user = java.util.UUID.randomUUID().toString().replace("-", "").substring(0, 12)
        val chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        attempt.creds.pass = StringBuilder(32).apply {
            repeat(32) { append(chars[rnd.nextInt(chars.length)]) }
        }.toString()
        log("proxy port=${attempt.creds.port} attempt=${attempt.id}")
    }

    private fun buildHevConfig(attempt: Attempt): String {
        return """
tunnel:
  name: tun0
  mtu: 1420
  multi-queue: false
  ipv4: 198.18.0.1
  ipv6: 'fc00::1'
  icmp: 'off'

socks5:
  address: 127.0.0.1
  port: ${attempt.creds.port}
  udp: 'udp'
  username: '${attempt.creds.user}'
  password: '${attempt.creds.pass}'

misc:
  log-file: ${File(filesDir, "hev.log").absolutePath}
  log-level: 'info'
""".trimIndent()
    }

    override fun onDestroy() {
        // §6/F1 (Astra R11): Service destruction uses the SAME release path as an explicit stop,
        // and the victim is captured BEFORE invalidation (the old code invalidated first and then
        // read currentAttempt — always null — so destroy always took the global-stop branch and
        // could stop a newer generation's core).
        // Astra 10-09 §3.2: destroy is also generation-scoped — its native branch runs only
        // while this instance is still the active one AND no newer stop/attempt superseded it.
        val destroyEpoch = stopEpochCounter.incrementAndGet()
        val victim = invalidateCurrentAttempt()
        Thread {
            try { victim?.let { releaseAttemptResources(it) } ?: run {
                // F1: no attempt context — stop only what the process still owns, and only while
                // THIS instance is still the active one AND this destroy is still the current
                // generation. A recreated service's cores are never stopped by the instance
                // they replaced.
                // R20 §6 (NO_ATTEMPT_LOCK): the same single-flight coordinator — invoke
                // OUTSIDE processNativeLock, never under it.
                // R21 §4: context captured at call time, re-verified INSIDE the lock at each
                // resource's admission — the async destroy worker that waited behind a lock
                // loses authority once B took over (stale-no-attempt-destroy regression fix).
                stopAllNativeNoAttempt("destroy", StopContext(this@XrayVpnService, destroyEpoch))
                try { vpnPfd?.close() } catch (_: Exception) {}
            } } catch (_: Exception) {}
            // F1: the process-wide running flag follows core OWNERSHIP after cleanup — a stale
            // instance's destroy must not clear it while a newer generation owns the core.
            nativeLock.lock()
            try { if (nativeCoreOwner == null) isRunning = false } finally { nativeLock.unlock() }
        }.start()
        super.onDestroy()
    }


    private fun runXray(jsonConfig: String, attempt: Attempt): XrayInvokeResult {
        return try {
            // Inject authenticated SOCKS5 inbound using THIS attempt's credentials.
            // §5.2 (P5): inject through the JSON structure instead of a string replace, so
            // whitespace/formatting variants of "inbounds":[] can no longer defeat the injection.
            val socksIn = JSONObject()
                .put("tag", "socks-in")
                .put("protocol", "socks")
                .put("listen", "127.0.0.1")
                .put("port", attempt.creds.port)
                .put("settings", JSONObject()
                    .put("auth", "password")
                    .put("accounts", JSONArray().put(JSONObject()
                        .put("user", attempt.creds.user)
                        .put("pass", attempt.creds.pass)))
                    .put("udp", true))
            val root = JSONObject(jsonConfig)
            val inbounds = root.optJSONArray("inbounds") ?: JSONArray()
            inbounds.put(socksIn)
            root.put("inbounds", inbounds)
            val finalConfig = root.toString()
            val request = JSONObject()
                .put("apiVersion", 1)
                .put("method", "runXrayFromJson")
                .put("payload", JSONObject().put("configJSON", finalConfig))
                .toString()
            // §6: (a) an attempt-scoped config file, so a stale attempt cannot overwrite the file the
            // current generation is using; (b) ownership re-checked immediately before the native
            // call so a superseded attempt cannot reach the native boundary after B is ready
            // (Astra: STALE_NATIVE_AFTER_B oldACallsAfterB=1 nativeOwner=A).
            //
            // The file write is deliberately OUTSIDE the lock (blocking I/O must never hold the
            // ownership lock); the native call itself runs INSIDE it, so the "stale attempt may not
            // invoke native" guarantee holds without any I/O serialization.
            val configFile = File(filesDir, attempt.xrayConfigPath)
            configFile.writeText(finalConfig)
            log("xray config len=${finalConfig.length} attempt=${attempt.id}")
            // F2 (Astra R11): wait for the previous generation's stop confirmation WITHOUT
            // holding nativeLock — the cleanup that clears coreStopPending needs that same lock.
            // Holding it here self-deadlocks the wait (always the full budget) and then starts
            // the core anyway with the stop still unconfirmed (Astra F2: the old stopXray lands
            // after B started and kills B's freshly started core).
            // Astra R18.1 §3.1/§9.1: the previous "a parked stop does not block a newer
            // generation" escape (stopInProgressOwner) is WITHDRAWN — it admitted B's start
            // while A's stop was still landing and the fresh core was killed ("actual=none
            // while owner=B"). The serialized protocol: wait for the in-flight stop to
            // COMPLETE (confirmed or failed), bounded by CORE_HANDOFF_TIMEOUT_MS; then, under
            // the lock, an unconfirmed previous stop (pending flag still set) refuses this
            // start with CONFLICT. Registration was never blocked — only native start is.
            val waitUntil = System.currentTimeMillis() + CORE_HANDOFF_TIMEOUT_MS
            while ((coreStopPending || coreStopState.get() is StopPhase.Stopping || hevStopState.get() is StopPhase.Stopping) &&
                System.currentTimeMillis() < waitUntil) {
                try { Thread.sleep(10) } catch (_: InterruptedException) { break }
            }
            var parsedResult: XrayInvokeResult
            // F2: BOUNDED acquisition — a hung previous stop must fail this start after the
            // handoff budget with an explicit reason, not block forever.
            val lockTaken = nativeLock.tryLock(CORE_HANDOFF_TIMEOUT_MS, java.util.concurrent.TimeUnit.MILLISECONDS)
            try {
                if (!lockTaken) {
                    log("native start aborted: native lock not available within budget (attempt ${attempt.id})")
                    return XrayInvokeResult.Failed(FailureKind.CONFLICT, "previous core stop not confirmed")
                }
                // Fail closed — an executing stop on EITHER resource, an UNCONFIRMED core
                // stop, or the pending flag (stops that returned without confirmation) all
                // refuse the takeover. This is a takeover CONFLICT, not a hev failure —
                // Astra R20 §7.1 restored the CONFLICT classification for the core path.
                // R22-F6: gate references coreStopTakeoverBlocked() — one source of truth
                // (pending || Unconfirmed || needsRetry); Stopping phases checked alongside
                // for the in-flight window that the terminal-state predicate does not cover.
                if (coreStopTakeoverBlocked() || coreStopState.get() is StopPhase.Stopping || hevStopState.get() is StopPhase.Stopping) {
                    log("native start aborted: previous stop still in flight/unconfirmed (attempt ${attempt.id})")
                    return XrayInvokeResult.Failed(FailureKind.CONFLICT, "previous core stop not confirmed")
                }
                // F1: ownership is re-verified INSIDE nativeLock, i.e. with no window between
                // the check and the native call.
                synchronized(attemptLock) {
                    if (!attemptIsCurrentLocked(attempt)) {
                        log("native start skipped: attempt ${attempt.id} is stale")
                        return XrayInvokeResult.Failed(FailureKind.CONFLICT, "superseded before core start")
                    }
                }
                val response = libXray.LibXray.invoke(request)
                // R09/R01: never log raw response content (may echo config or identity); length only.
                log("invoke response len=${response.length}")
                parsedResult = XrayInvokeParser.parse(response)
                // F1: core ownership transfers to THIS attempt at acceptance, atomically with
                // the start — every cleanup path can now see who owns the running core.
                if (parsedResult is XrayInvokeResult.Accepted) nativeCoreOwner = attempt.id
            } finally {
                if (lockTaken) nativeLock.unlock()
            }
            return parsedResult
        } catch (e: Exception) {
            log("invoke threw: ${e.javaClass.simpleName}")
            XrayInvokeResult.Failed(FailureKind.MALFORMED, "invoke exception: ${e.javaClass.simpleName}")
        }
    }

    // R26.1 (Astra R26-F3): geoip.dat/geosite.dat removed from assets and this copy path.
    // No active config path emits geosite:/geoip: matchers — the builtin config routes only
    // socks-in→proxy, and server-delivered profiles use explicit CIDR (R07 convergence).
    // The old data files carried unattributable provenance (pre-rebuild era) and 25 MB of
    // dead weight in the APK. If a future config needs geo matchers: re-add VETTED data
    // files from a licensed source, add a NOTICE entry per spec §8.3 A-5, and restore the
    // asset copy here.

    private fun log(msg: String) { try { FileWriter(File(filesDir, "xray.log"), true).use { it.write("${System.currentTimeMillis()} $msg\n") } } catch (_: Exception) {} }

    // 分应用决策单独镜像一份到 logcat：xray.log 在 release 包里取不出来（非 debuggable），
    // 而"到底有没有按名单建隧道"是必须能在设备上留证的。只写包名与计数，不含配置与凭据。
    private fun logPerApp(msg: String) {
        try { android.util.Log.i("WildLimePerApp", msg) } catch (_: Exception) {}
        log(msg)
    }
    private fun updateNotification(text: String) { getSystemService(NotificationManager::class.java).notify(NOTIFY_ID, buildNotification(text)) }

    // TODO(P1-next): notification channel importance（2026-09-10 dumpsys notification 实测）：
    //  渠道当前 importance=NONE（横幅被系统隐藏）。不影响前台服务存活（FGS 状态栏图标豁免 MIUI
    //  后台关闭计时，已实测）。但以后若做"断线推送提醒用户"功能，必须先提高该 channel 的
    //  importance，否则推送不会被用户看到。
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            NotificationChannel(CHANNEL_ID, "Xray VPN", NotificationManager.IMPORTANCE_LOW).apply { description = "VPN" }.let { getSystemService(NotificationManager::class.java).createNotificationChannel(it) }
    }

    private fun buildNotification(text: String): Notification {
        val pi = PendingIntent.getActivity(this, 0, packageManager.getLaunchIntentForPackage(packageName), PendingIntent.FLAG_IMMUTABLE)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            Notification.Builder(this, CHANNEL_ID).setContentTitle("Xray PoC").setContentText(text).setSmallIcon(android.R.drawable.ic_menu_manage).setContentIntent(pi).build()
        else { @Suppress("DEPRECATION") Notification.Builder(this).setContentTitle("Xray PoC").setContentText(text).setSmallIcon(android.R.drawable.ic_menu_manage).setContentIntent(pi).build() }
    }
}
