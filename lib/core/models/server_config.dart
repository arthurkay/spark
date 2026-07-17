import 'package:uuid/uuid.dart';

import 'server_connection.dart';

const _uuid = Uuid();

class ServerConfig {
  ServerConfig({
    String? id,
    required this.name,
    required this.connection,
    this.lastConnected,
  }) : id = id ?? _uuid.v4();

  final String id;
  final String name;
  final ServerConnection connection;
  final int? lastConnected;

  ServerConfig copyWith({
    String? name,
    ServerConnection? connection,
    int? lastConnected,
  }) {
    return ServerConfig(
      id: id,
      name: name ?? this.name,
      connection: connection ?? this.connection,
      lastConnected: lastConnected ?? this.lastConnected,
    );
  }

  factory ServerConfig.fromJson(Map<String, dynamic> json) {
    return ServerConfig(
      id: json['id'] as String?,
      name: (json['name'] ?? '').toString(),
      connection: ServerConnection.fromJson(
        json['connection'] as Map<String, dynamic>? ?? {},
      ),
      lastConnected: (json['lastConnected'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'connection': connection.toJson(),
        'lastConnected': lastConnected,
      };
}
