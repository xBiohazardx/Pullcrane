import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pullcrane/domain/services/crane_scale_parser.dart';
import 'package:pullcrane/domain/services/fast_ble_scanner.dart';
import 'package:universal_ble/universal_ble.dart';

enum ScaleConnectionState { disconnected, scanning, connecting, connected }

/// Singleton wrapping the BLE crane scale (WH-C06) and the simulated
/// finger-drag input. The scale broadcasts weight in its advertisements.
///
/// On Android, force data is streamed by the native [FastBleScanner]
/// (low-latency scan with retry + watchdog). On other platforms a Dart
/// fallback parses advertisements from the universal_ble scan stream.
class CraneScaleService extends ChangeNotifier {
  static final CraneScaleService instance = CraneScaleService._();

  static const String defaultDeviceName = 'IF_B7';
  static const Duration scanTimeout = Duration(seconds: 15);
  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration _dataTimeout = Duration(seconds: 10);
  static const int _maxFastScannerRetries = 3;
  static const Duration _fastScannerRetryDelay = Duration(seconds: 1);

  CraneScaleService._() {
    _init();
  }

  bool _isSimulated = false;
  bool get isSimulated => _isSimulated;

  ScaleConnectionState _state = ScaleConnectionState.disconnected;
  ScaleConnectionState get state => _state;

  BleDevice? _connectedDevice;
  BleDevice? get connectedDevice => _connectedDevice;

  int _currentForce = 0;
  int get currentForce => _currentForce;

  /// Last user-facing error (permission denial, connect timeout, scan
  /// failure). Cleared on the next scan/connect attempt.
  String? get lastError => _lastError;
  String? _lastError;

  /// Only devices advertising this exact name are considered (discovery and
  /// Dart-fallback parsing). Note: the native Android fast scanner filters
  /// by the name compiled into FastBleScanHandler.kt.
  String _deviceNameFilter = defaultDeviceName;
  String get deviceNameFilter => _deviceNameFilter;
  set deviceNameFilter(String value) {
    final String trimmed = value.trim();
    _deviceNameFilter = trimmed.isEmpty ? defaultDeviceName : trimmed;
  }

  /// Upper clamp for parsed and simulated force readings.
  int maxForceKg = 200;

  StreamSubscription<BleDevice>? _scanSubscription;
  StreamSubscription<AvailabilityState>? _availabilitySubscription;
  FastBleScanner? _fastScanner;
  Timer? _scanTimeoutTimer;
  Timer? _connectTimeoutTimer;
  bool _isScanning = false;
  bool _fastScanActive = false;
  bool _isReconnecting = false;
  Timer? _dataTimeoutTimer;
  String? _connectingDeviceId;
  int _fastScannerRetryCount = 0;
  bool _retryPending = false;
  bool _fastScannerErrorFlag = false;
  Timer? _retryTimer;

  final Map<String, BleDevice> _scanResultById = <String, BleDevice>{};
  List<BleDevice> _scanResults = <BleDevice>[];
  List<BleDevice> get scanResults => _scanResults;

  /// The native fast scanner only exists on Android.
  bool get _useFastScanner =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  void _init() {
    _scanSubscription = UniversalBle.scanStream.listen((device) {
      final bool isTargetDevice = (device.name ?? '') == _deviceNameFilter;
      if (!isTargetDevice) {
        return;
      }

      bool hasUpdates = false;
      _scanResultById[device.deviceId] = device;

      if (_connectedDevice == null) {
        _scanResults = _scanResultById.values.toList()
          ..sort((a, b) {
            final int aRssi = a.rssi ?? -999;
            final int bRssi = b.rssi ?? -999;
            return bRssi.compareTo(aRssi);
          });
        hasUpdates = true;
      }

      // Dart fallback path (non-Android): parse force from advertisements.
      if (!_useFastScanner && _connectedDevice?.deviceId == device.deviceId) {
        _connectedDevice = device;
        final int? parsedForce = _parseWeightFromManufacturerData(device);
        if (parsedForce != null) {
          if (_state == ScaleConnectionState.connecting) {
            _state = ScaleConnectionState.connected;
            _connectTimeoutTimer?.cancel();
            _lastError = null;
          }
          if (parsedForce != _currentForce) {
            _currentForce = parsedForce;
          }
          _resetDataTimeout();
          hasUpdates = true;
        }
      }

      if (hasUpdates) {
        notifyListeners();
      }
    });

    _availabilitySubscription = UniversalBle.availabilityStream.listen((
      availability,
    ) {
      if (availability != AvailabilityState.poweredOn) {
        _handleDisconnect();
      }
    });
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _availabilitySubscription?.cancel();
    _scanTimeoutTimer?.cancel();
    _connectTimeoutTimer?.cancel();
    _dataTimeoutTimer?.cancel();
    _retryTimer?.cancel();
    super.dispose();
  }

  Future<bool> _ensureBlePermissions() async {
    if (kIsWeb) return true;
    if (defaultTargetPlatform != TargetPlatform.android) return true;

    final Map<Permission, PermissionStatus> statuses =
        await <Permission>[
          Permission.bluetoothScan,
          Permission.bluetoothConnect,
          Permission.locationWhenInUse,
        ].request();

    return statuses.values.every(
      (status) => status.isGranted || status.isLimited,
    );
  }

  Future<void> startScan() async {
    if (_isScanning) return;

    if (_connectedDevice == null) {
      _state = ScaleConnectionState.scanning;
      _scanResultById.clear();
      _scanResults = <BleDevice>[];
    }
    _lastError = null;
    notifyListeners();

    if (!await _ensureBlePermissions()) {
      _isScanning = false;
      _state = ScaleConnectionState.disconnected;
      _lastError =
          'Bluetooth permissions denied. Grant them in the system settings.';
      notifyListeners();
      return;
    }

    try {
      await UniversalBle.startScan(
        scanFilter: ScanFilter(withNamePrefix: [_deviceNameFilter]),
      );
      _isScanning = true;
      _scanTimeoutTimer?.cancel();
      _scanTimeoutTimer = Timer(scanTimeout, () {
        if (_connectedDevice == null) {
          stopScan();
        }
      });
    } catch (e) {
      debugPrint('Scan error: $e');
      _isScanning = false;
      _state = ScaleConnectionState.disconnected;
      _lastError = 'Failed to start scanning: $e';
      notifyListeners();
    }
  }

  Future<void> stopScan() async {
    _isScanning = false;
    _scanTimeoutTimer?.cancel();
    try {
      await UniversalBle.stopScan();
    } catch (_) {}
    if (_state == ScaleConnectionState.scanning && _connectedDevice == null) {
      _state = ScaleConnectionState.disconnected;
      notifyListeners();
    }
  }

  Future<void> connect(BleDevice device) async {
    if ((device.name ?? '') != _deviceNameFilter) {
      return;
    }
    if (_isReconnecting) return;
    _isReconnecting = true;

    _connectedDevice = device;
    _connectingDeviceId = device.deviceId;
    _state = ScaleConnectionState.connecting;
    _lastError = null;
    notifyListeners();

    _retryTimer?.cancel();
    _retryPending = false;
    _fastScannerRetryCount = 0;

    try {
      if (_useFastScanner) {
        await stopScan();
        await _startFastScanner(device.deviceId);
      } else {
        await _connectViaDartFallback();
      }
    } catch (e) {
      debugPrint('Connection error: $e');
      _lastError = 'Failed to connect: $e';
      if (_useFastScanner) {
        _fastScanActive = false;
        _retryOrFallback();
      } else {
        _handleDisconnect();
      }
    } finally {
      _isReconnecting = false;
    }
  }

  /// Non-Android path: force is parsed from the (already running) universal
  /// BLE scan stream; "connected" means a parseable advertisement arrives
  /// before [connectTimeout].
  Future<void> _connectViaDartFallback() async {
    if (!_isScanning) {
      await startScan();
    }
    _connectTimeoutTimer?.cancel();
    _connectTimeoutTimer = Timer(connectTimeout, () {
      if (_state == ScaleConnectionState.connecting) {
        _lastError = 'No data received from the scale. Is it on?';
        _handleDisconnect();
      }
    });
  }

  Future<void> _startFastScanner(String deviceId) async {
    debugPrint('CraneScale: starting fast scanner for $deviceId');

    await _fastScanner?.dispose();
    _fastScanner = null;
    _fastScannerErrorFlag = false;

    _fastScanner = FastBleScanner(
      onForceChanged: (int force) {
        _resetDataTimeout();
        final int clamped = force.clamp(0, maxForceKg);
        if (_currentForce != clamped) {
          _currentForce = clamped;
          if (_state == ScaleConnectionState.connecting) {
            _state = ScaleConnectionState.connected;
            _fastScannerRetryCount = 0;
            debugPrint('CraneScale: fast scanner connected, first force=$force');
          }
          notifyListeners();
        }
      },
      onError: (Object error) {
        debugPrint('CraneScale: fast scanner error: $error');
        _fastScannerErrorFlag = true;
        _fastScanActive = false;
        _retryOrFallback();
      },
    );

    _fastScanActive = true;
    await _fastScanner!.startTracking(deviceId);

    if (!_fastScannerErrorFlag) {
      if (_state == ScaleConnectionState.connecting) {
        _state = ScaleConnectionState.connected;
        debugPrint('CraneScale: fast scanner active, state -> connected');
      }
      notifyListeners();
      _resetDataTimeout();
    }
  }

  void _resetDataTimeout() {
    _dataTimeoutTimer?.cancel();
    if (_state == ScaleConnectionState.connected && !_isSimulated) {
      _dataTimeoutTimer = Timer(_dataTimeout, () {
        debugPrint('CraneScale: data timeout after ${_dataTimeout.inSeconds}s');
        if (_retryPending) {
          debugPrint('CraneScale: retry already pending, extending timeout');
          _resetDataTimeout();
          return;
        }
        if (_fastScanActive) {
          debugPrint('CraneScale: fast scanner silent failure, triggering retry');
          _handleFastScannerSilentFailure();
        } else {
          debugPrint('CraneScale: no force data, disconnecting');
          _lastError = 'Lost connection to the scale (no data).';
          _handleDisconnect();
          startScan();
        }
      });
    }
  }

  void _handleFastScannerSilentFailure() {
    _fastScanActive = false;
    _retryOrFallback();
  }

  void _retryOrFallback() {
    if (_retryPending) return;

    _fastScanner?.dispose();
    _fastScanner = null;

    if (_fastScannerRetryCount < _maxFastScannerRetries) {
      _retryPending = true;
      _fastScannerRetryCount++;
      debugPrint(
          'CraneScale: scheduling fast scanner retry $_fastScannerRetryCount/$_maxFastScannerRetries');
      _retryTimer = Timer(_fastScannerRetryDelay, () async {
        _retryPending = false;
        if (_connectingDeviceId != null) {
          await _startFastScanner(_connectingDeviceId!);
        }
      });
    } else {
      debugPrint('CraneScale: fast scanner retries exhausted, disconnecting');
      _lastError = 'Lost connection to the scale after several retries.';
      _handleDisconnect();
    }
  }

  int? _parseWeightFromManufacturerData(BleDevice device) {
    for (final ManufacturerData manufacturerData
        in device.manufacturerDataList) {
      final Uint8List fullBytes = manufacturerData.toUint8List();
      final int? valueFromFull = CraneScaleParser.parseWeightKg(
        fullBytes,
        maxForceKg: maxForceKg,
      );
      if (valueFromFull != null) return valueFromFull;

      final int? valueFromPayload = CraneScaleParser.parseWeightKg(
        manufacturerData.payload,
        offset: CraneScaleParser.payloadWeightOffset,
        maxForceKg: maxForceKg,
      );
      if (valueFromPayload != null) return valueFromPayload;
    }
    return null;
  }

  Future<void> disconnect() async {
    await _handleDisconnect();
    startScan();
  }

  Future<void> connectSimulated() async {
    _retryTimer?.cancel();
    _retryPending = false;
    _connectingDeviceId = null;
    _connectTimeoutTimer?.cancel();
    await stopScan();
    await _handleDisconnect();
    _isSimulated = true;
    _state = ScaleConnectionState.connected;
    _lastError = null;
    notifyListeners();
  }

  void updateSimulatedForce(int force) {
    if (_isSimulated && _state == ScaleConnectionState.connected) {
      final int clamped = force.clamp(0, maxForceKg);
      if (_currentForce != clamped) {
        _currentForce = clamped;
        notifyListeners();
      }
    }
  }

  Future<void> _handleDisconnect() async {
    _retryTimer?.cancel();
    _retryPending = false;
    _connectingDeviceId = null;
    _fastScanner?.dispose();
    _fastScanner = null;
    _fastScanActive = false;
    _connectedDevice = null;
    _isSimulated = false;
    _state = ScaleConnectionState.disconnected;
    _currentForce = 0;
    _scanTimeoutTimer?.cancel();
    _connectTimeoutTimer?.cancel();
    _dataTimeoutTimer?.cancel();
    _isReconnecting = false;
    notifyListeners();
    if (_isScanning) {
      _isScanning = false;
      try {
        await UniversalBle.stopScan();
      } catch (_) {}
    }
  }
}
