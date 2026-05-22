import 'package:flutter/material.dart';

class ForceInputDummy extends StatefulWidget {
  final Widget child;
  final ValueChanged<int> onForceChanged;
  final ValueChanged<bool>? onTouchingChanged;
  final double sensitivity;
  final int minForce;
  final int maxForce;

  const ForceInputDummy({
    super.key,
    required this.child,
    required this.onForceChanged,
    this.onTouchingChanged,
    required this.sensitivity,
    this.minForce = 0,
    this.maxForce = 100,
  });

  @override
  State<ForceInputDummy> createState() => _ForceInputDummyState();
}

class _ForceInputDummyState extends State<ForceInputDummy> {
  double startY = 0;

  int _clampForce(int value) {
    return value.clamp(widget.minForce, widget.maxForce);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) {
        widget.onTouchingChanged?.call(true);
      },
      onPointerUp: (_) {
        widget.onTouchingChanged?.call(false);
        widget.onForceChanged(widget.minForce);
      },
      onPointerCancel: (_) {
        widget.onTouchingChanged?.call(false);
        widget.onForceChanged(widget.minForce);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (details) {
          startY = details.globalPosition.dy;
        },
        onPanUpdate: (details) {
          final double delta = (startY - details.globalPosition.dy).abs();
          final int scaledForce = (delta * widget.sensitivity).round();
          widget.onForceChanged(_clampForce(scaledForce));
        },
        child: widget.child,
      ),
    );
  }
}

