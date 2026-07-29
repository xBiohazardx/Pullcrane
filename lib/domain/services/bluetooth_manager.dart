import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pullcrane/domain/services/crane_scale_parser.dart';
import 'package:universal_ble/universal_ble.dart';

enum ScaleConnectionState { disconnected, scanning, connecting, connected }

/// Singleton wrapping the BLE crane scale (WH-C06) and the simulated
/// finger-drag input. The scale broadcasts weight in its advertisements, so
/// "connected" means "advertisements from the selected device parse
/// successfully" — there is no GATT connection.
class CraneScaleService extends ChangeNotifier {
  static final CraneScaleService instance = CraneScaleService._();

  static const String defaultDeviceName = 'IF_B7';
  static const Duration scanTimeout = Duration(seconds: 15);
  static const Duration connectTimeout = Duration(seconds: 10);

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

  /// Only advertisements from devices with exactly this name are considered.
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
  Timer? _scanTimeoutTimer;
  Timer? _connectTimeoutTimer;
  bool _isScanning = false;

  final Map<String, BleDevice> _scanResultById = <String, BleDevice>{};
  List<BleDevice> _scanResults = <BleDevice>[];
  List<BleDevice> get scanResults => _scanResults;

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

      if (_connectedDevice?.deviceId == device.deviceId) {
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
      await UniversalBle.startScan();
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
    _scanTimeoutTimer?.cancel();
    try {
      await UniversalBle.stopScan();
    } catch (e) {
      debugPrint('Stop scan error: $e');
    }
    _isScanning = false;
    if (_state == ScaleConnectionState.scanning && _connectedDevice == null) {
      _state = ScaleConnectionState.disconnected;
      notifyListeners();
    }
  }

  Future<void> connect(BleDevice device) async {
    if ((device.name ?? '') != _deviceNameFilter) {
      return;
    }

    _connectedDevice = device;
    _state = ScaleConnectionState.connecting;
    _lastError = null;
    notifyListeners();

    // If no parseable advertisement arrives in time, give up instead of
    // sitting in "connecting" forever.
    _connectTimeoutTimer?.cancel();
    _connectTimeoutTimer = Timer(connectTimeout, () {
      if (_state == ScaleConnectionState.connecting) {
        _lastError = 'No data received from "${device.name}". Is it on?';
        _handleDisconnect();
      }
    });

    try {
      // WH-C06 data is read from advertisement manufacturer data.
      // Keep scanning with duplicates so force updates continue to stream.
      if (!_isScanning) {
        await startScan();
      }
    } catch (e) {
      debugPrint('Connection error: $e');
      _lastError = 'Failed to connect: $e';
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
    _handleDisconnect();
  }

  Future<void> connectSimulated() async {
    await stopScan();
    _handleDisconnect(); // clear real connection
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

  void _handleDisconnect() {
    _connectedDevice = null;
    _isSimulated = false;
    _state = ScaleConnectionState.disconnected;
    _currentForce = 0;
    _scanTimeoutTimer?.cancel();
    _connectTimeoutTimer?.cancel();
    if (_isScanning) {
      _isScanning = false;
      unawaited(UniversalBle.stopScan());
    }
    notifyListeners();
  }
}
