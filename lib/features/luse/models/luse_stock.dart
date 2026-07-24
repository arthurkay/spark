class LuseStock {
  const LuseStock({
    required this.symbol,
    required this.name,
    required this.lastPrice,
    required this.change,
    required this.changePercent,
    required this.lastUpdated,
  });

  final String symbol;
  final String name;
  final double lastPrice;
  final double change;
  final double changePercent;
  final DateTime lastUpdated;

  bool get isGainer => change > 0;
  bool get isLoser => change < 0;
  bool get isUnchanged => change == 0;

  factory LuseStock.fromJson(Map<String, dynamic> json) {
    return LuseStock(
      symbol: (json['symbol'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      lastPrice: (json['lastPrice'] as num?)?.toDouble() ?? 0.0,
      change: (json['change'] as num?)?.toDouble() ?? 0.0,
      changePercent: (json['changePercent'] as num?)?.toDouble() ?? 0.0,
      lastUpdated: json['lastUpdated'] is int
          ? DateTime.fromMillisecondsSinceEpoch(json['lastUpdated'])
          : DateTime.tryParse(json['lastUpdated']?.toString() ?? '') ??
              DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'symbol': symbol,
        'name': name,
        'lastPrice': lastPrice,
        'change': change,
        'changePercent': changePercent,
        'lastUpdated': lastUpdated.millisecondsSinceEpoch,
      };
}
