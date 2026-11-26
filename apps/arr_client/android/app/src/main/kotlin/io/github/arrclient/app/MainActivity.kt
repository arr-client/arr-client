package io.github.arrclient.app

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // SystemTextSharer in lib/app/platform/text_sharer.dart.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "io.github.arrclient.app/share")
            .setMethodCallHandler { call, result ->
                val text = call.arguments as? String
                if (call.method == "shareText" && text != null) {
                    val send = Intent(Intent.ACTION_SEND)
                        .setType("text/plain")
                        .putExtra(Intent.EXTRA_TEXT, text)
                    // Always the chooser, so that the user picks the receiver each time.
                    startActivity(Intent.createChooser(send, null))
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }
}
