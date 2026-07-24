class LuseFundamentals {
  const LuseFundamentals({
    required this.symbol,
    required this.name,
    this.peRatio,
    this.eps,
    this.dividendYield,
    this.dividendAmount,
    this.marketCap,
    this.lastPrice,
    this.sector,
    this.currency,
    this.isin,
    this.lastUpdated,
  });

  final String symbol;
  final String name;
  final double? peRatio;
  final double? eps;
  final double? dividendYield;
  final double? dividendAmount;
  final double? marketCap;
  final double? lastPrice;
  final String? sector;
  final String? currency;
  final String? isin;
  final DateTime? lastUpdated;

  factory LuseFundamentals.fromJson(Map<String, dynamic> json) {
    return LuseFundamentals(
      symbol: (json['symbol'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      peRatio: _parseDouble(json['peRatio']),
      eps: _parseDouble(json['eps']),
      dividendYield: _parseDouble(json['dividendYield']),
      dividendAmount: _parseDouble(json['dividendAmount']),
      marketCap: _parseDouble(json['marketCap']),
      lastPrice: _parseDouble(json['lastPrice']),
      sector: json['sector']?.toString(),
      currency: json['currency']?.toString(),
      isin: json['isin']?.toString(),
      lastUpdated: json['lastUpdated'] is int
          ? DateTime.fromMillisecondsSinceEpoch(json['lastUpdated'])
          : DateTime.tryParse(json['lastUpdated']?.toString() ?? ''),
    );
  }

  Map<String, dynamic> toJson() => {
        'symbol': symbol,
        'name': name,
        if (peRatio != null) 'peRatio': peRatio,
        if (eps != null) 'eps': eps,
        if (dividendYield != null) 'dividendYield': dividendYield,
        if (dividendAmount != null) 'dividendAmount': dividendAmount,
        if (marketCap != null) 'marketCap': marketCap,
        if (lastPrice != null) 'lastPrice': lastPrice,
        if (sector != null) 'sector': sector,
        if (currency != null) 'currency': currency,
        if (isin != null) 'isin': isin,
        if (lastUpdated != null)
          'lastUpdated': lastUpdated!.millisecondsSinceEpoch,
      };

  static double? _parseDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }
}
