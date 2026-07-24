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
      _PeRatioChart(fundamentals: widget.fundamentals),
      _DividendYieldChart(fundamentals: widget.fundamentals),
      _MarketCapChart(fundamentals: widget.fundamentals),
      _SectorChart(fundamentals: widget.fundamentals),
      _PeVsEpsChart(fundamentals: widget.fundamentals),
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

class _PeRatioChart extends StatelessWidget {
  const _PeRatioChart({required this.fundamentals});

  final List<LuseFundamentals> fundamentals;

  @override
  Widget build(BuildContext context) {
    final valid = fundamentals
        .where((f) => f.peRatio != null && f.peRatio! > 0)
        .toList()
      ..sort((a, b) => b.peRatio!.compareTo(a.peRatio!));

    if (valid.isEmpty) {
      return _ChartEmpty(label: 'P/E Ratio');
    }

    final display = valid.take(10).toList();
    final maxY = display.map((f) => f.peRatio!).reduce((a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('P/E Ratio').small.semiBold,
          const Gap(8),
          Expanded(
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxY * 1.1,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: maxY / 4,
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
                  final color = fund.peRatio! > 20
                      ? const Color(0xFFF87171)
                      : fund.peRatio! > 10
                          ? const Color(0xFFFBBF24)
                          : const Color(0xFF34D399);
                  return BarChartGroupData(
                    x: index,
                    barRods: [
                      BarChartRodData(
                        toY: fund.peRatio!,
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

class _DividendYieldChart extends StatelessWidget {
  const _DividendYieldChart({required this.fundamentals});

  final List<LuseFundamentals> fundamentals;

  @override
  Widget build(BuildContext context) {
    final valid = fundamentals
        .where((f) => f.dividendYield != null && f.dividendYield! > 0)
        .toList()
      ..sort((a, b) => b.dividendYield!.compareTo(a.dividendYield!));

    if (valid.isEmpty) {
      return _ChartEmpty(label: 'Dividend Yield');
    }

    final display = valid.take(10).toList();
    final maxY =
        display.map((f) => f.dividendYield!).reduce((a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Dividend Yield').small.semiBold,
          const Gap(8),
          Expanded(
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxY * 1.1,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: maxY / 4,
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
                  final color = fund.dividendYield! > 5
                      ? const Color(0xFF34D399)
                      : fund.dividendYield! > 2
                          ? const Color(0xFFFBBF24)
                          : const Color(0xFFA1A1AA);
                  return BarChartGroupData(
                    x: index,
                    barRods: [
                      BarChartRodData(
                        toY: fund.dividendYield!,
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

class _MarketCapChart extends StatelessWidget {
  const _MarketCapChart({required this.fundamentals});

  final List<LuseFundamentals> fundamentals;

  @override
  Widget build(BuildContext context) {
    final valid = fundamentals
        .where((f) => f.marketCap != null && f.marketCap! > 0)
        .toList()
      ..sort((a, b) => b.marketCap!.compareTo(a.marketCap!));

    if (valid.isEmpty) {
      return _ChartEmpty(label: 'Market Cap');
    }

    final display = valid.take(8).toList();
    final total = display.map((f) => f.marketCap!).reduce((a, b) => a + b);
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
          const Text('Market Cap').small.semiBold,
          const Gap(8),
          Expanded(
            child: PieChart(
              PieChartData(
                sections: display.asMap().entries.map((entry) {
                  final index = entry.key;
                  final fund = entry.value;
                  final pct = (fund.marketCap! / total) * 100;
                  return PieChartSectionData(
                    value: fund.marketCap,
                    title: pct > 5 ? '${pct.toStringAsFixed(0)}%' : '',
                    color: colors[index % colors.length],
                    radius: 70,
                    titleStyle: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  );
                }).toList(),
                sectionsSpace: 2,
                centerSpaceRadius: 24,
              ),
            ),
          ),
        ],
      ),
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
                    title: '${sector.value}',
                    color: colors[index % colors.length],
                    radius: 70,
                    titleStyle: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  );
                }).toList(),
                sectionsSpace: 2,
                centerSpaceRadius: 24,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PeVsEpsChart extends StatelessWidget {
  const _PeVsEpsChart({required this.fundamentals});

  final List<LuseFundamentals> fundamentals;

  @override
  Widget build(BuildContext context) {
    final valid = fundamentals
        .where((f) =>
            f.peRatio != null && f.peRatio! > 0 && f.eps != null && f.eps! > 0)
        .toList();

    if (valid.isEmpty) {
      return _ChartEmpty(label: 'P/E vs EPS');
    }

    final peValues = valid.map((f) => f.peRatio!).toList();
    final epsValues = valid.map((f) => f.eps!).toList();
    final minPe = peValues.reduce((a, b) => a < b ? a : b);
    final maxPe = peValues.reduce((a, b) => a > b ? a : b);
    final minEps = epsValues.reduce((a, b) => a < b ? a : b);
    final maxEps = epsValues.reduce((a, b) => a > b ? a : b);
    final peRange = maxPe - minPe;
    final epsRange = maxEps - minEps;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text('P/E vs EPS').small.semiBold,
              const Spacer(),
              Text('P/E (x)  EPS (K)').xSmall.muted,
            ],
          ),
          const Gap(8),
          Expanded(
            child: ScatterChart(
              ScatterChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: true,
                  drawHorizontalLine: true,
                  horizontalInterval: epsRange > 0 ? epsRange / 4 : 1,
                  verticalInterval: peRange > 0 ? peRange / 4 : 1,
                  getDrawingHorizontalLine: (value) {
                    return FlLine(
                      color: const Color(0xFF27272A),
                      strokeWidth: 0.5,
                    );
                  },
                  getDrawingVerticalLine: (value) {
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
                      reservedSize: 40,
                      interval: epsRange > 0 ? epsRange / 4 : 1,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          value.toStringAsFixed(1),
                          style: const TextStyle(
                            fontSize: 8,
                            color: Color(0xFFA1A1AA),
                          ),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 20,
                      interval: peRange > 0 ? peRange / 4 : 1,
                      getTitlesWidget: (value, meta) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            value.toStringAsFixed(0),
                            style: const TextStyle(
                              fontSize: 8,
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
                scatterSpots: valid.map((fund) {
                  return ScatterSpot(
                    fund.peRatio!,
                    fund.eps!,
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
