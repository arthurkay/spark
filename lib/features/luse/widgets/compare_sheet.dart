import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../models/luse_stock.dart';
import '../providers/luse_provider.dart';
import 'luse_chart.dart';

class CompareSheet extends ConsumerWidget {
  const CompareSheet({super.key, required this.stocks});

  final List<LuseStock> stocks;

  static const _colors = [
    Color(0xFF38BDF8), // cyan
    Color(0xFFA78BFA), // violet
    Color(0xFF34D399), // emerald
    Color(0xFFFB923C), // orange
    Color(0xFFF472B6), // pink
    Color(0xFFFBBF24), // amber
    Color(0xFF60A5FA), // blue
    Color(0xFFF87171), // red
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(luseHistoryProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(LucideIcons.gitCompareArrows, size: 18),
                const Gap(8),
                Expanded(
                  child: Text('Compare ${stocks.length} stocks').h4,
                ),
              ],
            ),
            const Gap(4),
            Text(
              stocks.map((s) => s.symbol).join(' vs '),
            ).muted.small,
            const Gap(16),

            // Current prices
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: stocks.asMap().entries.map((entry) {
                  final i = entry.key;
                  final s = entry.value;
                  final color = _colors[i % _colors.length];
                  return Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: color,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const Gap(4),
                            Text(s.symbol).small.semiBold,
                          ],
                        ),
                        Text('K${s.lastPrice.toStringAsFixed(2)}').xSmall.muted,
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
            const Gap(16),

            // Chart
            historyAsync.when(
              loading: () => const SizedBox(
                height: 260,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, __) => const SizedBox(
                height: 260,
                child: Center(child: Text('Failed to load history')),
              ),
              data: (history) {
                final seriesList = stocks.asMap().entries.map((entry) {
                  final i = entry.key;
                  final s = entry.value;
                  final color = _colors[i % _colors.length];

                  final dataPoints = history
                      .map((snapshot) {
                        final stockData = snapshot.stocks
                            .where((st) => st.symbol == s.symbol)
                            .firstOrNull;
                        if (stockData == null) return null;
                        return ChartPoint(
                          date: snapshot.date,
                          value: stockData.lastPrice,
                        );
                      })
                      .whereType<ChartPoint>()
                      .toList()
                    ..sort((a, b) => a.date.compareTo(b.date));

                  return ChartSeries(
                    label: s.symbol,
                    color: color,
                    data: dataPoints,
                  );
                }).toList();

                return LuseChart(
                  series: seriesList,
                  showLegend: true,
                  height: 260,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
