import 'package:flutter/cupertino.dart' show CupertinoPage;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/api/providers.dart';
import '../core/storage/settings_store.dart';
import '../features/chat/chat_screen.dart';
import '../features/connection/connection_screen.dart';
import '../features/connection/settings_screen.dart';
import '../features/connection/welcome_screen.dart';
import '../features/files/diff_screen.dart';
import '../features/files/files_screen.dart';
import '../features/sessions/sessions_screen.dart';
import '../features/terminal/terminal_screen.dart';
import 'motion.dart';

/// A page pushed onto the navigation stack.
///
/// Uses [CupertinoPage] rather than a hand-rolled `CustomTransitionPage` for
/// three reasons the custom builders didn't provide:
///
///  * it animates the *outgoing* page too (parallax + dim). The previous
///    builders accepted `secondaryAnimation` and ignored it, so the page being
///    covered sat perfectly still — the main reason navigation felt flat.
///  * it comes with the edge swipe-back gesture, which the app had nowhere.
///  * its duration and curve are the platform's, instead of go_router's
///    unspecified 300ms default.
Page<void> _stackPage(GoRouterState state, Widget child) {
  return CupertinoPage<void>(key: state.pageKey, child: child);
}

/// The root page. Not part of the push stack — it cross-fades, since there is
/// no spatial relationship between "welcome" and "projects".
Page<void> _rootPage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: Motion.slow,
    reverseTransitionDuration: Motion.base,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Motion.standard),
        child: child,
      );
    },
  );
}

GoRouter createRouter(Ref ref) {
  return GoRouter(
    initialLocation: '/',
    refreshListenable: _ConnectionListenable(ref),
    redirect: (context, state) {
      // '/' is recorded like any other location. Skipping it meant backing out
      // to the project list left the previous deep route stored, so the next
      // launch reopened that screen instead of the list you actually left the
      // app on. `main()` treats a saved '/' as "no restore needed", which is
      // already correct since '/' is the initial location.
      ref.read(settingsStoreProvider).saveLastRoute(state.uri.toString());
      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        pageBuilder: (context, state) => _rootPage(state, const _HomeRouter()),
      ),
      GoRoute(
        path: '/settings',
        pageBuilder: (context, state) =>
            _stackPage(state, const SettingsScreen()),
      ),
      GoRoute(
        path: '/servers/add',
        pageBuilder: (context, state) =>
            _stackPage(state, const ConnectionScreen()),
      ),
      GoRoute(
        path: '/servers/:id/edit',
        pageBuilder: (context, state) => _stackPage(
          state,
          ConnectionScreen(serverId: state.pathParameters['id']),
        ),
      ),
      GoRoute(
        path: '/session/:id',
        pageBuilder: (context, state) => _stackPage(
          state,
          ChatScreen(sessionId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/session/:id/files',
        pageBuilder: (context, state) => _stackPage(
          state,
          FilesScreen(sessionId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/workspace/:worktree/files',
        pageBuilder: (context, state) => _stackPage(
          state,
          FilesScreen(
            directory: Uri.decodeComponent(state.pathParameters['worktree']!),
          ),
        ),
      ),
      GoRoute(
        path: '/session/:id/diff',
        pageBuilder: (context, state) => _stackPage(
          state,
          DiffScreen(sessionId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/session/:id/terminal',
        pageBuilder: (context, state) => _stackPage(
          state,
          TerminalScreen(sessionId: state.pathParameters['id']!),
        ),
      ),
    ],
  );
}

class _ConnectionListenable extends ChangeNotifier {
  _ConnectionListenable(Ref ref) {
    ref.listen(serverManagerProvider, (prev, next) => notifyListeners());
  }
}

class _HomeRouter extends ConsumerWidget {
  const _HomeRouter();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configs = ref.watch(serverManagerProvider).configs;
    if (configs.isEmpty) return const WelcomeScreen();
    return const ProjectsScreen();
  }
}
