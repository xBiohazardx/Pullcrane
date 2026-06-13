import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:pullcrane/domain/services/fast_ble_scanner.dart';

enum ScaleConnectionState { disconnected, scanning, connecting, connected }

class CraneScaleService extends ChangeNotifier {
  static final CraneScaleService instance = CraneScaleService._();

  static const String _targetDeviceName = 'IF_B7';
  static const int _weightOffset = 12;
  static const int _weightLength = 2;
  static const Duration _dataTimeout = Duration(seconds: 10);

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

      if (!_fastScanActive && _connectedDevice?.deviceId == device.deviceId) {
        _connectedDevice = device;
        final int? parsedForce = _parseWeightFromManufacturerData(device);
        if (parsedForce != null) {
          if (_state == ScaleConnectionState.connecting) {
            _state = ScaleConnectionState.connected;
          }
          if (parsedForce != _currentForce) {
            _currentForce = parsedForce;
          }
          notifyListeners();
          _resetDataTimeout();
        }
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
    _state = ScaleConnectionState.connecting;
    notifyListeners();

    try {
      await stopScan();
      await _startFastScanner(device.deviceId);
    } catch (e) {
      debugPrint("Fast scanner failed, falling back to advertisements: $e");
      _fastScanActive = false;
      _fallbackToAdvertisements();
    } finally {
      _isReconnecting = false;
    }
  }

  Future<void> _startFastScanner(String deviceId) async {
    debugPrint('CraneScale: starting fast scanner for $deviceId');

    _fastScanner = FastBleScanner(
      onForceChanged: (int force) {
        _resetDataTimeout();
        if (_currentForce != force) {
          _currentForce = force;
          if (_state == ScaleConnectionState.connecting) {
            _state = ScaleConnectionState.connected;
            debugPrint('CraneScale: fast scanner connected, first force=$force');
          }
          notifyListeners();
        }
      },
      onError: (Object error) {
        debugPrint("CraneScale: fast scanner error -> falling back: $error");
        _fastScanActive = false;
        _fallbackToAdvertisements();
      },
    );

    await _fastScanner!.startTracking(deviceId);
    _fastScanActive = true;
    if (_state == ScaleConnectionState.connecting) {
      _state = ScaleConnectionState.connected;
      debugPrint('CraneScale: fast scanner active, state -> connected');
    }
    notifyListeners();
    _resetDataTimeout();
  }

  void _resetDataTimeout() {
    _dataTimeoutTimer?.cancel();
    if (_state == ScaleConnectionState.connected && !_isSimulated) {
      _dataTimeoutTimer = Timer(_dataTimeout, () {
        debugPrint('CraneScale: data timeout after ${_dataTimeout.inSeconds}s, disconnecting');
        try {
          _handleDisconnect();
        } catch (e) {
          debugPrint('CraneScale: error during timeout disconnect: $e');
        }
      });
    }
  }

  Future<void> _fallbackToAdvertisements() async {
    await startScan();
    if (_connectedDevice != null) {
      _state = ScaleConnectionState.connected;
      notifyListeners();
      _resetDataTimeout();
    }
  }

  int? _parseWeightFromManufacturerData(BleDevice device) {
    for (final ManufacturerData manufacturerData
        in device.manufacturerDataList) {
      final Uint8List fullBytes = manufacturerData.toUint8List();
      final int? valueFromFull =
          _parseWeightFromBytes(fullBytes, _weightOffset);
      if (valueFromFull != null) return valueFromFull;

      final int adjustedOffset = _weightOffset - 2;
      final int? valueFromPayload = _parseWeightFromBytes(
        manufacturerData.payload,
        adjustedOffset,
      );
      if (valueFromPayload != null) return valueFromPayload;
    }
    return null;
  }

  int? _parseWeightFromBytes(Uint8List bytes, int offset) {
    if (offset < 0 || bytes.length < offset + _weightLength) {
      return null;
    }

    final ByteData data =
        ByteData.sublistView(bytes, offset, offset + _weightLength);
    final int rawWeight = data.getInt16(0, Endian.big);
    final double kilograms = rawWeight / 100.0;
    return kilograms.round().clamp(0, 100);
  }

  Future<void> disconnect() async {
    await _handleDisconnect();
    startScan();
  }

  Future<void> connectSimulated() async {
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

