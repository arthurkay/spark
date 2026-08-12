import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'app/router.dart';
import 'app/theme.dart';
import 'core/api/permission_provider.dart';
import 'core/api/question_provider.dart';
import 'core/api/providers.dart';
import 'core/notifications/notification_service.dart';
import 'core/storage/message_queue.dart';
import 'core/storage/settings_provider.dart';
import 'core/storage/settings_store.dart';
import 'features/sessions/sessions_provider.dart';
import 'features/chat/tts_overlay.dart';
import 'shared/widgets/offline_banner.dart';
import 'features/chat/tts_provider.dart';

String? _pendingRestoreRoute;

final _routerProvider = Provider<GoRouter>((ref) {
  return createRouter(ref);
});

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final container = ProviderContainer();
  await container.read(serverManagerProvider.notifier).restore();

  final savedRoute = await SettingsStore().loadLastRoute();
  if (savedRoute != null && savedRoute.isNotEmpty && savedRoute != '/') {
    _pendingRestoreRoute = savedRoute;
  }

  await NotificationService.instance.init(
    onTap: (permissionID, sessionID) {
      container.read(_routerProvider).push('/session/$sessionID');
    },
    onRouteTap: (route) {
      container.read(_routerProvider).push(route);
    },
  );
  container.read(permissionListenerProvider);
  container.read(questionListenerProvider);
  container.read(sessionLifecycleProvider);

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const OpencodeCompanionApp(),
    ),
  );
}

class OpencodeCompanionApp extends ConsumerStatefulWidget {
  const OpencodeCompanionApp({super.key});

  @override
  ConsumerState<OpencodeCompanionApp> createState() =>
      _OpencodeCompanionAppState();
}

class _OpencodeCompanionAppState extends ConsumerState<OpencodeCompanionApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final route = _pendingRestoreRoute;
      if (route != null) {
        _pendingRestoreRoute = null;
        final router = ref.read(_routerProvider);
        router.push(route);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        ref.read(appPausedProvider.notifier).state = false;
        ref.invalidate(eventStreamProvider);
        ref.invalidate(sessionsProvider);
        ref.invalidate(allSessionsProvider);
        _drainQueue();
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        ref.read(appPausedProvider.notifier).state = true;
        ref.read(ttsStateProvider.notifier).stop();
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        break;
    }
  }

  Future<void> _drainQueue() async {
    final client = ref.read(opencodeClientProvider);
    if (client == null) return;
    await MessageQueue().drain(client);
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(_routerProvider);
    final themeMode = themeModeFromString(ref.watch(themeModeProvider));

    final brightness = switch (themeMode) {
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
      ThemeMode.system => MediaQuery.platformBrightnessOf(context),
    };
    final overlayStyle = brightness == Brightness.dark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: ComponentTheme<FocusOutlineTheme>(
        data: FocusOutlineTheme(
          border: Border.all(
            color: Colors.transparent,
            width: 0,
          ),
          align: 0,
        ),
        child: ComponentTheme<TextFieldTheme>(
          data: TextFieldTheme(
            border: Border.all(color: Colors.transparent),
          ),
          child: ShadcnApp.router(
            title: 'Spark',
            debugShowCheckedModeBanner: false,
            theme: buildLightTheme(),
            darkTheme: buildDarkTheme(),
            themeMode: themeMode,
            routerConfig: router,
            // Above the router, so narration keeps playing — and stays
            // controllable — through every navigation. Only the player's own
            // pixels take hits; the rest of the stack stays transparent.
            builder: (context, child) => Stack(
              children: [
                child ?? const SizedBox.shrink(),
                const Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: OfflineBanner(),
                ),
                // Positioned.fill, not a bare child: a Stack sizes to its
                // non-positioned children, and once the processing scrim fades
                // to SizedBox.shrink the overlay would collapse to 0x0 — with
                // the player Positioned inside a zero-sized box, i.e. invisible.
                const Positioned.fill(child: TtsOverlay()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
