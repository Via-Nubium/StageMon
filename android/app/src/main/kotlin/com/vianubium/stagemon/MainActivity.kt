package com.vianubium.stagemon

import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Build
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

private const val TAG = "StageMonNet"
private const val TAG_IMPORT = "StageMonImport"

// Binds the whole process to the current wifi network so OSC/UDP traffic to
// the console keeps working even when Android's default-network scoring
// moves the system default to mobile data (e.g. wifi has no internet route).
class MainActivity : FlutterActivity() {
    private val channelName = "com.vianubium.stagemon/network"
    private var channel: MethodChannel? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null

    // Content of a .stagemonlayout file received via ACTION_VIEW (opened from
    // WhatsApp, a file manager, etc.), waiting for the Dart side to ask for it.
    // Pull-based rather than pushed eagerly: at the moment Android delivers the
    // intent, the Flutter engine/Dart isolate may not be far enough along to
    // have a listener registered yet (cold start), so a plain invokeMethod()
    // could be silently dropped. Dart asks for this once it's actually ready
    // to act on it (e.g. once connected to a console).
    private var pendingLayoutImport: String? = null
    private val layoutImportChannelName = "com.vianubium.stagemon/layout_import"
    private var layoutImportChannel: MethodChannel? = null

    private val displayChannelName = "com.vianubium.stagemon/display"
    private var displayChannel: MethodChannel? = null

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

        val importCh = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            layoutImportChannelName,
        )
        importCh.setMethodCallHandler { call, result ->
            when (call.method) {
                "getPendingLayoutImport" -> {
                    result.success(pendingLayoutImport)
                    pendingLayoutImport = null
                }
                else -> result.notImplemented()
            }
        }
        layoutImportChannel = importCh

        val displayCh = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            displayChannelName,
        )
        displayCh.setMethodCallHandler { call, result ->
            when (call.method) {
                "getScreenOffTimeout" -> result.success(getScreenOffTimeoutMs())
                else -> result.notImplemented()
            }
        }
        displayChannel = displayCh

        // Covers a cold start: the activity's own intent (the one that
        // launched it) is only available now that this method has run.
        handleIncomingIntent(intent)
    }

    // Android reuses this activity (launchMode="singleTop") instead of
    // creating a new one when StageMon is already running, so a file opened
    // while the app is alive arrives here instead of in onCreate/getIntent().
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIncomingIntent(intent)
    }

    private fun handleIncomingIntent(intent: Intent?) {
        if (intent?.action != Intent.ACTION_VIEW) return
        val uri = intent.data ?: return
        Log.d(TAG_IMPORT, "handleIncomingIntent: uri=$uri type=${intent.type}")
        try {
            val content = contentResolver.openInputStream(uri)?.use { stream ->
                stream.bufferedReader().readText()
            }
            if (content == null) {
                Log.w(TAG_IMPORT, "Could not open stream for $uri")
                return
            }
            pendingLayoutImport = content
            Log.d(TAG_IMPORT, "Received layout file, ${content.length} chars")
            runOnUiThread { layoutImportChannel?.invokeMethod("layoutImportAvailable", null) }
        } catch (e: Exception) {
            Log.e(TAG_IMPORT, "Failed to read shared layout file", e)
        }
    }

    // The user's configured "Settings > Display > Screen timeout", in ms.
    // Readable without any permission. Lets StageMon's own keep-awake dim
    // approximate when the system would have dimmed/locked instead of using
    // an arbitrary fixed delay.
    private fun getScreenOffTimeoutMs(): Int {
        return try {
            Settings.System.getInt(contentResolver, Settings.System.SCREEN_OFF_TIMEOUT)
        } catch (e: Settings.SettingNotFoundException) {
            30000
        }
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
