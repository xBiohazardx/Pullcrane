package com.teq_tech.pullcrane

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity() {

    companion object {
        const val FAST_BLE_CHANNEL = "com.teq_tech.pullcrane/fast_ble_scan"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            FAST_BLE_CHANNEL
        ).setStreamHandler(FastBleScanHandler(context))
    }
}
