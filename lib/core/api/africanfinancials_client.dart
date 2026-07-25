import 'package:dio/dio.dart';

import '../../features/luse/models/luse_company_profile.dart';
import '../../features/luse/models/luse_fundamentals.dart';
import '../storage/cache_service.dart';

class AfricanfinancialsClient {
  AfricanfinancialsClient({Dio? dio})
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
  static const _baseUrl = 'https://africanfinancials.com';
  static const _cachePrefix = 'af_profile_';
  static const _cacheTtl = Duration(hours: 24);
  static const _fundamentalsCacheKey = 'af_fundamentals.json';
  static const _fundamentalsCacheTtl = Duration(hours: 24);

  static const _stockTickerMap = {
    'AECI': 'aeci',
    'ATEL': 'atel',
    'BATA': 'bata',
    'BATZ': 'batz',
    'CCAF': 'ccaf',
    'CECZ': 'cecz',
    'CHIL': 'chil',
    'DCZM': 'dczm',
    'FARM': 'farm',
    'KLRE': 'klre',
    'MAFS': 'mafs',
    'NATB': 'natb',
    'PMDZ': 'pmdz',
    'PUMA': 'puma',
    'REIZUSD': 'reizusd',
    'SCBL': 'scbl',
    'SHOP': 'shop',
    'ZABR': 'zabr',
    'ZCCM-IH': 'zccm',
    'ZFCO': 'zfco',
    'ZMBF': 'zmbf',
    'ZMFA': 'zmfa',
    'ZMRE': 'zmre',
    'ZNCO': 'znco',
    'ZSUG': 'zsug',
  };

  Future<LuseCompanyProfile?> fetchProfile(
    String symbol, {
    bool forceRefresh = false,
  }) async {
    final cacheKey = '$_cachePrefix$symbol.json';

    if (!forceRefresh) {
      final cached = await CacheService.instance.read(
        cacheKey,
        maxAge: _cacheTtl,
      );
      if (cached != null) {
        return LuseCompanyProfile.fromJson(cached as Map<String, dynamic>);
      }
    }

    final slug = _stockTickerMap[symbol] ?? symbol.toLowerCase();
    try {
      final response = await _dio.get('$_baseUrl/company/zm-$slug/');
      final html = response.data.toString();
      final profile = _parseProfile(html, symbol);

      if (profile != null) {
        await CacheService.instance.write(cacheKey, profile.toJson());
      }
      return profile;
    } on DioException {
      final cached = await CacheService.instance.read(cacheKey);
      if (cached != null) {
        return LuseCompanyProfile.fromJson(cached as Map<String, dynamic>);
      }
      return null;
    }
  }

  LuseCompanyProfile? _parseProfile(String html, String symbol) {
    final name = _extractText(
        html,
        RegExp(
          r'<h1[^>]*class="[^"]*entry-title[^"]*"[^>]*>([^<]+)</h1>',
        ));
    if (name == null) return null;

    final description = _extractText(
            html,
            RegExp(
              r'<div[^>]*class="[^"]*company-description[^"]*"[^>]*>([\s\S]*?)</div>',
            )) ??
        '';

    final sector = _extractText(
        html,
        RegExp(
          r'(?:Sector|Industry)[:\s]*</(?:dt|th|span|div)>\s*<(?:dd|td|span|div)[^>]*>([^<]+)',
        ));

    final listingDate = _extractText(
        html,
        RegExp(
          r'(?:Listed|Listing\s*Date)[:\s]*</(?:dt|th|span|div)>\s*<(?:dd|td|span|div)[^>]*>([^<]+)',
        ));

    final yearEnd = _extractText(
        html,
        RegExp(
          r'(?:Year\s*End|Financial\s*Year)[:\s]*</(?:dt|th|span|div)>\s*<(?:dd|td|span|div)[^>]*>([^<]+)',
        ));

    final address = _extractText(
        html,
        RegExp(
          r'(?:Address|Registered\s*Office)[:\s]*</(?:dt|th|span|div)>\s*<(?:dd|td|span|div)[^>]*>([\s\S]*?)</(?:dd|td|span|div)',
        ));

    final phone = _extractText(
        html,
        RegExp(
          r'(?:Tel(?:ephone)?|Phone)[:\s]*</(?:dt|th|span|div)>\s*<(?:dd|td|span|div)[^>]*>([\s\S]*?)</(?:dd|td|span|div)',
        ));

    final website = _extractAttribute(
        html,
        RegExp(
          r'<a[^>]*href="(https?://[^"]+)"[^>]*>\s*(?:Visit\s*Website|Website)',
        ));

    final reports = _parseReports(html);

    return LuseCompanyProfile(
      symbol: symbol,
      name: _cleanHtml(name),
      description: _cleanHtml(description),
      sector: sector?.trim(),
      listingDate: listingDate?.trim(),
      yearEnd: yearEnd?.trim(),
      address: address?.trim().replaceAll(RegExp(r'\s+'), ' '),
      phone: phone?.trim(),
      website: website,
      reports: reports,
    );
  }

  List<LuseCompanyReport> _parseReports(String html) {
    final reports = <LuseCompanyReport>[];
    final pattern = RegExp(
      r'<a[^>]*href="([^"]*(?:document|report|annual|interim|abridged)[^"]*)"[^>]*>\s*([^<]*(?:Annual|Interim|Abridged|Report|Financial|Presentation|Circular)[^<]*)\s*</a>',
      caseSensitive: false,
    );
    for (final match in pattern.allMatches(html)) {
      final url = match.group(1) ?? '';
      final title = match.group(2) ?? '';
      if (url.isNotEmpty && title.isNotEmpty) {
        final dateMatch = RegExp(r'(\d{4})').firstMatch(title);
        reports.add(LuseCompanyReport(
          title: _cleanHtml(title),
          url: url.startsWith('http') ? url : '$_baseUrl$url',
          date: dateMatch?.group(1),
          type: _detectReportType(title),
        ));
      }
    }
    return reports;
  }

  String? _detectReportType(String title) {
    final lower = title.toLowerCase();
    if (lower.contains('annual')) return 'Annual Report';
    if (lower.contains('interim')) return 'Interim Report';
    if (lower.contains('abridged')) return 'Abridged Report';
    if (lower.contains('presentation')) return 'Presentation';
    if (lower.contains('circular')) return 'Circular';
    return 'Report';
  }

  String? _extractText(String html, RegExp pattern) {
    final match = pattern.firstMatch(html);
    return match?.group(1)?.trim();
  }

  String? _extractAttribute(String html, RegExp pattern) {
    final match = pattern.firstMatch(html);
    return match?.group(1)?.trim();
  }

  String _cleanHtml(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll(RegExp(r'&nbsp;'), ' ')
        .replaceAll(RegExp(r'&amp;'), '&')
        .replaceAll(RegExp(r'&lt;'), '<')
        .replaceAll(RegExp(r'&gt;'), '>')
        .replaceAll(RegExp(r'&quot;'), '"')
        .replaceAll(RegExp(r'&#\d+;'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Future<List<LuseFundamentals>> fetchAllFundamentals({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = await CacheService.instance.read(
        _fundamentalsCacheKey,
        maxAge: _fundamentalsCacheTtl,
      );
      if (cached != null) {
        final items = cached['items'] as List<dynamic>? ?? [];
        return items
            .whereType<Map<String, dynamic>>()
            .map(LuseFundamentals.fromJson)
            .toList();
      }
    }

    try {
      final response = await _dio.get(
        '$_baseUrl/lusaka-securities-exchange-share-prices/',
      );
      final html = response.data.toString();
      final fundamentals = _parseSharePricesPage(html);

      await CacheService.instance.write(
        _fundamentalsCacheKey,
        {'items': fundamentals.map((f) => f.toJson()).toList()},
      );
      return fundamentals;
    } on DioException {
      final cached = await CacheService.instance.read(_fundamentalsCacheKey);
      if (cached != null) {
        final items = cached['items'] as List<dynamic>? ?? [];
        return items
            .whereType<Map<String, dynamic>>()
            .map(LuseFundamentals.fromJson)
            .toList();
      }
      return [];
    }
  }

  List<LuseFundamentals> _parseSharePricesPage(String html) {
    final fundamentals = <LuseFundamentals>[];
    final now = DateTime.now();

    final tickerToSymbol = <String, String>{};
    for (final entry in _stockTickerMap.entries) {
      tickerToSymbol[entry.value] = entry.key;
    }

    final rowPattern = RegExp(
      r'<tr[^>]*>\s*<td[^>]*>.*?<a[^>]*href="[^"]*company/zm-([^/"]+)/[^"]*"[^>]*title="([^"]*)"[^>]*>.*?</a>.*?</td>\s*'
      r'<td[^>]*>\s*([\d,]+\.?\d*)\s*</td>\s*'
      r'<td[^>]*>\s*([+\-]?[\d,]+\.?\d*)\s*%?\s*</td>\s*'
      r'<td[^>]*>\s*([\d,]+)\s*</td>\s*'
      r'<td[^>]*>\s*([\d,]+)\s*</td>\s*'
      r'<td[^>]*>\s*([+\-]?[\d,]+\.?\d*)\s*%?\s*</td>\s*'
      r'<td[^>]*>\s*([^<]*)\s*</td>',
      multiLine: true,
    );

    for (final match in rowPattern.allMatches(html)) {
      final slug = match.group(1) ?? '';
      final fullName = match.group(2) ?? '';
      final priceStr = match.group(3)?.replaceAll(',', '') ?? '';
      final changeStr = match.group(4)?.replaceAll(',', '') ?? '';
      final sector = match.group(8)?.trim() ?? '';

      final symbol = tickerToSymbol[slug] ?? slug.toUpperCase();
      final price = double.tryParse(priceStr);
      final change = double.tryParse(changeStr);

      if (price != null && price > 0) {
        final changePercent = change ?? 0.0;
        fundamentals.add(LuseFundamentals(
          symbol: symbol,
          name: _cleanHtml(fullName),
          lastPrice: price,
          change: changePercent,
          changePercent: changePercent,
          sector: sector.isNotEmpty ? sector : null,
          lastUpdated: now,
        ));
      }
    }

    fundamentals.sort((a, b) => a.symbol.compareTo(b.symbol));
    return fundamentals;
  }
}
