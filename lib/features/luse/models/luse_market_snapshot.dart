import 'luse_stock.dart';

class LuseMarketSnapshot {
  const LuseMarketSnapshot({
    required this.date,
    required this.stocks,
    required this.source,
  });

  final DateTime date;
  final List<LuseStock> stocks;
  final String source;

  int get totalStocks => stocks.length;
  int get gainers => stocks.where((s) => s.isGainer).length;
  int get losers => stocks.where((s) => s.isLoser).length;
  int get unchanged => stocks.where((s) => s.isUnchanged).length;

  String get dateKey =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  factory LuseMarketSnapshot.fromJson(Map<String, dynamic> json) {
    final stocksList = (json['stocks'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(LuseStock.fromJson)
        .toList();
    return LuseMarketSnapshot(
      date: json['date'] is int
          ? DateTime.fromMillisecondsSinceEpoch(json['date'])
          : DateTime.tryParse(json['date']?.toString() ?? '') ?? DateTime.now(),
      stocks: stocksList,
      source: (json['source'] ?? 'LuSE').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'date': date.millisecondsSinceEpoch,
        'stocks': stocks.map((s) => s.toJson()).toList(),
        'source': source,
      };
}
