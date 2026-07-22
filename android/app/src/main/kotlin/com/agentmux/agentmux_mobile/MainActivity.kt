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

    // A single, persistent, reference-counted lock. Two overlapping
    // MdnsScanner.scan() calls (e.g. a manual refresh fired while a prior
    // scan is still within its timeout window) must each get their own
    // acquire()/release() pair against the SAME lock object — that's what
    // setReferenceCounted(true) is for. Recreating the lock per call (or
    // short-circuiting acquire() when already held, as an earlier version
    // of this file did) breaks that: the first scan's release() would drop
    // the lock out from under a still-running second scan.
    private val multicastLock: WifiManager.MulticastLock by lazy {
        val wifiManager =
            applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        wifiManager.createMulticastLock("agentmux-mdns-discovery").apply {
            setReferenceCounted(true)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "acquire" -> {
                        multicastLock.acquire()
                        result.success(null)
                    }
                    "release" -> {
                        // Guards against an unbalanced release() (no prior
                        // acquire()) throwing "WifiLock under-locked" —
                        // matched acquire/release pairs from the Dart side
                        // are still what keeps the ref count correct.
                        if (multicastLock.isHeld) multicastLock.release()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        while (multicastLock.isHeld) {
            multicastLock.release()
        }
        super.onDestroy()
    }
}
