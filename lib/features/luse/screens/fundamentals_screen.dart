import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../models/luse_fundamentals.dart';
import '../providers/luse_provider.dart';
import '../widgets/fundamentals_chart_carousel.dart';
import '../widgets/fundamentals_card.dart';
import '../widgets/company_profile_sheet.dart';

class FundamentalsScreen extends ConsumerStatefulWidget {
  const FundamentalsScreen({super.key});

  @override
  ConsumerState<FundamentalsScreen> createState() => _FundamentalsScreenState();
}

class _FundamentalsScreenState extends ConsumerState<FundamentalsScreen> {
  String _sortField = 'symbol';
  bool _sortAsc = true;
  String _query = '';

  void _toggleSort(String field) {
    setState(() {
      if (_sortField == field) {
        _sortAsc = !_sortAsc;
      } else {
        _sortField = field;
        _sortAsc = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final fundamentalsAsync = ref.watch(luseFundamentalsProvider);

    return Scaffold(
      headers: [
        AppBar(
          leading: [
            IconButton.ghost(
              icon: const Icon(LucideIcons.arrowLeft),
              onPressed: () => context.pop(),
            ),
          ],
          title: const Text('Fundamentals'),
          trailing: [
            IconButton.ghost(
              icon: const Icon(LucideIcons.refreshCw),
              onPressed: () => ref.invalidate(luseFundamentalsProvider),
            ),
          ],
        ),
      ],
      child: fundamentalsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.triangleAlert, size: 40)
                  .iconMutedForeground,
              const Gap(12),
              Text('Failed to load fundamentals').h4,
              const Gap(8),
              Text('$e').muted.textCenter,
              const Gap(16),
              PrimaryButton(
                onPressed: () => ref.invalidate(luseFundamentalsProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (fundamentals) {
          final filtered = _query.isEmpty
              ? fundamentals
              : fundamentals
                  .where((f) =>
                      f.symbol.toLowerCase().contains(_query.toLowerCase()) ||
                      f.name.toLowerCase().contains(_query.toLowerCase()))
                  .toList();

          final sorted = List<LuseFundamentals>.from(filtered)
            ..sort((a, b) {
              int cmp;
              switch (_sortField) {
                case 'price':
                  cmp = _compareNullable(a.lastPrice, b.lastPrice);
                case 'change':
                  cmp = _compareNullable(a.changePercent, b.changePercent);
                case 'sector':
                  cmp = (a.sector ?? 'zzz').compareTo(b.sector ?? 'zzz');
                default:
                  cmp = a.symbol.compareTo(b.symbol);
              }
              return _sortAsc ? cmp : -cmp;
            });

          return CustomScrollView(
            slivers: [
              // Chart carousel
              if (fundamentals.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: FundamentalsChartCarousel(
                      fundamentals: fundamentals,
                    ),
                  ),
                ),

              // Search
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Text('All Stocks').small.semiBold.muted,
                          const Spacer(),
                          Text('${fundamentals.length} stocks').xSmall.muted,
                        ],
                      ),
                      const Gap(8),
                      TextField(
                        placeholder: const Text('Search stocks...'),
                        border: Border.all(color: Colors.transparent),
                        features: const [
                          InputFeature.leading(
                              Icon(LucideIcons.search, size: 16)),
                        ],
                        onChanged: (v) => setState(() => _query = v.trim()),
                      ),
                    ],
                  ),
                ),
              ),

              // Sort bar
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      _SortChip(
                        label: 'Symbol',
                        active: _sortField == 'symbol',
                        asc: _sortAsc,
                        onTap: () => _toggleSort('symbol'),
                      ),
                      const Gap(8),
                      _SortChip(
                        label: 'Price',
                        active: _sortField == 'price',
                        asc: _sortAsc,
                        onTap: () => _toggleSort('price'),
                      ),
                      const Gap(8),
                      _SortChip(
                        label: 'Change',
                        active: _sortField == 'change',
                        asc: _sortAsc,
                        onTap: () => _toggleSort('change'),
                      ),
                      const Spacer(),
                      _SortChip(
                        label: 'Sector',
                        active: _sortField == 'sector',
                        asc: _sortAsc,
                        onTap: () => _toggleSort('sector'),
                      ),
                    ],
                  ),
                ),
              ),

              // Stock list
              SliverPadding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                sliver: SliverList.builder(
                  itemCount: sorted.length,
                  itemBuilder: (context, index) {
                    final fund = sorted[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: FundamentalsCard(
                        fundamental: fund,
                        onTap: () => openSheetOverlay(
                          context: context,
                          position: OverlayPosition.bottom,
                          builder: (context) =>
                              CompanyProfileSheet(symbol: fund.symbol),
                        ),
                      ),
                    );
                  },
                ),
              ),

              const SliverToBoxAdapter(child: Gap(80)),
            ],
          );
        },
      ),
    );
  }

  int _compareNullable(double? a, double? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return a.compareTo(b);
  }
}

class _SortChip extends StatelessWidget {
  const _SortChip({
    required this.label,
    required this.active,
    required this.asc,
    required this.onTap,
  });

  final String label;
  final bool active;
  final bool asc;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: active
                  ? Theme.of(context).colorScheme.foreground
                  : Theme.of(context).colorScheme.mutedForeground,
            ),
          ),
          if (active) ...[
            const Gap(2),
            Icon(
              asc ? LucideIcons.chevronUp : LucideIcons.chevronDown,
              size: 10,
            ),
          ],
        ],
      ),
    );
  }
}
