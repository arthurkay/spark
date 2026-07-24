class LuseCompanyProfile {
  const LuseCompanyProfile({
    required this.symbol,
    required this.name,
    this.description = '',
    this.sector,
    this.listingDate,
    this.yearEnd,
    this.address,
    this.phone,
    this.website,
    this.reports = const [],
  });

  final String symbol;
  final String name;
  final String description;
  final String? sector;
  final String? listingDate;
  final String? yearEnd;
  final String? address;
  final String? phone;
  final String? website;
  final List<LuseCompanyReport> reports;

  factory LuseCompanyProfile.fromJson(Map<String, dynamic> json) {
    final rawReports = json['reports'];
    final reports = rawReports is List
        ? rawReports
            .whereType<Map<String, dynamic>>()
            .map(LuseCompanyReport.fromJson)
            .toList()
        : <LuseCompanyReport>[];
    return LuseCompanyProfile(
      symbol: (json['symbol'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      sector: json['sector']?.toString(),
      listingDate: json['listingDate']?.toString(),
      yearEnd: json['yearEnd']?.toString(),
      address: json['address']?.toString(),
      phone: json['phone']?.toString(),
      website: json['website']?.toString(),
      reports: reports,
    );
  }

  Map<String, dynamic> toJson() => {
        'symbol': symbol,
        'name': name,
        'description': description,
        if (sector != null) 'sector': sector,
        if (listingDate != null) 'listingDate': listingDate,
        if (yearEnd != null) 'yearEnd': yearEnd,
        if (address != null) 'address': address,
        if (phone != null) 'phone': phone,
        if (website != null) 'website': website,
        'reports': reports.map((r) => r.toJson()).toList(),
      };
}

class LuseCompanyReport {
  const LuseCompanyReport({
    required this.title,
    required this.url,
    this.date,
    this.type,
  });

  final String title;
  final String url;
  final String? date;
  final String? type;

  factory LuseCompanyReport.fromJson(Map<String, dynamic> json) {
    return LuseCompanyReport(
      title: (json['title'] ?? '').toString(),
      url: (json['url'] ?? '').toString(),
      date: json['date']?.toString(),
      type: json['type']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'url': url,
        if (date != null) 'date': date,
        if (type != null) 'type': type,
      };
}
