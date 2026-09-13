class ServerConnection {
  const ServerConnection({
    required this.host,
    required this.port,
    this.username,
    this.useHttps = false,
  });

  final String host;
  final int port;
  final String? username;
  final bool useHttps;

  String get scheme => useHttps ? 'https' : 'http';

  String get baseUrl => '$scheme://$host:$port';

  ServerConnection copyWith({
    String? host,
    int? port,
    String? username,
    bool? useHttps,
  }) {
    return ServerConnection(
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      useHttps: useHttps ?? this.useHttps,
    );
  }

  factory ServerConnection.fromJson(Map<String, dynamic> json) {
    return ServerConnection(
      host: (json['host'] ?? '').toString(),
      port: (json['port'] as num?)?.toInt() ?? 4096,
      username: json['username'] as String?,
      useHttps: json['useHttps'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
    'host': host,
    'port': port,
    'username': username,
    'useHttps': useHttps,
  };
}
