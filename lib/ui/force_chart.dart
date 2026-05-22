import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class ForceChart extends StatelessWidget {
  final List<FlSpot> dataPoints;
  final int chartMaxForce;
  final int targetMinForce;
  final int targetMaxForce;
  final bool showTargetArea;

  const ForceChart({
    super.key,
    required this.dataPoints,
    required this.chartMaxForce,
    required this.targetMinForce,
    required this.targetMaxForce,
    this.showTargetArea = true,
  });

  @override
  Widget build(BuildContext context) {
    const double lowerYPadding = 2;

    return Stack(
      children: [
        LineChart(
          LineChartData(
            minY: -lowerYPadding,
            maxY: chartMaxForce.toDouble(),
            clipData: FlClipData.all(),
            borderData: FlBorderData(show: false),
            rangeAnnotations: RangeAnnotations(
              horizontalRangeAnnotations: showTargetArea
                  ? [
                      HorizontalRangeAnnotation(
                        y1: targetMinForce.toDouble(),
                        y2: targetMaxForce.toDouble(),
                        color: Colors.green.withValues(alpha: 0.20),
                      ),
                    ]
                  : const [],
            ),
            lineBarsData: [
              LineChartBarData(
                spots: dataPoints,
                isCurved: true,
                curveSmoothness: 0.35,
                preventCurveOverShooting: true,
                color: Theme.of(context).colorScheme.primary,
                barWidth: 4,
                dotData: FlDotData(show: false),
              ),
            ],
            titlesData: FlTitlesData(
              leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: false,
                  reservedSize: 42,
                  getTitlesWidget: (value, meta) {
                    if (value == chartMaxForce.toDouble()) {
                      return Text(value.toInt().toString());
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ),
            gridData: FlGridData(show: false),
            lineTouchData: LineTouchData(enabled: false),
          ),
          duration: const Duration(milliseconds: 180),
        ),
        if (showTargetArea)
          Positioned(
            top: 8,
            right: 8,
            child: Text(
              'Target: $targetMinForce-$targetMaxForce kg',
              style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w600),
            ),
          ),
      ],
    );
  }
}