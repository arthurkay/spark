import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/api/providers.dart';
import '../core/storage/settings_store.dart';
import '../features/chat/chat_screen.dart';
import '../features/chat/voice_mode_screen.dart';
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
/// Cupertino-style slide from right, but snappier (~200ms) than the platform
/// default (~400ms). Animates both the incoming and outgoing pages.
Page<void> _stackPage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: Motion.base,
    reverseTransitionDuration: Motion.fast,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final slide = Tween<Offset>(
        begin: const Offset(1, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Motion.standard));
      final reverseSlide = Tween<Offset>(
        begin: Offset.zero,
        end: const Offset(-0.3, 0),
      ).animate(CurvedAnimation(parent: secondaryAnimation, curve: Motion.standard));
      final fade = Tween<double>(
        begin: 0.0,
        end: 1.0,
      ).animate(CurvedAnimation(parent: animation, curve: Motion.standard));
      final reverseFade = Tween<double>(
        begin: 1.0,
        end: 0.6,
      ).animate(CurvedAnimation(parent: secondaryAnimation, curve: Motion.standard));

      return AnimatedBuilder(
        animation: Listenable.merge([animation, secondaryAnimation]),
        builder: (context, _) {
          return SlideTransition(
            position: reverseSlide,
            child: FadeTransition(
              opacity: reverseFade,
              child: SlideTransition(
                position: slide,
                child: FadeTransition(
                  opacity: fade,
                  child: child,
                ),
              ),
            ),
          );
        },
      );
    },
  );
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
        path: '/session/:id/voice',
        pageBuilder: (context, state) => _stackPage(
          state,
          VoiceModeScreen(sessionId: state.pathParameters['id']!),
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
