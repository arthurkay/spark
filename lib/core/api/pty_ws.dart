import 'dart:convert';

import 'opencode_client.dart';

/// Builds the WebSocket URL used to stream a PTY session's I/O.
///
/// Auth is carried via the `auth_token` query parameter (a base64 `user:password`
/// Basic-auth-style token) since a WebSocket handshake can't reuse the Dio
/// client's normal HTTP headers. This is the only auth mechanism actually
/// exercised against `/pty/:id/connect` in this app — `getPtyConnectToken`
/// (`/pty/:id/connect-token`) exists on [OpencodeClient] but is unused.
Uri buildPtyWebSocketUri({
  required OpencodeClient client,
  required String ptyId,
  String? directory,
  int cursor = 0,
}) {
  final baseUrl = client.dio.options.baseUrl;
  final wsScheme = baseUrl.startsWith('https') ? 'wss' : 'ws';
  final host = baseUrl.replaceFirst(RegExp(r'^https?://'), '');

  String? authToken;
  final password = client.password;
  if (password != null && password.isNotEmpty) {
    final user = client.connection.username?.isNotEmpty == true
        ? client.connection.username!
        : 'opencode';
    authToken = base64Encode(utf8.encode('$user:$password'));
  }

  final queryParams = <String, String>{
    'cursor': '$cursor',
    if (directory != null) 'directory': directory,
    if (authToken != null) 'auth_token': authToken,
  };
  final query = queryParams.entries
      .map((e) =>
          '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
      .join('&');
  return Uri.parse('$wsScheme://$host/pty/$ptyId/connect?$query');
}
