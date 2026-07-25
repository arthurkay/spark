import 'africanfinancials_client.dart';
import '../../features/luse/models/luse_stock.dart';
import '../../features/luse/models/luse_market_snapshot.dart';
import '../storage/luse_store.dart';
import '../storage/cache_service.dart';

class LuseClient {
  LuseClient({AfricanfinancialsClient? africanfinancialsClient})
      : _afClient = africanfinancialsClient ?? AfricanfinancialsClient();

  final AfricanfinancialsClient _afClient;
  static const _cacheKey = 'luse_stocks_v3.json';
  static const _cacheTtl = Duration(hours: 4);

  final _store = LuseStore();

  Future<LuseMarketSnapshot> fetchStocks({bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cached = await CacheService.instance.read(
        _cacheKey,
        maxAge: _cacheTtl,
      );
      if (cached != null) {
        return LuseMarketSnapshot.fromJson(cached);
      }
    }

    try {
      final fundamentals = await _afClient.fetchAllFundamentals();
      final stocks = fundamentals
          .map((f) => LuseStock(
                symbol: f.symbol,
                name: f.name,
                lastPrice: f.lastPrice ?? 0,
                change: f.change ?? 0,
                changePercent: f.changePercent ?? 0,
                lastUpdated: f.lastUpdated ?? DateTime.now(),
              ))
          .toList();

      final snapshot = LuseMarketSnapshot(
        date: DateTime.now(),
        stocks: stocks,
        source: 'Africanfinancials',
      );

      await CacheService.instance.write(_cacheKey, snapshot.toJson());
      await _store.saveSnapshot(snapshot);

      final watchlist = await _store.getWatchlist();
      if (watchlist.isNotEmpty) {
        await _store.saveWatchlistHistory(watchlist, stocks);
      }

      return snapshot;
    } catch (_) {
      final cached = await CacheService.instance.read(_cacheKey);
      if (cached != null) {
        return LuseMarketSnapshot.fromJson(cached);
      }
      return LuseMarketSnapshot(
        date: DateTime.now(),
        stocks: const [],
        source: 'Africanfinancials',
      );
    }
  }

  Future<void> clearCache() async {
    await CacheService.instance.delete(_cacheKey);
  }
}
