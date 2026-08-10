import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

Future<void> main() async {
  const base = 'http://127.0.0.1:40711';
  final dir = '/tmp';
  final client = HttpOverrides.current;
  // create pty via dart:io
  final ptyId = await _createPty(base, dir);
  print('pty=$ptyId');

  final uri = Uri.parse('ws://127.0.0.1:40711/pty/$ptyId/connect?cursor=0');
  final channel = WebSocketChannel.connect(uri);
  final completer = Completer<int>();
  final buffer = StringBuffer();
  const marker = 'SPARK_WRITE_DONE_dart';
  const delim = 'SPARK_EOF_dart';
  final markerRe = RegExp('$marker:(-?\\d+)');
  final encoded = base64Encode(utf8.encode('dart probe\n'));
  final command = "base64 -d << '$delim' > '/tmp/dart-probe-out.txt'\n"
      '$encoded\n'
      '$delim\n'
      "printf '\\n$marker:%d\\n' \$?\n";

  final sub = channel.stream.listen((data) {
    if (completer.isCompleted) return;
    if (data is List<int>) {
      if (data.isNotEmpty && data[0] == 0x00) return;
      buffer.write(utf8.decode(data, allowMalformed: true));
    } else if (data is String) {
      buffer.write(data);
    }
    final m = markerRe.firstMatch(buffer.toString());
    if (m != null && !completer.isCompleted) {
      print('marker matched exit=${m.group(1)}');
      completer.complete(int.parse(m.group(1)!));
    }
  });

  await Future<void>.delayed(const Duration(milliseconds: 600));
  channel.sink.add(utf8.encode(command));
  final exit = await completer.future.timeout(const Duration(seconds: 15));
  print('exit=$exit');

  print('cancelling subscription...');
  await sub.cancel();
  print('subscription cancelled');
  print('closing sink...');
  await channel.sink.close().timeout(const Duration(seconds: 5),
      onTimeout: () => print('!!! sink.close() HUNG (timed out at 5s)'));
  print('sink closed');
  print('done');
}

Future<String> _createPty(String base, String dir) async {
  final httpClient = HttpClient();
  final req = await httpClient.postUrl(Uri.parse('$base/pty'));
  req.headers.contentType = ContentType.json;
  req.write(jsonEncode({'title': 'file-write', 'cwd': dir}));
  final res = await req.close();
  final body = await res.transform(utf8.decoder).join();
  httpClient.close();
  return (jsonDecode(body) as Map<String, dynamic>)['id'] as String;
}
