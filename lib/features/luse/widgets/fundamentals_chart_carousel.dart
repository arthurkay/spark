import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/widgets.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' hide Column, Row, Expanded;

import '../models/luse_fundamentals.dart';

class FundamentalsChartCarousel extends StatefulWidget {
  const FundamentalsChartCarousel({super.key, required this.fundamentals});

  final List<LuseFundamentals> fundamentals;

  @override
  State<FundamentalsChartCarousel> createState() =>
      _FundamentalsChartCarouselState();
}

class _FundamentalsChartCarouselState extends State<FundamentalsChartCarousel> {
  final _controller = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final charts = [
      _SectorChart(fundamentals: widget.fundamentals),
      _ChangeChart(fundamentals: widget.fundamentals),
      _YtdChart(fundamentals: widget.fundamentals),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 200,
          child: PageView(
            controller: _controller,
            onPageChanged: (index) => setState(() => _currentPage = index),
            children: charts,
          ),
        ),
        const Gap(8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(charts.length, (index) {
            final isActive = index == _currentPage;
            return Container(
              width: isActive ? 16 : 6,
              height: 6,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: isActive
                    ? const Color(0xFF38BDF8)
                    : const Color(0xFF3F3F46),
                borderRadius: BorderRadius.circular(3),
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _SectorChart extends StatelessWidget {
  const _SectorChart({required this.fundamentals});

  final List<LuseFundamentals> fundamentals;

  @override
  Widget build(BuildContext context) {
    final sectorMap = <String, int>{};
    for (final f in fundamentals) {
      final sector = f.sector ?? 'Unknown';
      sectorMap[sector] = (sectorMap[sector] ?? 0) + 1;
    }

    if (sectorMap.isEmpty) {
      return _ChartEmpty(label: 'Sector');
    }

    final sectors = sectorMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final colors = [
      const Color(0xFF38BDF8),
      const Color(0xFF34D399),
      const Color(0xFFFBBF24),
      const Color(0xFFF87171),
      const Color(0xFFA78BFA),
      const Color(0xFFF472B6),
      const Color(0xFF2DD4BF),
      const Color(0xFFFB923C),
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Sector Breakdown').small.semiBold,
          const Gap(8),
          Expanded(
            child: PieChart(
              PieChartData(
                sections: sectors.asMap().entries.map((entry) {
                  final index = entry.key;
                  final sector = entry.value;
                  return PieChartSectionData(
                    value: sector.value.toDouble(),
                    color: colors[index % colors.length],
                    radius: 70,
                    title: '',
                  );
                }).toList(),
                sectionsSpace: 2,
                centerSpaceRadius: 24,
              ),
            ),
          ),
          const Gap(6),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: sectors.asMap().entries.map((entry) {
              final index = entry.key;
              final sector = entry.value;
              final color = colors[index % colors.length];
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const Gap(4),
                  Text(
                    '${sector.key} (${sector.value})',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _ChangeChart extends StatelessWidget {
  const _ChangeChart({required this.fundamentals});

  final List<LuseFundamentals> fundamentals;

  @override
  Widget build(BuildContext context) {
    final withChange = fundamentals
        .where((f) => f.changePercent != null && f.changePercent != 0)
        .toList()
      ..sort(
          (a, b) => b.changePercent!.abs().compareTo(a.changePercent!.abs()));

    if (withChange.isEmpty) {
      return _ChartEmpty(label: 'Daily Change');
    }

    final display = withChange.take(10).toList();
    final maxAbs = display
        .map((f) => f.changePercent!.abs())
        .reduce((a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Daily Change').small.semiBold,
          const Gap(8),
          Expanded(
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxAbs * 1.2,
                minY: 0,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: maxAbs > 0 ? maxAbs / 4 : 1,
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
                      reservedSize: 20,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx >= 0 && idx < display.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              display[idx].symbol,
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
                barGroups: display.asMap().entries.map((entry) {
                  final index = entry.key;
                  final fund = entry.value;
                  final color = fund.changePercent! > 0
                      ? const Color(0xFF34D399)
                      : const Color(0xFFF87171);
                  return BarChartGroupData(
                    x: index,
                    barRods: [
                      BarChartRodData(
                        toY: fund.changePercent!.abs(),
                        color: color,
                        width: 12,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(3),
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

class _YtdChart extends StatelessWidget {
  const _YtdChart({required this.fundamentals});

  final List<LuseFundamentals> fundamentals;

  @override
  Widget build(BuildContext context) {
    final withYtd = fundamentals.where((f) => f.changePercent != null).toList()
      ..sort(
          (a, b) => b.changePercent!.abs().compareTo(a.changePercent!.abs()));

    if (withYtd.isEmpty) {
      return _ChartEmpty(label: 'Performance');
    }

    final display = withYtd.take(10).toList();
    final maxAbs = display
        .map((f) => f.changePercent!.abs())
        .reduce((a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Top Movers').small.semiBold,
          const Gap(8),
          Expanded(
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxAbs * 1.2,
                minY: 0,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: maxAbs > 0 ? maxAbs / 4 : 1,
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
                      reservedSize: 20,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx >= 0 && idx < display.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              display[idx].symbol,
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
                barGroups: display.asMap().entries.map((entry) {
                  final index = entry.key;
                  final fund = entry.value;
                  final color = fund.changePercent! > 0
                      ? const Color(0xFF34D399)
                      : const Color(0xFFF87171);
                  return BarChartGroupData(
                    x: index,
                    barRods: [
                      BarChartRodData(
                        toY: fund.changePercent!.abs(),
                        color: color,
                        width: 12,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(3),
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

class _ChartEmpty extends StatelessWidget {
  const _ChartEmpty({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label).small.semiBold,
          const Gap(8),
          Expanded(
            child: Center(
              child: Text('No data').muted.xSmall,
            ),
          ),
        ],
      ),
    );
  }
}
