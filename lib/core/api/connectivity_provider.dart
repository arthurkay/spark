import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';
import 'sse_client.dart';

class ConnectivityController extends Notifier<bool> {
  int _errorCount = 0;

  @override
  bool build() {
    ref.listen<AsyncValue<OpencodeEvent>>(eventStreamProvider, (prev, next) {
      next.whenOrNull(
        data: (event) {
          if (event.type == 'server.connected' ||
              event.type == 'server.reconnected') {
            _errorCount = 0;
            state = true;
          }
        },
        error: (_, __) {
          _errorCount++;
          if (_errorCount >= 3) state = false;
        },
      );
    });

    final client = ref.watch(opencodeClientProvider);
    if (client == null) {
      return false;
    }
    return true;
  }

  void setConnected(bool value) {
    if (value) _errorCount = 0;
    state = value;
  }
}

final connectivityProvider = NotifierProvider<ConnectivityController, bool>(
  ConnectivityController.new,
);
