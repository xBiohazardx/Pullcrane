import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:pullcrane/data/app_stores.dart';
import 'package:pullcrane/domain/models/exercise.dart';
import 'package:pullcrane/domain/models/set_log.dart';

enum TimeFilter { d, w, m, y, all }

class ExerciseProgressionPage extends StatefulWidget {
  const ExerciseProgressionPage({super.key, required this.exercise});

  final Exercise exercise;

  @override
  State<ExerciseProgressionPage> createState() => _ExerciseProgressionPageState();
}

class _ExerciseProgressionPageState extends State<ExerciseProgressionPage> {
  TimeFilter selectedFilter = TimeFilter.all;
  List<SetLog> trainingLogs = <SetLog>[];
  bool logsLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTrainingLogs();
  }

  Future<void> _loadTrainingLogs() async {
    final List<SetLog> logs =
        await AppStores.sessions.listLogsForExercise(widget.exercise.id);
    if (!mounted) {
      return;
    }
    setState(() {
      trainingLogs = logs;
      logsLoading = false;
    });
  }

  String _formatDate(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  String _formatShortDate(DateTime d, TimeFilter filter) {
    if (filter == TimeFilter.d) {
      return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    } else if (filter == TimeFilter.y || filter == TimeFilter.all) {
      return '${d.year}-${d.month.toString().padLeft(2, '0')}';
    }
    return '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  DateTime get _filterThreshold {
    final DateTime now = DateTime.now();
    switch (selectedFilter) {
      case TimeFilter.d:
        return now.subtract(const Duration(days: 1));
      case TimeFilter.w:
        return now.subtract(const Duration(days: 7));
      case TimeFilter.m:
        return now.subtract(const Duration(days: 30));
      case TimeFilter.y:
        return now.subtract(const Duration(days: 365));
      case TimeFilter.all:
        return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  List<MaxLiftRecord> _getFilteredHistory() {
    final DateTime threshold = _filterThreshold;
    if (selectedFilter == TimeFilter.all) return widget.exercise.maxLiftHistory;
    return widget.exercise.maxLiftHistory.where((r) => r.date.isAfter(threshold)).toList();
  }

  List<SetLog> get _filteredTrainingLogs {
    final DateTime threshold = _filterThreshold;
    return trainingLogs.where((log) {
      final DateTime? date = log.sessionStartedAt;
      return date == null || date.isAfter(threshold);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final List<MaxLiftRecord> filteredData = _getFilteredHistory();

    final List<FlSpot> leftSpots = [];
    final List<FlSpot> rightSpots = [];
    final List<FlSpot> singleSpots = [];

    double minX = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = 10;

    for (final record in filteredData) {
      final double x = record.date.millisecondsSinceEpoch.toDouble();
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;

      if (widget.exercise.isSideSwitching) {
        leftSpots.add(FlSpot(x, record.leftKg.toDouble()));
        rightSpots.add(FlSpot(x, record.rightKg.toDouble()));
        if (record.leftKg > maxY) maxY = record.leftKg.toDouble();
        if (record.rightKg > maxY) maxY = record.rightKg.toDouble();
      } else {
        singleSpots.add(FlSpot(x, record.leftKg.toDouble()));
        if (record.leftKg > maxY) maxY = record.leftKg.toDouble();
      }
    }

    // Add some padding to Y axis
    maxY = maxY + 10;

    // Fix minX and maxX if single item or empty
    if (minX == double.infinity) {
      minX = 0;
      maxX = 1;
    } else if (minX == maxX) {
      minX -= 3600000; // -1 hour
      maxX += 3600000; // +1 hour
    }

    final Widget chartWidget = filteredData.isEmpty
        ? const Center(child: Text('No data for selected period.'))
        : Padding(
            padding: const EdgeInsets.all(16.0),
            child: LineChart(
              LineChartData(
                minX: minX,
                maxX: maxX,
                minY: 0,
                maxY: maxY,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                ),
                titlesData: FlTitlesData(
                  topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      getTitlesWidget: (value, meta) {
                        // Skip min and max bounds for cleaner look
                        if (value == minX || value == maxX) return const SizedBox.shrink();
                        
                        final date = DateTime.fromMillisecondsSinceEpoch(value.toInt());
                        return Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            _formatShortDate(date, selectedFilter),
                            style: const TextStyle(fontSize: 10),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: widget.exercise.isSideSwitching
                    ? [
                        LineChartBarData(
                          spots: leftSpots,
                          isCurved: true,
                          color: Colors.blue,
                          barWidth: 3,
                          dotData: FlDotData(show: true),
                        ),
                        LineChartBarData(
                          spots: rightSpots,
                          isCurved: true,
                          color: Colors.red,
                          barWidth: 3,
                          dotData: FlDotData(show: true),
                        ),
                      ]
                    : [
                        LineChartBarData(
                          spots: singleSpots,
                          isCurved: true,
                          color: Colors.green,
                          barWidth: 3,
                          dotData: FlDotData(show: true),
                        ),
                      ],
              ),
            ),
          );

    final List<SetLog> filteredLogs = _filteredTrainingLogs;
    final int sessionCount = filteredLogs
        .map((log) => log.sessionStartedAt?.toIso8601String() ?? '')
        .toSet()
        .length;
    final int timeUnderTensionSeconds = filteredLogs.fold<int>(
      0,
      (sum, log) => sum + log.actualDurationSeconds,
    );
    final int bestPeakKg = filteredLogs.fold<int>(
      0,
      (best, log) => max(best, log.peakForceKg),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.exercise.name} Progression'),
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: SegmentedButton<TimeFilter>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: TimeFilter.d, label: FittedBox(fit: BoxFit.scaleDown, child: Text('D'))),
                ButtonSegment(value: TimeFilter.w, label: FittedBox(fit: BoxFit.scaleDown, child: Text('W'))),
                ButtonSegment(value: TimeFilter.m, label: FittedBox(fit: BoxFit.scaleDown, child: Text('M'))),
                ButtonSegment(value: TimeFilter.y, label: FittedBox(fit: BoxFit.scaleDown, child: Text('Y'))),
                ButtonSegment(value: TimeFilter.all, label: FittedBox(fit: BoxFit.scaleDown, child: Text('All'))),
              ],
              selected: <TimeFilter>{selectedFilter},
              onSelectionChanged: (Set<TimeFilter> newSelection) {
                setState(() {
                  selectedFilter = newSelection.first;
                });
              },
            ),
          ),
          if (widget.exercise.isSideSwitching)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(width: 12, height: 12, color: Colors.blue),
                  const SizedBox(width: 4),
                  const Text('Left'),
                  const SizedBox(width: 16),
                  Container(width: 12, height: 12, color: Colors.red),
                  const SizedBox(width: 4),
                  const Text('Right'),
                ],
              ),
            ),
          SizedBox(
            height: 250,
            child: chartWidget,
          ),
          const Divider(),
          if (!logsLoading && trainingLogs.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                'Training summary',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _StatChip(
                    label: 'Sessions',
                    value: '$sessionCount',
                  ),
                  _StatChip(
                    label: 'Time under tension',
                    value: _formatDurationSeconds(timeUnderTensionSeconds),
                  ),
                  _StatChip(
                    label: 'Best peak',
                    value: '${bestPeakKg}kg',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            ...filteredLogs.take(10).map(
                  (log) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.fitness_center, size: 20),
                    title: Text(
                      'Set ${log.setNumber}'
                      '${log.hand != null ? ' (${log.hand == ExerciseHand.left ? 'L' : 'R'})' : ''} — '
                      'peak ${log.peakForceKg}kg / target ${log.targetForceKg}kg',
                    ),
                    subtitle: Text(
                      '${log.sessionStartedAt == null ? '' : '${_formatDate(log.sessionStartedAt!)} • '}'
                      '${log.plannedDurationSeconds > 0 ? '${log.actualDurationSeconds}/${log.plannedDurationSeconds}s' : '${log.plannedReps} reps'}',
                    ),
                  ),
                ),
            const Divider(),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Max lift measurements',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          if (filteredData.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: Text('No history available.')),
            )
          else
            ...List.generate(filteredData.length, (index) {
              // Show newest first
              final record = filteredData[filteredData.length - 1 - index];
              final String weightText = widget.exercise.isSideSwitching
                  ? 'L ${record.leftKg}kg • R ${record.rightKg}kg'
                  : '${record.leftKg}kg';

              return ListTile(
                title: Text(weightText),
                subtitle: Text(_formatDate(record.date)),
              );
            }),
        ],
      ),
    );
  }

  String _formatDurationSeconds(int seconds) {
    final int minutes = seconds ~/ 60;
    final int remainder = seconds % 60;
    if (minutes == 0) {
      return '${remainder}s';
    }
    return '${minutes}m ${remainder}s';
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: Theme.of(context).textTheme.titleMedium),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}
