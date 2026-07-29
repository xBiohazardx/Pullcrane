import 'package:flutter/material.dart';
import 'package:pullcrane/domain/services/bluetooth_manager.dart';

/// Wraps a page and translates vertical finger drags into simulated force
/// readings on [CraneScaleService] (when the simulated device is connected).
class ForceInputDummy extends StatefulWidget {
  final Widget child;
  final double sensitivity;
  final int minForce;
  final int maxForce;
  final bool isEnabled;

  const ForceInputDummy({
    super.key,
    required this.child,
    required this.sensitivity,
    this.minForce = 0,
    this.maxForce = 100,
    this.isEnabled = false,
  });

  @override
  State<ForceInputDummy> createState() => _ForceInputDummyState();
}

class _ForceInputDummyState extends State<ForceInputDummy> {
  double startY = 0;

  int _clampForce(int value) {
    return value.clamp(widget.minForce, widget.maxForce);
  }

  void _updateForce(int value) {
    CraneScaleService.instance.updateSimulatedForce(value);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isEnabled) return widget.child;

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerUp: (_) {
        _updateForce(widget.minForce);
      },
      onPointerCancel: (_) {
        _updateForce(widget.minForce);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (details) {
          startY = details.globalPosition.dy;
        },
        onPanUpdate: (details) {
          final double delta = (startY - details.globalPosition.dy).abs();
          final int scaledForce = (delta * widget.sensitivity).round();
          _updateForce(_clampForce(scaledForce));
        },
        child: widget.child,
      ),
    );
  }
}
