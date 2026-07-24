import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' hide Column, Row, Expanded;

import '../models/luse_fundamentals.dart';
import '../providers/luse_provider.dart';

class FundamentalsCard extends ConsumerWidget {
  const FundamentalsCard({
    super.key,
    required this.fundamental,
    this.onTap,
  });

  final LuseFundamentals fundamental;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final watchlist = ref.watch(luseWatchlistProvider);
    final isWatched = watchlist.contains(fundamental.symbol);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.muted,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).colorScheme.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(fundamental.symbol).small.semiBold,
                          if (isWatched) ...[
                            const Gap(4),
                            const Icon(
                              LucideIcons.star,
                              size: 10,
                              color: Color(0xFFFBBF24),
                            ),
                          ],
                        ],
                      ),
                      const Gap(2),
                      Text(fundamental.name).xSmall.muted,
                    ],
                  ),
                ),
                if (fundamental.lastPrice != null)
                  Text('K${fundamental.lastPrice!.toStringAsFixed(2)}')
                      .small
                      .semiBold,
              ],
            ),
            const Gap(10),
            Row(
              children: [
                _Metric(
                  label: 'P/E',
                  value: fundamental.peRatio != null
                      ? fundamental.peRatio!.toStringAsFixed(1)
                      : '--',
                  color: _peColor(fundamental.peRatio),
                ),
                const Gap(8),
                _Metric(
                  label: 'EPS',
                  value: fundamental.eps != null
                      ? 'K${fundamental.eps!.toStringAsFixed(2)}'
                      : '--',
                  color: _epsColor(fundamental.eps),
                ),
                const Gap(8),
                _Metric(
                  label: 'Div Yield',
                  value: fundamental.dividendYield != null
                      ? '${fundamental.dividendYield!.toStringAsFixed(1)}%'
                      : '--',
                  color: _divColor(fundamental.dividendYield),
                ),
                const Spacer(),
                if (fundamental.marketCap != null)
                  _Metric(
                    label: 'Market Cap',
                    value: _formatMarketCap(fundamental.marketCap!),
                    color: Theme.of(context).colorScheme.mutedForeground,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color? _peColor(double? pe) {
    if (pe == null) return null;
    if (pe > 20) return const Color(0xFFF87171);
    if (pe > 10) return const Color(0xFFFBBF24);
    return const Color(0xFF34D399);
  }

  Color? _epsColor(double? eps) {
    if (eps == null) return null;
    if (eps < 0) return const Color(0xFFF87171);
    return const Color(0xFF34D399);
  }

  Color? _divColor(double? div) {
    if (div == null) return null;
    if (div > 5) return const Color(0xFF34D399);
    if (div > 2) return const Color(0xFFFBBF24);
    return null;
  }

  String _formatMarketCap(double value) {
    if (value >= 1e9) return '${(value / 1e9).toStringAsFixed(1)}B';
    if (value >= 1e6) return '${(value / 1e6).toStringAsFixed(1)}M';
    if (value >= 1e3) return '${(value / 1e3).toStringAsFixed(1)}K';
    return value.toStringAsFixed(0);
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    this.color,
  });

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label).xSmall.muted,
        const Gap(2),
        Text(
          value,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: color ?? Theme.of(context).colorScheme.foreground,
          ),
        ),
      ],
    );
  }
}
