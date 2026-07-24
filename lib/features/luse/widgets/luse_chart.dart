import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/widgets.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' hide Column, Row;

class ChartSeries {
  const ChartSeries({
    required this.label,
    required this.color,
    required this.data,
  });

  final String label;
  final Color color;
  final List<ChartPoint> data;
}

class ChartPoint {
  const ChartPoint({required this.date, required this.value});

  final DateTime date;
  final double value;
}

class LuseChart extends StatelessWidget {
  const LuseChart({
    super.key,
    required this.series,
    this.height = 220,
    this.showLegend = true,
  });

  final List<ChartSeries> series;
  final double height;
  final bool showLegend;

  @override
  Widget build(BuildContext context) {
    if (series.isEmpty || series.every((s) => s.data.isEmpty)) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text('No data available').muted,
        ),
      );
    }

    final allPoints = series.expand((s) => s.data).toList();
    final allValues = allPoints.map((p) => p.value).toList();
    final minY = allValues.reduce((a, b) => a < b ? a : b);
    final maxY = allValues.reduce((a, b) => a > b ? a : b);
    final padding = (maxY - minY) * 0.1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showLegend && series.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(
              spacing: 12,
              runSpacing: 4,
              children: series.map((s) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: s.color,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const Gap(4),
                    Text(s.label).xSmall,
                  ],
                );
              }).toList(),
            ),
          ),
        SizedBox(
          height: height,
          child: Padding(
            padding: const EdgeInsets.only(right: 12, top: 8, bottom: 4),
            child: LineChart(
              LineChartData(
                minY: minY - padding,
                maxY: maxY + padding,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval:
                      _calcInterval(minY - padding, maxY + padding, 4),
                  getDrawingHorizontalLine: (value) {
                    return FlLine(
                      color: const Color(0xFF27272A),
                      strokeWidth: 0.5,
                    );
                  },
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 50,
                      interval:
                          _calcInterval(minY - padding, maxY + padding, 4),
                      getTitlesWidget: (value, meta) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Text(
                            'K${value.toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontSize: 9,
                              color: Color(0xFFA1A1AA),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      interval: _calcDateInterval(allPoints),
                      getTitlesWidget: (value, meta) {
                        final date = DateTime.fromMillisecondsSinceEpoch(
                          value.toInt(),
                        );
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '${date.month}/${date.day}',
                            style: const TextStyle(
                              fontSize: 9,
                              color: Color(0xFFA1A1AA),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: series.map((s) {
                  final spots = s.data
                      .map((p) => FlSpot(
                            p.date.millisecondsSinceEpoch.toDouble(),
                            p.value,
                          ))
                      .toList();
                  return LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    preventCurveOverShooting: true,
                    color: s.color,
                    barWidth: 2,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      show: spots.length <= 15,
                      getDotPainter: (spot, percent, bar, index) {
                        return FlDotCirclePainter(
                          radius: 3,
                          color: s.color,
                          strokeColor: Colors.white,
                          strokeWidth: 1,
                        );
                      },
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          s.color.withAlpha(40),
                          s.color.withAlpha(5),
                        ],
                      ),
                    ),
                  );
                }).toList(),
                lineTouchData: LineTouchData(
                  handleBuiltInTouches: true,
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => const Color(0xFF27272A),
                    tooltipRoundedRadius: 8,
                    getTooltipItems: (spots) {
                      return spots.map((spot) {
                        final seriesIndex = series.indexWhere(
                          (s) => s.data.any(
                            (p) =>
                                p.date.millisecondsSinceEpoch.toDouble() ==
                                spot.x,
                          ),
                        );
                        final label =
                            seriesIndex >= 0 ? series[seriesIndex].label : '';
                        return LineTooltipItem(
                          '$label\nK${spot.y.toStringAsFixed(2)}',
                          TextStyle(
                            color: seriesIndex >= 0
                                ? series[seriesIndex].color
                                : Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        );
                      }).toList();
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  double _calcInterval(double min, double max, int targetTicks) {
    final range = max - min;
    if (range <= 0) return 1;
    final raw = range / targetTicks;
    final magnitude = (raw / 1000).floorToDouble();
    if (magnitude >= 1) return magnitude * 1000;
    final mag10 = (raw / 100).floorToDouble();
    if (mag10 >= 1) return mag10 * 100;
    final mag1 = (raw / 10).floorToDouble();
    if (mag1 >= 1) return mag1 * 10;
    final mag01 = (raw).floorToDouble();
    if (mag01 >= 1) return mag01;
    return raw;
  }

  double _calcDateInterval(List<ChartPoint> allPoints) {
    if (allPoints.length < 2) return 86400000;
    final first = allPoints.first.date.millisecondsSinceEpoch;
    final last = allPoints.last.date.millisecondsSinceEpoch;
    final range = last - first;
    return range / 5;
  }
}
