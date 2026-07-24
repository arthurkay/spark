import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../../shared/widgets/sheet_keyboard_padding.dart';
import '../models/luse_stock.dart';
import '../providers/luse_provider.dart';
import 'luse_chart.dart';

class StockDetailSheet extends ConsumerWidget {
  const StockDetailSheet({super.key, required this.stock});

  final LuseStock stock;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final watchlist = ref.watch(luseWatchlistProvider);
    final isWatched = watchlist.contains(stock.symbol);
    final historyAsync = ref.watch(luseHistoryProvider);
    final fundamentalsAsync = ref.watch(luseFundamentalsProvider);

    return SheetKeyboardPadding(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(stock.symbol).h4,
                        Text(stock.name).muted.small,
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => ref
                        .read(luseWatchlistProvider.notifier)
                        .toggle(stock.symbol),
                    child: Icon(
                      isWatched ? LucideIcons.star : LucideIcons.star,
                      size: 20,
                      color: isWatched
                          ? const Color(0xFFFBBF24)
                          : Theme.of(context).colorScheme.mutedForeground,
                    ),
                  ),
                ],
              ),
              const Gap(16),

              // Price row
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('K${stock.lastPrice.toStringAsFixed(2)}').h3,
                  const Gap(12),
                  Text(
                    '${stock.change >= 0 ? '+' : ''}${stock.change.toStringAsFixed(2)} (${stock.changePercent >= 0 ? '+' : ''}${stock.changePercent.toStringAsFixed(2)}%)',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: stock.isGainer
                          ? const Color(0xFF34D399)
                          : stock.isLoser
                              ? const Color(0xFFF87171)
                              : Theme.of(context).colorScheme.mutedForeground,
                    ),
                  ),
                ],
              ),
              const Gap(20),

              // Chart
              historyAsync.when(
                loading: () => const SizedBox(
                  height: 220,
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (_, __) => const SizedBox(
                  height: 220,
                  child: Center(child: Text('Failed to load history')),
                ),
                data: (history) {
                  final dataPoints = history
                      .map((snapshot) {
                        final stockData = snapshot.stocks
                            .where((s) => s.symbol == stock.symbol)
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

                  return LuseChart(
                    series: [
                      ChartSeries(
                        label: stock.symbol,
                        color: const Color(0xFF38BDF8),
                        data: dataPoints,
                      ),
                    ],
                    showLegend: false,
                    height: 220,
                  );
                },
              ),
              const Gap(16),

              // Stats row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _StatItem(
                    label: 'Open',
                    value: 'K${stock.lastPrice.toStringAsFixed(2)}',
                  ),
                  _StatItem(
                    label: 'Change',
                    value:
                        '${stock.change >= 0 ? '+' : ''}${stock.change.toStringAsFixed(2)}',
                  ),
                  _StatItem(
                    label: 'Volume',
                    value: '--',
                  ),
                ],
              ),

              // Fundamentals section
              fundamentalsAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                data: (fundamentals) {
                  final fund = fundamentals
                      .where((f) => f.symbol == stock.symbol)
                      .firstOrNull;
                  if (fund == null) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.muted,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('Fundamentals').small.semiBold,
                          const Gap(10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _StatItem(
                                label: 'P/E',
                                value: fund.peRatio != null
                                    ? fund.peRatio!.toStringAsFixed(1)
                                    : '--',
                              ),
                              _StatItem(
                                label: 'EPS',
                                value: fund.eps != null
                                    ? 'K${fund.eps!.toStringAsFixed(2)}'
                                    : '--',
                              ),
                              _StatItem(
                                label: 'Div Yield',
                                value: fund.dividendYield != null
                                    ? '${fund.dividendYield!.toStringAsFixed(1)}%'
                                    : '--',
                              ),
                              if (fund.marketCap != null)
                                _StatItem(
                                  label: 'Market Cap',
                                  value: _formatMarketCap(fund.marketCap!),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatMarketCap(double value) {
    if (value >= 1e9) return '${(value / 1e9).toStringAsFixed(1)}B';
    if (value >= 1e6) return '${(value / 1e6).toStringAsFixed(1)}M';
    if (value >= 1e3) return '${(value / 1e3).toStringAsFixed(1)}K';
    return value.toStringAsFixed(0);
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label).xSmall.muted,
        const Gap(2),
        Text(value).small.semiBold,
      ],
    );
  }
}
