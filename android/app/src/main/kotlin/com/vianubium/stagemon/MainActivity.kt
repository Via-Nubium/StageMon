package com.vianubium.stagemon

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Build
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

private const val TAG = "StageMonNet"

// Binds the whole process to the current wifi network so OSC/UDP traffic to
// the console keeps working even when Android's default-network scoring
// moves the system default to mobile data (e.g. wifi has no internet route).
class MainActivity : FlutterActivity() {
    private val channelName = "com.vianubium.stagemon/network"
    private var channel: MethodChannel? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        ch.setMethodCallHandler { call, result ->
            Log.d(TAG, "received call from Dart: ${call.method}")
            when (call.method) {
                "bindWifi" -> {
                    bindProcessToWifi()
                    result.success(null)
                }
                "unbind" -> {
                    unbindProcess()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        channel = ch
    }

    private fun connectivityManager(): ConnectivityManager =
        getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

    private fun bindProcessToWifi() {
        // bindProcessToNetwork() only exists from API 23; below that the
        // per-app routing table doesn't apply the same way, so skip.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return

        // Dart calls this on every app resume, not just on first connect.
        // Skip if already listening: the same callback keeps reporting
        // onAvailable/onLost for as long as it's registered, even while the
        // app is backgrounded. Re-registering here would open a fresh
        // request with no prior network to "lose" — if wifi happened to
        // drop while backgrounded, the new registration would never see
        // that transition and onLost would silently never fire.
        if (networkCallback != null) {
            Log.d(TAG, "bindProcessToWifi: already listening, skip")
            return
        }
        Log.d(TAG, "bindProcessToWifi: requesting network")

        val cm = connectivityManager()
        // No addCapability(NET_CAPABILITY_VALIDATED) here on purpose: that's
        // exactly the capability wifi loses when it has no internet route,
        // and requiring it would make this request fail in the case we're
        // working around.
        val request = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            .build()

        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                Log.d(TAG, "onAvailable: $network")
                cm.bindProcessToNetwork(network)
                runOnUiThread { channel?.invokeMethod("networkAvailable", null) }
            }

            override fun onLost(network: Network) {
                Log.d(TAG, "onLost: $network")
                // Deliberately not calling bindProcessToNetwork(null) here:
                // the process stays bound to this (now dead) Network, so any
                // socket call fails immediately instead of silently falling
                // back to the system default (which could be mobile data).
                // Rebinding happens automatically on the next onAvailable().
                runOnUiThread { channel?.invokeMethod("networkLost", null) }
            }

            override fun onUnavailable() {
                Log.d(TAG, "onUnavailable")
            }
        }
        networkCallback = callback
        cm.requestNetwork(request, callback)
    }

    private fun unbindProcess() {
        Log.d(TAG, "unbindProcess (had callback: ${networkCallback != null})")
        networkCallback?.let {
            try {
                connectivityManager().unregisterNetworkCallback(it)
            } catch (_: IllegalArgumentException) {
                // Callback was already unregistered by the system (network gone).
            }
        }
        networkCallback = null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            connectivityManager().bindProcessToNetwork(null)
        }
    }

    override fun onDestroy() {
        unbindProcess()
        super.onDestroy()
    }
}
