import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pullcrane/ui/force_chart.dart';
import 'package:pullcrane/ui/force_input_dummy.dart';

class ForceTrainingPage extends StatefulWidget {
  const ForceTrainingPage({super.key, required this.title});

  final String title;

  @override
  State<ForceTrainingPage> createState() => _ForceTrainingPageState();
}

class _ForceTrainingPageState extends State<ForceTrainingPage> {
  static const int minForceKg = 0;
  static const int maxForceKg = 100;
  static const int targetMinForceKg = 60;
  static const int targetMaxForceKg = 75;
  static const double dummySensitivity = 0.3;
  static const Duration staleInputTimeout = Duration(milliseconds: 120);
  static const Duration targetVibrationInterval = Duration(milliseconds: 280);

  List<FlSpot> dataPoints = List.empty(growable: true);
  int currentForce = 0;
  int maxForce = 0;
  int timeIndex = 0;
  DateTime lastForceUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  bool isTouching = false;
  bool isInTargetRange = false;
  late final Timer samplingTimer;
  Timer? targetVibrationTimer;

  bool _isInsideTarget(int force) {
    return force >= targetMinForceKg && force <= targetMaxForceKg;
  }

  void _syncTargetFeedback(int force) {
    final bool nextInTargetRange = _isInsideTarget(force);
    if (nextInTargetRange == isInTargetRange) {
      return;
    }

    isInTargetRange = nextInTargetRange;
    if (isInTargetRange) {
      HapticFeedback.selectionClick();
      targetVibrationTimer?.cancel();
      targetVibrationTimer = Timer.periodic(targetVibrationInterval, (_) {
        HapticFeedback.lightImpact();
      });
    } else {
      targetVibrationTimer?.cancel();
      targetVibrationTimer = null;
    }
  }

  @override
  void initState() {
    super.initState();
    for(int i = 0; i < 500; i++) {
      dataPoints.add(FlSpot(i.toDouble(), 0));
    }

    samplingTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      setState(() {
        final bool hasFreshInput =
            DateTime.now().difference(lastForceUpdate) <= staleInputTimeout;

        // If no fresh updates arrive for a short time, sample 0 to avoid stale force values.
        if (!hasFreshInput && !isTouching) {
          currentForce = 0;
        }

        final int sampledForce = currentForce.clamp(minForceKg, maxForceKg);
        currentForce = sampledForce;
        _syncTargetFeedback(sampledForce);

        dataPoints.add(FlSpot(timeIndex.toDouble(), sampledForce.toDouble()));
        timeIndex++;
        if (dataPoints.length > 500) {
          dataPoints.removeAt(0);
        }

        if (sampledForce > maxForce) {
          maxForce = sampledForce;
        }
      });
    });
  }

  void _onDummyForceChanged(int force) {
    setState(() {
      currentForce = force.clamp(minForceKg, maxForceKg);
      lastForceUpdate = DateTime.now();
      _syncTargetFeedback(currentForce);
    });
  }

  void _onDummyTouchingChanged(bool touching) {
    setState(() {
      isTouching = touching;
      if (touching) {
        lastForceUpdate = DateTime.now();
      }
    });
  }

  @override
  void dispose() {
    samplingTimer.cancel();
    targetVibrationTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: ForceInputDummy(
        sensitivity: dummySensitivity,
        minForce: minForceKg,
        maxForce: maxForceKg,
        onForceChanged: _onDummyForceChanged,
        onTouchingChanged: _onDummyTouchingChanged,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Force: ${currentForce}kg',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: isInTargetRange ? Colors.green : null,
                  ),
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: FractionallySizedBox(
                  widthFactor: 0.95,
                  heightFactor: 0.95,
                  child: ForceChart(
                    dataPoints: dataPoints,
                    chartMaxForce: maxForceKg,
                    targetMinForce: targetMinForceKg,
                    targetMaxForce: targetMaxForceKg,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

