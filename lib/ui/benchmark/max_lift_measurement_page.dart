import 'package:flutter/material.dart';
import 'package:pullcrane/domain/models/exercise.dart';
import 'package:pullcrane/ui/force_input_dummy.dart';

class MaxLiftMeasurementPage extends StatefulWidget {
  const MaxLiftMeasurementPage({super.key, required this.exercise});

  final Exercise exercise;

  @override
  State<MaxLiftMeasurementPage> createState() => _MaxLiftMeasurementPageState();
}

class _MaxLiftMeasurementPageState extends State<MaxLiftMeasurementPage> {
  static const int minForceKg = 0;
  static const int maxForceKg = 100;
  static const double dummySensitivity = 0.3;

  late ExerciseHand selectedHand;
  int currentLeftForceKg = 0;
  int currentRightForceKg = 0;
  int maxLeftForceKg = 0;
  int maxRightForceKg = 0;

  bool get isTwoHandMeasurement => widget.exercise.isSideSwitching;

  @override
  void initState() {
    super.initState();
    selectedHand = widget.exercise.startingHand;
    maxLeftForceKg = widget.exercise.maxLiftLeftKg;
    maxRightForceKg = widget.exercise.maxLiftRightKg;
  }

  String _handLabel(ExerciseHand hand) {
    return hand == ExerciseHand.left ? 'Left' : 'Right';
  }

  void _onForceChanged(int forceKg) {
    final int clamped = forceKg.clamp(minForceKg, maxForceKg);
    setState(() {
      if (selectedHand == ExerciseHand.left) {
        currentLeftForceKg = clamped;
        if (clamped > maxLeftForceKg) {
          maxLeftForceKg = clamped;
        }
        currentRightForceKg = 0;
      } else {
        currentRightForceKg = clamped;
        if (clamped > maxRightForceKg) {
          maxRightForceKg = clamped;
        }
        currentLeftForceKg = 0;
      }
    });
  }

  void _setSelectedHand(ExerciseHand hand) {
    if (selectedHand == hand) {
      return;
    }
    setState(() {
      selectedHand = hand;
      currentLeftForceKg = 0;
      currentRightForceKg = 0;
    });
  }

  void _saveAndClose() {
    final Exercise updatedExercise = widget.exercise.copyWith(
      maxLiftLeftKg: maxLeftForceKg,
      maxLiftRightKg: maxRightForceKg,
    );
    Navigator.of(context).pop(updatedExercise);
  }

  Widget _buildForceBar({
    required BuildContext context,
    required String label,
    required int currentForceKg,
    required int maxForceRecordedKg,
    required bool isActive,
  }) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Card(
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: isActive ? colors.primary : colors.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Column(
          children: [
            Text(label, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SizedBox(
              height: 220,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final double barHeight = constraints.maxHeight;
                  final double currentRatio =
                      (currentForceKg / maxForceKg).clamp(0, 1).toDouble();
                  final double maxRatio =
                      (maxForceRecordedKg / maxForceKg).clamp(0, 1).toDouble();
                  final double currentHeight = barHeight * currentRatio;
                  final double maxLineBottom =
                      ((barHeight * maxRatio) - 1).clamp(0, barHeight - 2).toDouble();

                  return Stack(
                    children: [
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: colors.surfaceContainerHighest.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 90),
                          height: currentHeight,
                          decoration: BoxDecoration(
                            color: colors.primary.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: maxLineBottom,
                        child: Container(
                          height: 2,
                          color: colors.tertiary,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Text('Current ${currentForceKg}kg • Max ${maxForceRecordedKg}kg'),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Max Lift: ${widget.exercise.name}')),
      body: ForceInputDummy(
        sensitivity: dummySensitivity,
        minForce: minForceKg,
        maxForce: maxForceKg,
        onForceChanged: _onForceChanged,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<ExerciseHand>(
                segments: const [
                  ButtonSegment<ExerciseHand>(
                    value: ExerciseHand.left,
                    label: Text('Left'),
                  ),
                  ButtonSegment<ExerciseHand>(
                    value: ExerciseHand.right,
                    label: Text('Right'),
                  ),
                ],
                selected: <ExerciseHand>{selectedHand},
                onSelectionChanged: (hands) {
                  _setSelectedHand(hands.first);
                },
              ),
              const SizedBox(height: 12),
              Text(
                'Drag anywhere to measure ${_handLabel(selectedHand)} hand force.',
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildForceBar(
                      context: context,
                      label: 'Left hand',
                      currentForceKg: currentLeftForceKg,
                      maxForceRecordedKg: maxLeftForceKg,
                      isActive: selectedHand == ExerciseHand.left,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildForceBar(
                      context: context,
                      label: 'Right hand',
                      currentForceKg: currentRightForceKg,
                      maxForceRecordedKg: maxRightForceKg,
                      isActive: selectedHand == ExerciseHand.right,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _saveAndClose,
                      child: const Text('Save max lift'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
