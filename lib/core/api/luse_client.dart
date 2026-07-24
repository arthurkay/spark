import 'package:dio/dio.dart';

import '../../features/luse/models/luse_stock.dart';
import '../../features/luse/models/luse_market_snapshot.dart';
import '../storage/luse_store.dart';
import '../storage/cache_service.dart';

class LuseClient {
  LuseClient({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
              headers: {
                'User-Agent':
                    'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36',
                'Accept': 'text/html,application/xhtml+xml',
              },
            ));

  final Dio _dio;
  static const _baseUrl = 'https://www.luse.co.zm';
  static const _cacheKey = 'luse_stocks_v2.json';
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
      final response = await _dio.get(_baseUrl);
      final html = response.data.toString();
      final stocks = _parseStocksFromHtml(html);
      final snapshot = LuseMarketSnapshot(
        date: DateTime.now(),
        stocks: stocks,
        source: 'LuSE',
      );

      await CacheService.instance.write(_cacheKey, snapshot.toJson());
      await _store.saveSnapshot(snapshot);

      return snapshot;
    } on DioException {
      final cached = await CacheService.instance.read(_cacheKey);
      if (cached != null) {
        return LuseMarketSnapshot.fromJson(cached);
      }
      return LuseMarketSnapshot(
        date: DateTime.now(),
        stocks: const [],
        source: 'LuSE',
      );
    }
  }

  List<LuseStock> _parseStocksFromHtml(String html) {
    final stocks = <LuseStock>[];
    final now = DateTime.now();

    // Known LuSE stock names mapping (verified against LuSE official data)
    const stockNames = {
      'AECI': 'AECI Mining Explosives',
      'ATEL': 'Airtel Networks',
      'BATA': 'Zambia Bata Shoe',
      'BATZ': 'British American Tobacco Zambia',
      'CCAF': 'CEC Africa (CECA) Investments',
      'CECZ': 'Copperbelt Energy Corporation',
      'CHIL': 'Chilanga Cement',
      'DCZM': 'Dot Com Zambia',
      'FARM': 'REIZ Preference Shares',
      'KLRE': 'Klapton Reinsurance',
      'MAFS': 'Madison Financial Services',
      'NATB': 'National Breweries',
      'PMDZ': 'Pamodzi Hotels',
      'PUMA': 'Puma Energy',
      'REIZUSD': 'Real Estate Investments Zambia',
      'SCBL': 'Standard Chartered Bank Zambia',
      'SHOP': 'Shoprite Holdings',
      'ZABR': 'Zambia Breweries',
      'ZCCM-IH': 'ZCCM Investment Holdings',
      'ZFCO': 'Zambia Forestry & Forest Industries Corp',
      'ZMBF': 'Zambeef Products',
      'ZMFA': 'Metal Fabricators of Zambia',
      'ZMRE': 'Zambia Reinsurance',
      'ZNCO': 'Zanaco',
      'ZSUG': 'Zambia Sugar',
    };

    // Pattern: symbol followed by price and change
    // Look for stock ticker patterns in the HTML
    final tickerPattern = RegExp(
      r'(?:>|[\s>])([A-Z][A-Z0-9\-]+(?:\s[A-Z]+)?)(?:<|\s)',
      multiLine: true,
    );
    final pricePattern = RegExp(
      r'(\d{1,6}\.\d{2})',
    );
    final changePattern = RegExp(
      r'([+\-]?\d{1,6}\.\d{2})',
    );

    // Find all ticker symbols in the page
    final tickers = <String>{};
    for (final match in tickerPattern.allMatches(html)) {
      final symbol = match.group(1)?.trim() ?? '';
      if (symbol.isNotEmpty &&
          symbol.length >= 2 &&
          symbol.length <= 10 &&
          stockNames.containsKey(symbol)) {
        tickers.add(symbol);
      }
    }

    // Parse each stock section
    for (final symbol in tickers) {
      // Find the section around this symbol
      final symbolIndex = html.indexOf(symbol);
      if (symbolIndex == -1) continue;

      final section = html.substring(
        symbolIndex,
        (symbolIndex + 500).clamp(0, html.length),
      );

      // Extract prices from the section
      final prices = pricePattern
          .allMatches(section)
          .map((m) => double.tryParse(m.group(1) ?? '') ?? 0.0)
          .where((p) => p > 0)
          .toList();

      // Extract changes
      final changes = changePattern
          .allMatches(section)
          .map((m) => double.tryParse(m.group(1) ?? '') ?? 0.0)
          .toList();

      if (prices.isNotEmpty) {
        final price = prices.first;
        final change = changes.length > 1 ? changes[1] : 0.0;
        final changePercent =
            price > 0 ? (change / (price - change)) * 100 : 0.0;

        stocks.add(LuseStock(
          symbol: symbol,
          name: stockNames[symbol] ?? symbol,
          lastPrice: price,
          change: change,
          changePercent: double.parse(changePercent.toStringAsFixed(2)),
          lastUpdated: now,
        ));
      }
    }

    // Sort by symbol
    stocks.sort((a, b) => a.symbol.compareTo(b.symbol));

    return stocks;
  }

  Future<void> clearCache() async {
    await CacheService.instance.delete(_cacheKey);
  }
}
