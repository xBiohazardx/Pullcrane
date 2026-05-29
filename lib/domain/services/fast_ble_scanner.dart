import 'dart:async';
import 'package:flutter/services.dart';

class FastBleScanner {
  static const String _channelName = 'com.teq_tech.pullcrane/fast_ble_scan';
  static const EventChannel _eventChannel = EventChannel(_channelName);

  StreamSubscription<Map<Object?, Object?>>? _subscription;
  final void Function(int force) onForceChanged;
  final void Function(Object error) onError;

  FastBleScanner({
    required this.onForceChanged,
    required this.onError,
  });

  bool get isTracking => _subscription != null;

  Future<void> startTracking(String deviceId) async {
    await stopTracking();

    _subscription = _eventChannel
        .receiveBroadcastStream(deviceId)
        .cast<Map<Object?, Object?>>()
        .listen(
          (Map<Object?, Object?> event) {
            final Object? forceValue = event['force'];
            if (forceValue is int) {
              onForceChanged(forceValue);
            }
          },
          onError: onError,
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
