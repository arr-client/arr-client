package io.github.arrclient.localnetwork

import android.Manifest
import android.annotation.TargetApi
import android.content.Context
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.RouteInfo
import android.os.Build
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

/** Android 17, the first release that enforces ACCESS_LOCAL_NETWORK. */
private const val ENFORCED_FROM = 37

/** Tells this plugin's permission result apart from those of others. */
private const val REQUEST_CODE = 0x4C4E

/**
 * Reports what the local network permission flow needs to know, and asks for the permission.
 *
 * It is registered with every Flutter engine, so a background isolate can read the state. Only an
 * engine with an activity can prompt.
 */
class LocalNetworkPlugin :
    FlutterPlugin,
    ActivityAware,
    MethodChannel.MethodCallHandler,
    PluginRegistry.RequestPermissionsResultListener {
    private lateinit var context: Context
    private lateinit var channel: MethodChannel
    private var activityBinding: ActivityPluginBinding? = null

    /** Callers waiting for the one prompt on screen. */
    private val waiting = mutableListOf<MethodChannel.Result>()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "io.github.arrclient/local_network")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        waiting.clear()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "snapshot" -> result.success(snapshot())
            "requestPermission" -> requestPermission(result)
            else -> result.notImplemented()
        }
    }

    private fun isGranted(): Boolean =
        Build.VERSION.SDK_INT < ENFORCED_FROM ||
            context.checkSelfPermission(Manifest.permission.ACCESS_LOCAL_NETWORK) ==
            PackageManager.PERMISSION_GRANTED

    private fun snapshot(): Map<String, Any?> {
        if (Build.VERSION.SDK_INT < ENFORCED_FROM) return mapOf("enforced" to false)

        val manager = context.getSystemService(ConnectivityManager::class.java)
        var onLan = false
        val lanRoutes = mutableListOf<Map<String, Any?>>()
        // Deprecated in favour of callbacks, which cannot answer a question asked once.
        @Suppress("DEPRECATION")
        for (network in manager.allNetworks) {
            val capabilities = manager.getNetworkCapabilities(network) ?: continue
            // A VPN also reports the transports it runs over.
            if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) continue
            if (!capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) &&
                !capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)
            ) {
                continue
            }
            onLan = true
            manager.getLinkProperties(network)?.routes
                ?.filter { it.type == RouteInfo.RTN_UNICAST }
                ?.forEach { lanRoutes.add(describe(it)) }
        }

        // The active network is the one this app's traffic uses: a VPN that leaves the app out is
        // not reported here.
        val active = manager.activeNetwork
        val overVpn = active != null &&
            manager.getNetworkCapabilities(active)
                ?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true
        val vpnRoutes = if (overVpn) {
            manager.getLinkProperties(active)?.routes?.map { describe(it) }.orEmpty()
        } else {
            emptyList()
        }

        return mapOf(
            "enforced" to true,
            "granted" to isGranted(),
            "lanRoutes" to if (onLan) lanRoutes else null,
            "vpnRoutes" to vpnRoutes,
        )
    }

    /** Only called from API 37, so the route type (API 33) is available. */
    @TargetApi(Build.VERSION_CODES.TIRAMISU)
    private fun describe(route: RouteInfo): Map<String, Any?> =
        mapOf(
            "address" to route.destination.address.address,
            "prefixLength" to route.destination.prefixLength,
            // A route a VPN leaves out of its tunnel.
            "excluded" to (route.type == RouteInfo.RTN_THROW),
        )

    private fun requestPermission(result: MethodChannel.Result) {
        val activity = activityBinding?.activity
        if (Build.VERSION.SDK_INT < ENFORCED_FROM || isGranted() || activity == null) {
            result.success(isGranted())
            return
        }
        waiting.add(result)
        if (waiting.size == 1) {
            activity.requestPermissions(
                arrayOf(Manifest.permission.ACCESS_LOCAL_NETWORK),
                REQUEST_CODE,
            )
        }
    }

    /** Answers every waiting caller with the state now, however the prompt ended. */
    private fun answerWaiting() {
        val granted = isGranted()
        waiting.forEach { it.success(granted) }
        waiting.clear()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != REQUEST_CODE) return false
        answerWaiting()
        return true
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivity() {
        removeActivity()
        answerWaiting()
    }

    // The recreated activity receives the result of a prompt that is still open.
    override fun onDetachedFromActivityForConfigChanges() = removeActivity()

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)

    private fun removeActivity() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
    }
}
