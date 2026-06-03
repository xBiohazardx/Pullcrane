package com.teq_tech.pullcrane

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothManager
import android.bluetooth.le.BluetoothLeScanner
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.app.ActivityCompat
import io.flutter.plugin.common.EventChannel
import java.nio.ByteBuffer
import java.nio.ByteOrder

private const val TAG = "FastBleScan"
private const val WEIGHT_OFFSET = 12
private const val WEIGHT_LENGTH = 2
private const val TARGET_DEVICE_NAME = "IF_B7"
private const val RATE_LOG_INTERVAL_MS = 2000L

class FastBleScanHandler(
    private val context: Context
) : EventChannel.StreamHandler {

    private var scanner: BluetoothLeScanner? = null
    private var eventSink: EventChannel.EventSink? = null
    private var scanResultCount = 0
    private var parseSuccessCount = 0
    private var eventSentCount = 0
    private var lastRateLog = 0L
    private val handler = Handler(Looper.getMainLooper())

    private val scanCallback = object : ScanCallback() {
        @SuppressLint("MissingPermission")
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            scanResultCount++
            val device = result.device
            val name = device.name ?: "null"
            val address = device.address

            if (name != TARGET_DEVICE_NAME) {
                return
            }

            val record = result.scanRecord
            if (record == null) {
                Log.w(TAG, "Scan result for $name ($address) has null scanRecord")
                return
            }

            val parsedForce = parseWeightFromManufacturerData(record)
            if (parsedForce != null) {
                parseSuccessCount++
                eventSink?.success(mapOf("force" to parsedForce))
                eventSentCount++
            }

            logRate()
        }

        override fun onScanFailed(errorCode: Int) {
            Log.e(TAG, "onScanFailed: errorCode=$errorCode")
            eventSink?.error("SCAN_FAILED", "BLE scan failed with error $errorCode", null)
        }
    }

    private fun logRate() {
        val now = System.currentTimeMillis()
        if (now - lastRateLog >= RATE_LOG_INTERVAL_MS) {
            val elapsed = (now - lastRateLog) / 1000.0
            Log.d(TAG, "Rate: $scanResultCount scan results, $parseSuccessCount parsed, $eventSentCount sent in last $elapsed s")
            scanResultCount = 0
            parseSuccessCount = 0
            eventSentCount = 0
            lastRateLog = now
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        Log.d(TAG, "onListen called, arguments=$arguments")
        eventSink = events

        if (!hasPermissions()) {
            Log.e(TAG, "onListen: missing BLE permissions")
            events?.error("NO_PERMISSION", "Missing BLE permissions", null)
            return
        }

        val btManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        val adapter = btManager?.adapter
        if (adapter == null || !adapter.isEnabled) {
            Log.e(TAG, "onListen: Bluetooth not enabled (adapter=$adapter, enabled=${adapter?.isEnabled})")
            events?.error("BT_OFF", "Bluetooth is not enabled", null)
            return
        }

        scanner = adapter.bluetoothLeScanner
        if (scanner == null) {
            Log.e(TAG, "onListen: bluetoothLeScanner is null")
            events?.error("NO_SCANNER", "BLE scanner not available on this device", null)
            return
        }

        Log.d(TAG, "onListen: starting scan for $TARGET_DEVICE_NAME")
        startLowLatencyScan()
    }

    @SuppressLint("MissingPermission")
    private fun startLowLatencyScan() {
        val settingsBuilder = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .setCallbackType(ScanSettings.CALLBACK_TYPE_ALL_MATCHES)
            .setReportDelay(0)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            settingsBuilder.setMatchMode(ScanSettings.MATCH_MODE_AGGRESSIVE)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            settingsBuilder.setPhy(ScanSettings.PHY_LE_ALL_SUPPORTED)
            settingsBuilder.setLegacy(false)
        }

        val settings = settingsBuilder.build()

        val emptyFilters = emptyList<ScanFilter>()

        try {
            lastRateLog = System.currentTimeMillis()
            scanResultCount = 0
            parseSuccessCount = 0
            eventSentCount = 0
            scanner?.startScan(emptyFilters, settings, scanCallback)
            Log.d(TAG, "Scan started: mode=LOW_LATENCY, reportDelay=0, matchMode=AGGRESSIVE, no hw filter")
        } catch (e: SecurityException) {
            Log.e(TAG, "Security exception starting scan: ${e.message}")
            eventSink?.error("SECURITY", "Missing BLE permissions", e.message)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start scan: ${e.message}")
            eventSink?.error("SCAN_ERROR", e.message, null)
        }
    }

    override fun onCancel(arguments: Any?) {
        Log.d(TAG, "onCancel called")
        stopScan()
        eventSink = null
        handler.removeCallbacksAndMessages(null)
    }

    @SuppressLint("MissingPermission")
    private fun stopScan() {
        try {
            scanner?.stopScan(scanCallback)
            Log.d(TAG, "Scan stopped")
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping scan: ${e.message}")
        }
        scanner = null
    }

    private fun hasPermissions(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            return ActivityCompat.checkSelfPermission(
                context, Manifest.permission.BLUETOOTH_SCAN
            ) == PackageManager.PERMISSION_GRANTED &&
            ActivityCompat.checkSelfPermission(
                context, Manifest.permission.BLUETOOTH_CONNECT
            ) == PackageManager.PERMISSION_GRANTED
        }
        return ActivityCompat.checkSelfPermission(
            context, Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun parseWeightFromManufacturerData(record: android.bluetooth.le.ScanRecord): Int? {
        val records = record.bytes ?: return null

        var index = 0
        while (index < records.size - 1) {
            val length = records[index].toInt() and 0xFF
            if (length == 0 || index + length >= records.size) break

            val type = records[index + 1].toInt() and 0xFF

            if (type == 0xFF && length >= WEIGHT_OFFSET + WEIGHT_LENGTH + 2) {
                val dataStart = index + 2
                val dataEnd = index + length + 1
                val cmdBytes = records.copyOfRange(dataStart, dataEnd)
                val result = parseWeight(cmdBytes, WEIGHT_OFFSET)
                if (result != null) return result

                val payloadBytes = records.copyOfRange(index + 4, dataEnd)
                val result2 = parseWeight(payloadBytes, WEIGHT_OFFSET - 2)
                if (result2 != null) return result2
            }

            index += length + 1
        }
        return null
    }

    private fun parseWeight(bytes: ByteArray, offset: Int): Int? {
        if (offset < 0 || bytes.size < offset + WEIGHT_LENGTH) {
            return null
        }

        val rawWeight = ByteBuffer.wrap(bytes, offset, WEIGHT_LENGTH)
            .order(ByteOrder.BIG_ENDIAN)
            .getShort()
            .toInt() and 0xFFFF

        val kilograms = rawWeight / 100.0
        return kilograms.toInt().coerceIn(0, 100)
    }
}
