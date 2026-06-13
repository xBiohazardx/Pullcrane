import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:pullcrane/domain/services/fast_ble_scanner.dart';

enum ScaleConnectionState { disconnected, scanning, connecting, connected }

class CraneScaleService extends ChangeNotifier {
  static final CraneScaleService instance = CraneScaleService._();

  static const String _targetDeviceName = 'IF_B7';
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

  StreamSubscription<BleDevice>? _scanSubscription;
  FastBleScanner? _fastScanner;
  Timer? _scanTimeoutTimer;
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
  List<BleDevice> _scanResults = [];
  List<BleDevice> get scanResults => _scanResults;

  void _init() {
    _scanSubscription = UniversalBle.scanStream.listen((device) {
      final bool isTargetDevice = (device.name ?? '') == _targetDeviceName;
      if (!isTargetDevice) {
        return;
      }

      _scanResultById[device.deviceId] = device;

      if (_connectedDevice == null) {
        _scanResults = _scanResultById.values.toList()
          ..sort((a, b) {
            final int aRssi = a.rssi ?? -999;
            final int bRssi = b.rssi ?? -999;
            return bRssi.compareTo(aRssi);
          });
        notifyListeners();
      }
    });

    UniversalBle.availabilityStream.listen((availability) {
      if (availability != AvailabilityState.poweredOn) {
        _handleDisconnect();
      }
    });
  }

  Future<void> _ensureBlePermissions() async {
    if (kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.android) return;

    final List<Permission> permissions = <Permission>[
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ];
    await permissions.request();
  }

  Future<void> startScan() async {
    if (_isScanning) return;

    if (_connectedDevice == null) {
      _state = ScaleConnectionState.scanning;
      _scanResultById.clear();
      _scanResults = <BleDevice>[];
    }
    notifyListeners();

    try {
      await _ensureBlePermissions();
      await UniversalBle.startScan(
        scanFilter: ScanFilter(withNamePrefix: [_targetDeviceName]),
      );
      _isScanning = true;
      _scanTimeoutTimer?.cancel();
      _scanTimeoutTimer = Timer(const Duration(seconds: 15), () {
        if (_connectedDevice == null) {
          stopScan();
        }
      });
    } catch (e) {
      debugPrint("Scan error: $e");
      _isScanning = false;
      _state = ScaleConnectionState.disconnected;
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
    if ((device.name ?? '') != _targetDeviceName) {
      return;
    }
    if (_isReconnecting) return;
    _isReconnecting = true;

    _connectedDevice = device;
    _connectingDeviceId = device.deviceId;
    _state = ScaleConnectionState.connecting;
    notifyListeners();

    _retryTimer?.cancel();
    _retryPending = false;
    _fastScannerRetryCount = 0;

    try {
      await stopScan();
      await _startFastScanner(device.deviceId);
    } catch (e) {
      debugPrint("Fast scanner setup failed: $e");
      _fastScanActive = false;
      _retryOrFallback();
    } finally {
      _isReconnecting = false;
    }
  }

  Future<void> _startFastScanner(String deviceId) async {
    debugPrint('CraneScale: starting fast scanner for $deviceId');

    await _fastScanner?.dispose();
    _fastScanner = null;
    _fastScannerErrorFlag = false;

    _fastScanner = FastBleScanner(
      onForceChanged: (int force) {
        _resetDataTimeout();
        if (_currentForce != force) {
          _currentForce = force;
          if (_state == ScaleConnectionState.connecting) {
            _state = ScaleConnectionState.connected;
            _fastScannerRetryCount = 0;
            debugPrint('CraneScale: fast scanner connected, first force=$force');
          }
          notifyListeners();
        }
      },
      onError: (Object error) {
        debugPrint("CraneScale: fast scanner error: $error");
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
          debugPrint('CraneScale: not in fast scan mode, hard disconnecting');
          try {
            _handleDisconnect();
          } catch (e) {
            debugPrint('CraneScale: error during timeout disconnect: $e');
          }
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
      debugPrint('CraneScale: scheduling fast scanner retry $_fastScannerRetryCount/$_maxFastScannerRetries');
      _retryTimer = Timer(_fastScannerRetryDelay, () async {
        _retryPending = false;
        if (_connectingDeviceId != null) {
          await _startFastScanner(_connectingDeviceId!);
        }
      });
    } else {
      debugPrint('CraneScale: fast scanner retries exhausted, disconnecting');
      _handleDisconnect();
    }
  }

  Future<void> disconnect() async {
    await _handleDisconnect();
    startScan();
  }

  Future<void> connectSimulated() async {
    _retryTimer?.cancel();
    _retryPending = false;
    _connectingDeviceId = null;
    await stopScan();
    _handleDisconnect();
    _isSimulated = true;
    _state = ScaleConnectionState.connected;
    notifyListeners();
  }

  void updateSimulatedForce(int force) {
    if (_isSimulated && _state == ScaleConnectionState.connected) {
      if (_currentForce != force) {
        _currentForce = force;
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

