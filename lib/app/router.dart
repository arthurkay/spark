import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/api/providers.dart';
import '../features/chat/chat_screen.dart';
import '../features/connection/settings_screen.dart';
import '../features/files/diff_screen.dart';
import '../features/files/files_screen.dart';
import '../features/luse/screens/luse_screen.dart';
import '../features/luse/screens/fundamentals_screen.dart';
import '../features/sessions/sessions_screen.dart';

GoRouter createRouter(Ref ref) {
  return GoRouter(
    initialLocation: '/',
    refreshListenable: _ConnectionListenable(ref),
    routes: [
      GoRoute(
        path: '/',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const ProjectsScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      ),
      GoRoute(
        path: '/settings',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const SettingsScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            );
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.3, 0),
                end: Offset.zero,
              ).animate(curved),
              child: FadeTransition(opacity: curved, child: child),
            );
          },
        ),
      ),
      GoRoute(
        path: '/session/:id',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: ChatScreen(sessionId: state.pathParameters['id']!),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            );
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(1, 0),
                end: Offset.zero,
              ).animate(curved),
              child: FadeTransition(opacity: curved, child: child),
            );
          },
        ),
      ),
      GoRoute(
        path: '/session/:id/files',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: FilesScreen(sessionId: state.pathParameters['id']!),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            );
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(1, 0),
                end: Offset.zero,
              ).animate(curved),
              child: FadeTransition(opacity: curved, child: child),
            );
          },
        ),
      ),
      GoRoute(
        path: '/workspace/:worktree/files',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: FilesScreen(
            directory: Uri.decodeComponent(state.pathParameters['worktree']!),
          ),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            );
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(1, 0),
                end: Offset.zero,
              ).animate(curved),
              child: FadeTransition(opacity: curved, child: child),
            );
          },
        ),
      ),
      GoRoute(
        path: '/session/:id/diff',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: DiffScreen(sessionId: state.pathParameters['id']!),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            );
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(1, 0),
                end: Offset.zero,
              ).animate(curved),
              child: FadeTransition(opacity: curved, child: child),
            );
          },
        ),
      ),
      GoRoute(
        path: '/luse',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const LuseScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            );
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(1, 0),
                end: Offset.zero,
              ).animate(curved),
              child: FadeTransition(opacity: curved, child: child),
            );
          },
        ),
      ),
      GoRoute(
        path: '/luse/fundamentals',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const FundamentalsScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            );
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(1, 0),
                end: Offset.zero,
              ).animate(curved),
              child: FadeTransition(opacity: curved, child: child),
            );
          },
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
