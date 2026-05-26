import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:pullcrane/data/app_repositories.dart';
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

  late Exercise currentExercise;
  late ExerciseHand selectedHand;
  int currentLeftForceKg = 0;
  int currentRightForceKg = 0;
  int maxLeftForceKg = 0;
  int maxRightForceKg = 0;

  int forceThresholdKg = 10;
  bool isSettingsLoaded = false;

  bool get isTwoHandMeasurement => currentExercise.isSideSwitching;

  bool get canSave {
    if (!isSettingsLoaded) return false;
    if (isTwoHandMeasurement) {
      return maxLeftForceKg >= forceThresholdKg &&
          maxRightForceKg >= forceThresholdKg;
    } else {
      return selectedHand == ExerciseHand.left
          ? maxLeftForceKg >= forceThresholdKg
          : maxRightForceKg >= forceThresholdKg;
    }
  }

  @override
  void initState() {
    super.initState();
    currentExercise = widget.exercise;
    selectedHand = currentExercise.startingHand;
    maxLeftForceKg = 0;
    maxRightForceKg = 0;
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await AppRepositories.settings.load();
    if (mounted) {
      setState(() {
        forceThresholdKg = settings.forceThresholdKg;
        isSettingsLoaded = true;
      });
    }
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

  Future<void> _saveMaxLift() async {
    final newRecord = MaxLiftRecord(
      date: DateTime.now(),
      leftKg: maxLeftForceKg,
      rightKg: maxRightForceKg,
    );

    final List<MaxLiftRecord> newHistory = List.from(
      currentExercise.maxLiftHistory,
    )..add(newRecord);

    int newAbsoluteMaxLeft = 0;
    int newAbsoluteMaxRight = 0;
    for (var record in newHistory) {
      if (record.leftKg > newAbsoluteMaxLeft) {
        newAbsoluteMaxLeft = record.leftKg;
      }
      if (record.rightKg > newAbsoluteMaxRight) {
        newAbsoluteMaxRight = record.rightKg;
      }
    }

    final Exercise updatedExercise = currentExercise.copyWith(
      maxLiftLeftKg: newAbsoluteMaxLeft,
      maxLiftRightKg: newAbsoluteMaxRight,
      maxLiftHistory: newHistory,
    );

    await AppRepositories.exercises.saveExercise(updatedExercise);

    if (!mounted) return;

    setState(() {
      currentExercise = updatedExercise;
      maxLeftForceKg = 0;
      maxRightForceKg = 0;
      currentLeftForceKg = 0;
      currentRightForceKg = 0;
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Max lift saved!')));
  }

  Widget _buildProgressionChart() {
    if (currentExercise.maxLiftHistory.isEmpty) {
      return const Center(child: Text('No progression data yet.'));
    }

    final Map<String, MaxLiftRecord> latestPerDay = {};
    for (final record in currentExercise.maxLiftHistory) {
      final dateKey =
          '${record.date.year}-${record.date.month.toString().padLeft(2, '0')}-${record.date.day.toString().padLeft(2, '0')}';
      if (!latestPerDay.containsKey(dateKey) ||
          record.date.isAfter(latestPerDay[dateKey]!.date)) {
        latestPerDay[dateKey] = record;
      }
    }

    final filteredHistory = latestPerDay.values.toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    final DateTime firstDateRaw = filteredHistory.first.date;
    final DateTime firstDateDay = DateTime(
      firstDateRaw.year,
      firstDateRaw.month,
      firstDateRaw.day,
    );

    List<FlSpot> leftSpots = [];
    List<FlSpot> rightSpots = [];

    double maxY = 10; // minimum chart height
    double maxX = 0;

    for (int i = 0; i < filteredHistory.length; i++) {
      final record = filteredHistory[i];
      final recordDay = DateTime(
        record.date.year,
        record.date.month,
        record.date.day,
      );
      final double days = recordDay.difference(firstDateDay).inDays.toDouble();

      leftSpots.add(FlSpot(days, record.leftKg.toDouble()));
      rightSpots.add(FlSpot(days, record.rightKg.toDouble()));

      maxY = max(maxY, record.leftKg.toDouble());
      maxY = max(maxY, record.rightKg.toDouble());
      maxX = max(maxX, days);
    }

    maxY = (maxY * 1.2).ceilToDouble(); // Add some padding
    if (maxX == 0) {
      maxX = 1.0; // Pad X axis if only one point or all on the same day
    }

    final ColorScheme colors = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isTwoHandMeasurement) ...[
              _buildLegendItem('Left', colors.primary),
              const SizedBox(width: 16),
              _buildLegendItem('Right', colors.secondary),
            ] else ...[
              _buildLegendItem('Force', colors.primary),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: maxX,
              minY: 0,
              maxY: maxY,
              lineBarsData: [
                if (!isTwoHandMeasurement || leftSpots.any((s) => s.y > 0))
                  LineChartBarData(
                    spots: leftSpots,
                    isCurved: true,
                    color: colors.primary,
                    barWidth: 3,
                    dotData: const FlDotData(show: true),
                  ),
                if (isTwoHandMeasurement && rightSpots.any((s) => s.y > 0))
                  LineChartBarData(
                    spots: rightSpots,
                    isCurved: true,
                    color: colors.secondary,
                    barWidth: 3,
                    dotData: const FlDotData(show: true),
                  ),
              ],
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: 1,
                    getTitlesWidget: (value, meta) {
                      final bool hasPoint = filteredHistory.any((r) {
                        final rd = DateTime(
                          r.date.year,
                          r.date.month,
                          r.date.day,
                        );
                        return rd.difference(firstDateDay).inDays.toDouble() ==
                            value;
                      });

                      if (!hasPoint) return const SizedBox.shrink();

                      final date = firstDateDay.add(
                        Duration(days: value.toInt()),
                      );
                      final dayStr = date.day.toString().padLeft(2, '0');
                      final monthStr = date.month.toString().padLeft(2, '0');
                      return Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          '$dayStr.$monthStr.',
                          style: const TextStyle(fontSize: 10),
                        ),
                      );
                    },
                  ),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 32,
                    getTitlesWidget: (value, meta) {
                      return Text(
                        value.toInt().toString(),
                        style: const TextStyle(fontSize: 10),
                      );
                    },
                  ),
                ),
              ),
              gridData: const FlGridData(show: true, drawVerticalLine: false),
              borderData: FlBorderData(show: false),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
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
                  final double currentRatio = (currentForceKg / maxForceKg)
                      .clamp(0, 1)
                      .toDouble();
                  final double maxRatio = (maxForceRecordedKg / maxForceKg)
                      .clamp(0, 1)
                      .toDouble();
                  final double currentHeight = barHeight * currentRatio;
                  final double maxLineBottom = ((barHeight * maxRatio) - 1)
                      .clamp(0, barHeight - 2)
                      .toDouble();

                  return Stack(
                    children: [
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: colors.surfaceContainerHighest.withValues(
                              alpha: 0.35,
                            ),
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
                        child: Container(height: 2, color: colors.tertiary),
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
      appBar: AppBar(title: Text('Max Lift: ${currentExercise.name}')),
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
              if (isTwoHandMeasurement) ...[
                Text(
                  'Tap a bar to select, then drag anywhere to measure ${_handLabel(selectedHand)} hand force.',
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _setSelectedHand(ExerciseHand.left),
                        child: _buildForceBar(
                          context: context,
                          label: 'Left hand',
                          currentForceKg: currentLeftForceKg,
                          maxForceRecordedKg: maxLeftForceKg,
                          isActive: selectedHand == ExerciseHand.left,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _setSelectedHand(ExerciseHand.right),
                        child: _buildForceBar(
                          context: context,
                          label: 'Right hand',
                          currentForceKg: currentRightForceKg,
                          maxForceRecordedKg: maxRightForceKg,
                          isActive: selectedHand == ExerciseHand.right,
                        ),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                const Text('Drag anywhere to measure force.'),
                const SizedBox(height: 12),
                _buildForceBar(
                  context: context,
                  label: 'Force',
                  currentForceKg: selectedHand == ExerciseHand.left
                      ? currentLeftForceKg
                      : currentRightForceKg,
                  maxForceRecordedKg: selectedHand == ExerciseHand.left
                      ? maxLeftForceKg
                      : maxRightForceKg,
                  isActive: true,
                ),
              ],
              const SizedBox(height: 24),
              Expanded(child: _buildProgressionChart()),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () =>
                          Navigator.of(context).pop(currentExercise),
                      child: const Text('Close'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: canSave ? _saveMaxLift : null,
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
