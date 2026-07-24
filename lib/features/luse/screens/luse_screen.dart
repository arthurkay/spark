import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../../features/luse/models/luse_stock.dart';
import '../../../features/luse/providers/luse_provider.dart';
import '../widgets/stock_detail_sheet.dart';
import '../widgets/compare_sheet.dart';

class LuseScreen extends ConsumerStatefulWidget {
  const LuseScreen({super.key});

  @override
  ConsumerState<LuseScreen> createState() => _LuseScreenState();
}

class _LuseScreenState extends ConsumerState<LuseScreen> {
  String _sortField = 'symbol';
  bool _sortAsc = true;
  String _query = '';
  bool _selectMode = false;
  final Set<String> _selected = {};

  void _onStockTap(LuseStock stock) {
    if (_selectMode) {
      setState(() {
        if (_selected.contains(stock.symbol)) {
          _selected.remove(stock.symbol);
          if (_selected.isEmpty) _selectMode = false;
        } else {
          _selected.add(stock.symbol);
        }
      });
    } else {
      openSheetOverlay(
        context: context,
        position: OverlayPosition.bottom,
        builder: (context) => StockDetailSheet(stock: stock),
      );
    }
  }

  void _onStockLongPress(LuseStock stock) {
    if (!_selectMode) {
      setState(() {
        _selectMode = true;
        _selected.add(stock.symbol);
      });
    }
  }

  void _exitSelectMode() {
    setState(() {
      _selectMode = false;
      _selected.clear();
    });
  }

  void _openCompare(List<LuseStock> allStocks) {
    final compareStocks =
        allStocks.where((s) => _selected.contains(s.symbol)).toList();
    if (compareStocks.length < 2) return;
    _exitSelectMode();
    openSheetOverlay(
      context: context,
      position: OverlayPosition.bottom,
      builder: (context) => CompareSheet(stocks: compareStocks),
    );
  }

  @override
  Widget build(BuildContext context) {
    final stocksAsync = ref.watch(luseStocksProvider);
    final watchlist = ref.watch(luseWatchlistProvider);
    final historyAsync = ref.watch(luseHistoryProvider);

    return Scaffold(
      headers: [
        AppBar(
          leading: [
            IconButton.ghost(
              icon: const Icon(LucideIcons.arrowLeft),
              onPressed: () => context.pop(),
            ),
          ],
          title: const Text('LuSE Market'),
          trailing: [
            IconButton.ghost(
              icon: const Icon(LucideIcons.chartBar),
              onPressed: () => context.push('/luse/fundamentals'),
            ),
            IconButton.ghost(
              icon: const Icon(LucideIcons.refreshCw),
              onPressed: () => ref.invalidate(luseStocksProvider),
            ),
          ],
        ),
      ],
      child: stocksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.triangleAlert, size: 40)
                  .iconMutedForeground,
              const Gap(12),
              Text('Failed to load market data').h4,
              const Gap(8),
              Text('$e').muted.textCenter,
              const Gap(16),
              PrimaryButton(
                onPressed: () => ref.invalidate(luseStocksProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (snapshot) {
          final stocks = snapshot.stocks;
          final watchlistStocks =
              stocks.where((s) => watchlist.contains(s.symbol)).toList();
          final filtered = _query.isEmpty
              ? stocks
              : stocks
                  .where((s) =>
                      s.symbol.toLowerCase().contains(_query.toLowerCase()) ||
                      s.name.toLowerCase().contains(_query.toLowerCase()))
                  .toList();
          final sorted = List<LuseStock>.from(filtered)
            ..sort((a, b) {
              int cmp;
              switch (_sortField) {
                case 'price':
                  cmp = a.lastPrice.compareTo(b.lastPrice);
                case 'change':
                  cmp = a.change.compareTo(b.change);
                case 'percent':
                  cmp = a.changePercent.compareTo(b.changePercent);
                default:
                  cmp = a.symbol.compareTo(b.symbol);
              }
              return _sortAsc ? cmp : -cmp;
            });

          return CustomScrollView(
            slivers: [
              // Market summary
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: _MarketSummary(stocks: stocks),
                ),
              ),

              // Watchlist section
              if (watchlistStocks.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                    child: Text('Your Watchlist').small.semiBold.muted,
                  ),
                ),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 90,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: watchlistStocks.length,
                      separatorBuilder: (_, __) => const Gap(8),
                      itemBuilder: (context, index) =>
                          _WatchlistChip(stock: watchlistStocks[index]),
                    ),
                  ),
                ),
              ],

              // History section
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                  child: historyAsync.when(
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                    data: (history) => history.length > 1
                        ? _HistorySection(history: history, stocks: stocks)
                        : const SizedBox.shrink(),
                  ),
                ),
              ),

              // All stocks header
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Text('All Equities').small.semiBold.muted,
                          const Spacer(),
                          Text('${stocks.length} stocks').xSmall.muted,
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

              // Sort / select bar
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _selectMode
                      ? Row(
                          children: [
                            GestureDetector(
                              onTap: _exitSelectMode,
                              child: const Icon(LucideIcons.x, size: 16),
                            ),
                            const Gap(8),
                            Text('${_selected.length} selected').small,
                            const Spacer(),
                            if (_selected.length >= 2)
                              PrimaryButton(
                                size: ButtonSize.small,
                                onPressed: () => _openCompare(sorted),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(LucideIcons.gitCompareArrows,
                                        size: 14),
                                    const Gap(4),
                                    Text('Compare (${_selected.length})'),
                                  ],
                                ),
                              ),
                          ],
                        )
                      : Row(
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
                            const Spacer(),
                            _SortChip(
                              label: 'Change',
                              active: _sortField == 'percent',
                              asc: _sortAsc,
                              onTap: () => _toggleSort('percent'),
                            ),
                          ],
                        ),
                ),
              ),

              // Stock list
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverList.builder(
                  itemCount: sorted.length,
                  itemBuilder: (context, index) {
                    final stock = sorted[index];
                    final isWatched = watchlist.contains(stock.symbol);
                    return _StockRow(
                      stock: stock,
                      isWatched: isWatched,
                      isSelected: _selected.contains(stock.symbol),
                      onToggleWatch: () => ref
                          .read(luseWatchlistProvider.notifier)
                          .toggle(stock.symbol),
                      onTap: () => _onStockTap(stock),
                      onLongPress: () => _onStockLongPress(stock),
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
}

class _MarketSummary extends StatelessWidget {
  const _MarketSummary({required this.stocks});

  final List<LuseStock> stocks;

  @override
  Widget build(BuildContext context) {
    final gainers = stocks.where((s) => s.isGainer).length;
    final losers = stocks.where((s) => s.isLoser).length;
    final unchanged = stocks.where((s) => s.isUnchanged).length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.muted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.chartBar, size: 18),
              const Gap(8),
              const Text('Market Summary').medium.semiBold,
            ],
          ),
          const Gap(12),
          Row(
            children: [
              _SummaryStat(
                label: 'Gainers',
                value: '$gainers',
                color: const Color(0xFF34D399),
                icon: LucideIcons.trendingUp,
              ),
              const Gap(16),
              _SummaryStat(
                label: 'Losers',
                value: '$losers',
                color: const Color(0xFFF87171),
                icon: LucideIcons.trendingDown,
              ),
              const Gap(16),
              _SummaryStat(
                label: 'Unchanged',
                value: '$unchanged',
                color: Theme.of(context).colorScheme.mutedForeground,
                icon: LucideIcons.minus,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryStat extends StatelessWidget {
  const _SummaryStat({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String label;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const Gap(4),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value).medium.semiBold,
            Text(label).xSmall.muted,
          ],
        ),
      ],
    );
  }
}

class _WatchlistChip extends StatelessWidget {
  const _WatchlistChip({required this.stock});

  final LuseStock stock;

  @override
  Widget build(BuildContext context) {
    final color = stock.isGainer
        ? const Color(0xFF34D399)
        : stock.isLoser
            ? const Color(0xFFF87171)
            : Theme.of(context).colorScheme.mutedForeground;

    return Container(
      width: 140,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.muted,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(stock.symbol).small.semiBold,
          const Gap(4),
          Text('K${stock.lastPrice.toStringAsFixed(2)}').medium,
          const Gap(2),
          Text(
            '${stock.change >= 0 ? '+' : ''}${stock.changePercent.toStringAsFixed(2)}%',
            style: TextStyle(fontSize: 10, color: color),
          ),
        ],
      ),
    );
  }
}

class _HistorySection extends StatelessWidget {
  const _HistorySection({
    required this.history,
    required this.stocks,
  });

  final List history;
  final List<LuseStock> stocks;

  @override
  Widget build(BuildContext context) {
    // Show the last 5 days
    final recent =
        history.length > 5 ? history.sublist(history.length - 5) : history;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Recent History').small.semiBold.muted,
        const Gap(8),
        SizedBox(
          height: 60,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: recent.length,
            separatorBuilder: (_, __) => const Gap(8),
            itemBuilder: (context, index) {
              final snapshot = recent[index];
              final date = snapshot.date;
              final dayStocks = snapshot.stocks;
              final gainers = dayStocks.where((s) => s.isGainer).length;
              final losers = dayStocks.where((s) => s.isLoser).length;

              return Container(
                width: 100,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.muted,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${date.month}/${date.day}',
                    ).xSmall.semiBold,
                    const Gap(2),
                    Text(
                      '▲$gainers ▼$losers',
                    ).xSmall.muted,
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
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

class _StockRow extends StatelessWidget {
  const _StockRow({
    required this.stock,
    required this.isWatched,
    required this.onToggleWatch,
    this.isSelected = false,
    this.onTap,
    this.onLongPress,
  });

  final LuseStock stock;
  final bool isWatched;
  final VoidCallback onToggleWatch;
  final bool isSelected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final changeColor = stock.isGainer
        ? const Color(0xFF34D399)
        : stock.isLoser
            ? const Color(0xFFF87171)
            : Theme.of(context).colorScheme.mutedForeground;

    return GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? Theme.of(context).colorScheme.primary.withAlpha(20)
                : null,
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).colorScheme.border,
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            children: [
              if (isSelected)
                const Padding(
                  padding: EdgeInsets.only(right: 12),
                  child: Icon(LucideIcons.check, size: 16),
                )
              else ...[
                GestureDetector(
                  onTap: onToggleWatch,
                  child: Icon(
                    isWatched ? LucideIcons.star : LucideIcons.star,
                    size: 16,
                    color: isWatched
                        ? const Color(0xFFFBBF24)
                        : Theme.of(context).colorScheme.mutedForeground,
                  ),
                ),
                const Gap(12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(stock.symbol).small.semiBold,
                    Text(stock.name).xSmall.muted,
                  ],
                ),
              ),
              Text('K${stock.lastPrice.toStringAsFixed(2)}').medium,
              const Gap(12),
              SizedBox(
                width: 70,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${stock.change >= 0 ? '+' : ''}${stock.change.toStringAsFixed(2)}',
                      style: TextStyle(fontSize: 10, color: changeColor),
                    ),
                    Text(
                      '${stock.changePercent >= 0 ? '+' : ''}${stock.changePercent.toStringAsFixed(2)}%',
                      style: TextStyle(fontSize: 10, color: changeColor),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ));
  }
}
