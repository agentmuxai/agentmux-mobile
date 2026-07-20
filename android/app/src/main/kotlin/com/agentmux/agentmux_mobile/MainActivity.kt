package com.agentmux.agentmux_mobile

import android.content.Context
import android.net.wifi.WifiManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Android silently drops incoming multicast packets (including mDNS) unless
// the app holds a WifiManager.MulticastLock — no exception, no log, the
// PTR/SRV/TXT lookups in mdns_scanner.dart just never resolve. Only affects
// API <=33 in practice, but acquiring the lock is a harmless no-op elsewhere.
// See agentmux-mobile#2.
class MainActivity : FlutterActivity() {
    private val channelName = "com.agentmux.agentmux_mobile/multicast_lock"
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "acquire" -> {
                        acquireLock()
                        result.success(null)
                    }
                    "release" -> {
                        releaseLock()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun acquireLock() {
        if (multicastLock?.isHeld == true) return
        val wifiManager =
            applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        val lock = wifiManager.createMulticastLock("agentmux-mdns-discovery")
        lock.setReferenceCounted(true)
        lock.acquire()
        multicastLock = lock
    }

    private fun releaseLock() {
        multicastLock?.let { if (it.isHeld) it.release() }
        multicastLock = null
    }

    override fun onDestroy() {
        releaseLock()
        super.onDestroy()
    }
}
