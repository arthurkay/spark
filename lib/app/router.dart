import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/api/providers.dart';
import '../features/chat/chat_screen.dart';
import '../features/connection/settings_screen.dart';
import '../features/files/diff_screen.dart';
import '../features/files/files_screen.dart';
import '../features/sessions/sessions_screen.dart';

GoRouter createRouter(Ref ref) {
  return GoRouter(
    initialLocation: '/',
    refreshListenable: _ConnectionListenable(ref),
    routes: [
      GoRoute(path: '/', builder: (context, state) => const ProjectsScreen()),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/session/:id',
        builder: (context, state) =>
            ChatScreen(sessionId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/session/:id/files',
        builder: (context, state) =>
            FilesScreen(sessionId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/workspace/:worktree/files',
        builder: (context, state) => FilesScreen(
          directory: Uri.decodeComponent(state.pathParameters['worktree']!),
        ),
      ),
      GoRoute(
        path: '/session/:id/diff',
        builder: (context, state) =>
            DiffScreen(sessionId: state.pathParameters['id']!),
      ),
    ],
  );
}

class _ConnectionListenable extends ChangeNotifier {
  _ConnectionListenable(Ref ref) {
    ref.listen(serverManagerProvider, (prev, next) => notifyListeners());
  }
}
