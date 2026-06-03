import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class FastBleScanner {
  static const String _channelName = 'com.teq_tech.pullcrane/fast_ble_scan';
  static const EventChannel _eventChannel = EventChannel(_channelName);

  StreamSubscription<Map<Object?, Object?>>? _subscription;
  final void Function(int force) onForceChanged;
  final void Function(Object error) onError;
  int _eventCount = 0;
  DateTime _lastLog = DateTime.now();

  FastBleScanner({
    required this.onForceChanged,
    required this.onError,
  });

  bool get isTracking => _subscription != null;

  Future<void> startTracking(String deviceId) async {
    await stopTracking();
    debugPrint('FastBleScanner: startTracking($deviceId)');
    _eventCount = 0;
    _lastLog = DateTime.now();

    _subscription = _eventChannel
        .receiveBroadcastStream(deviceId)
        .cast<Map<Object?, Object?>>()
        .listen(
          (Map<Object?, Object?> event) {
            _eventCount++;
            final Object? forceValue = event['force'];
            if (forceValue is int) {
              onForceChanged(forceValue);
            }

            final now = DateTime.now();
            if (now.difference(_lastLog).inSeconds >= 2) {
              debugPrint(
                  'FastBleScanner: $_eventCount events in last 2s, latest force=$forceValue');
              _eventCount = 0;
              _lastLog = now;
            }
          },
          onError: (Object error) {
            debugPrint('FastBleScanner: error=$error');
            onError(error);
          },
          cancelOnError: false,
        );
  }

  Future<void> stopTracking() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  Future<void> dispose() async {
    await stopTracking();
  }
}
