import 'package:flutter_test/flutter_test.dart';

import 'package:spark/core/models/server_connection.dart';

void main() {
  test('ServerConnection builds base url', () {
    const conn = ServerConnection(host: '127.0.0.1', port: 4096);
    expect(conn.baseUrl, 'http://127.0.0.1:4096');
  });

  test('ServerConnection uses https scheme', () {
    const conn = ServerConnection(
      host: 'example.com',
      port: 443,
      useHttps: true,
    );
    expect(conn.baseUrl, 'https://example.com:443');
  });
}
