import 'package:dio/dio.dart';

import '../../features/luse/models/luse_fundamentals.dart';
import '../storage/cache_service.dart';

class MansaApiClient {
  MansaApiClient({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
              headers: {
                'User-Agent':
                    'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36',
                'Accept': 'application/json',
              },
            ));

  final Dio _dio;
  static const _baseUrl = 'https://www.mansaapi.com/api/v1';
  static const _apiKey = 'mansa_api_free'; // Free tier placeholder
  static const _stocksCacheKey = 'mansa_luse_stocks.json';
  static const _stocksCacheTtl = Duration(hours: 4);
  static const _fundamentalsCachePrefix = 'mansa_fundamentals_';
  static const _fundamentalsCacheTtl = Duration(hours: 24);
  static const _moversCacheKey = 'mansa_luse_movers.json';
  static const _moversCacheTtl = Duration(hours: 1);

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $_apiKey',
      };

  Future<List<Map<String, dynamic>>> fetchAllStocks({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = await CacheService.instance.read(
        _stocksCacheKey,
        maxAge: _stocksCacheTtl,
      );
      if (cached != null) {
        return (cached as List).whereType<Map<String, dynamic>>().toList();
      }
    }

    try {
      final response = await _dio.get(
        '$_baseUrl/markets/exchanges/LuSE/stocks',
        options: Options(headers: _headers),
      );
      final data = response.data;
      final stocks = data is List
          ? data.whereType<Map<String, dynamic>>().toList()
          : <Map<String, dynamic>>[];

      await CacheService.instance.write(
        _stocksCacheKey,
        {'items': stocks},
      );
      return stocks;
    } on DioException {
      final cached = await CacheService.instance.read(_stocksCacheKey);
      if (cached != null) {
        return (cached['items'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .toList() ??
            [];
      }
      return [];
    }
  }

  Future<LuseFundamentals?> fetchFundamentals(
    String symbol, {
    bool forceRefresh = false,
  }) async {
    final cacheKey = '$_fundamentalsCachePrefix$symbol.json';

    if (!forceRefresh) {
      final cached = await CacheService.instance.read(
        cacheKey,
        maxAge: _fundamentalsCacheTtl,
      );
      if (cached != null) {
        return LuseFundamentals.fromJson(cached as Map<String, dynamic>);
      }
    }

    try {
      final response = await _dio.get(
        '$_baseUrl/markets/exchanges/LuSE/stocks/$symbol/fundamentals',
        options: Options(headers: _headers),
      );
      final data = response.data;
      if (data is Map<String, dynamic>) {
        final fundamentals = LuseFundamentals.fromJson({
          'symbol': symbol,
          ...data,
        });
        await CacheService.instance.write(cacheKey, fundamentals.toJson());
        return fundamentals;
      }
      return null;
    } on DioException {
      final cached = await CacheService.instance.read(cacheKey);
      if (cached != null) {
        return LuseFundamentals.fromJson(cached as Map<String, dynamic>);
      }
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> fetchMovers({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = await CacheService.instance.read(
        _moversCacheKey,
        maxAge: _moversCacheTtl,
      );
      if (cached != null) {
        return (cached as List).whereType<Map<String, dynamic>>().toList();
      }
    }

    try {
      final response = await _dio.get(
        '$_baseUrl/markets/exchanges/LuSE/movers',
        options: Options(headers: _headers),
      );
      final data = response.data;
      final movers = data is List
          ? data.whereType<Map<String, dynamic>>().toList()
          : <Map<String, dynamic>>[];

      await CacheService.instance.write(
        _moversCacheKey,
        {'items': movers},
      );
      return movers;
    } on DioException {
      final cached = await CacheService.instance.read(_moversCacheKey);
      if (cached != null) {
        return (cached['items'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .toList() ??
            [];
      }
      return [];
    }
  }
}
