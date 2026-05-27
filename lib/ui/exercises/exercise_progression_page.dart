import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:pullcrane/domain/models/exercise.dart';

enum TimeFilter { d, w, m, y, all }

class ExerciseProgressionPage extends StatefulWidget {
  const ExerciseProgressionPage({super.key, required this.exercise});

  final Exercise exercise;

  @override
  State<ExerciseProgressionPage> createState() => _ExerciseProgressionPageState();
}

class _ExerciseProgressionPageState extends State<ExerciseProgressionPage> {
  TimeFilter selectedFilter = TimeFilter.all;

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

  List<MaxLiftRecord> _getFilteredHistory() {
    if (selectedFilter == TimeFilter.all) return widget.exercise.maxLiftHistory;
    
    final DateTime now = DateTime.now();
    DateTime threshold;
    switch (selectedFilter) {
      case TimeFilter.d:
        threshold = now.subtract(const Duration(days: 1));
        break;
      case TimeFilter.w:
        threshold = now.subtract(const Duration(days: 7));
        break;
      case TimeFilter.m:
        threshold = now.subtract(const Duration(days: 30));
        break;
      case TimeFilter.y:
        threshold = now.subtract(const Duration(days: 365));
        break;
      case TimeFilter.all:
        threshold = DateTime.fromMillisecondsSinceEpoch(0);
        break;
    }
    
    return widget.exercise.maxLiftHistory.where((r) => r.date.isAfter(threshold)).toList();
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

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.exercise.name} Progression'),
      ),
      body: Column(
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
          Expanded(
            child: filteredData.isEmpty
                ? const Center(child: Text('No history available.'))
                : ListView.builder(
                    itemCount: filteredData.length,
                    // Show newest first
                    itemBuilder: (context, index) {
                      final record = filteredData[filteredData.length - 1 - index];
                      final String weightText = widget.exercise.isSideSwitching
                          ? 'L ${record.leftKg}kg • R ${record.rightKg}kg'
                          : '${record.leftKg}kg';

                      return ListTile(
                        title: Text(weightText),
                        subtitle: Text(_formatDate(record.date)),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
