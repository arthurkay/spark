import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/widgets.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' hide Column, Row, Expanded;

class DividendHistoryChart extends StatelessWidget {
  const DividendHistoryChart({super.key, required this.dividends});

  final List<DividendEntry> dividends;

  @override
  Widget build(BuildContext context) {
    if (dividends.isEmpty) {
      return Container(
        height: 120,
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text('No dividend history').muted.xSmall,
        ),
      );
    }

    final sorted = List<DividendEntry>.from(dividends)
      ..sort((a, b) => a.date.compareTo(b.date));
    final maxY = sorted.map((d) => d.amount).reduce((a, b) => a > b ? a : b);

    return Container(
      height: 140,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Dividend History').small.semiBold,
          const Gap(8),
          Expanded(
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxY * 1.2,
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => const Color(0xFF27272A),
                    tooltipRoundedRadius: 6,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final entry = sorted[group.x.toInt()];
                      return BarTooltipItem(
                        'K${rod.toY.toStringAsFixed(2)}\n${entry.label}',
                        const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      );
                    },
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: maxY > 0 ? maxY / 3 : 1,
                  getDrawingHorizontalLine: (value) {
                    return FlLine(
                      color: const Color(0xFF27272A),
                      strokeWidth: 0.5,
                    );
                  },
                ),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx >= 0 && idx < sorted.length) {
                          final d = sorted[idx].date;
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              '${d.month}/${d.day.toString().padLeft(2, '0')}',
                              style: const TextStyle(
                                fontSize: 8,
                                color: Color(0xFFA1A1AA),
                              ),
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                barGroups: sorted.asMap().entries.map((entry) {
                  final index = entry.key;
                  final dividend = entry.value;
                  return BarChartGroupData(
                    x: index,
                    barRods: [
                      BarChartRodData(
                        toY: dividend.amount,
                        color: const Color(0xFF38BDF8),
                        width: 16,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DividendEntry {
  const DividendEntry({
    required this.date,
    required this.amount,
    this.label = '',
  });

  final DateTime date;
  final double amount;
  final String label;
}
