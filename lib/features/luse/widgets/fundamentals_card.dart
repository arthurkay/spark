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
    final changeColor = fundamental.isGainer
        ? const Color(0xFF34D399)
        : fundamental.isLoser
            ? const Color(0xFFF87171)
            : Theme.of(context).colorScheme.mutedForeground;

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
            const Gap(8),
            Row(
              children: [
                if (fundamental.sector != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .foreground
                          .withAlpha(15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(fundamental.sector!).xSmall,
                  ),
                  const Gap(8),
                ],
                if (fundamental.changePercent != null)
                  Text(
                    '${fundamental.changePercent! >= 0 ? '+' : ''}${fundamental.changePercent!.toStringAsFixed(2)}%',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: changeColor,
                    ),
                  ),
                const Spacer(),
                if (fundamental.peRatio != null)
                  _Metric(
                      label: 'P/E',
                      value: fundamental.peRatio!.toStringAsFixed(1)),
                if (fundamental.eps != null) ...[
                  const Gap(8),
                  _Metric(
                      label: 'EPS',
                      value: 'K${fundamental.eps!.toStringAsFixed(2)}'),
                ],
                if (fundamental.dividendYield != null) ...[
                  const Gap(8),
                  _Metric(
                      label: 'Div',
                      value:
                          '${fundamental.dividendYield!.toStringAsFixed(1)}%'),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label).xSmall.muted,
        const Gap(2),
        Text(value).small.semiBold,
      ],
    );
  }
}
