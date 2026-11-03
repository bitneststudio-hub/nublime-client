package hev.htproxy

/**
 * JNI bindings for hev-socks5-tunnel (tun2socks).
 * Class name and package MUST match the JNI_OnLoad FindClass in hev-jni.c:
 * PKGNAME=hev/htproxy, CLSNAME=TProxyService
 */
object TProxyService {
    init {
        System.loadLibrary("hev-socks5-tunnel")
    }

    external fun TProxyStartService(configPath: String, fd: Int): Boolean
    external fun TProxyStopService(): Boolean
    external fun TProxyIsRunning(): Boolean
    external fun TProxyGetStats(): LongArray
}
