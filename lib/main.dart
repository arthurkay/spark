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
import 'features/sessions/sessions_provider.dart';

final _routerProvider = Provider<GoRouter>((ref) => createRouter(ref));

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final container = ProviderContainer();
  await container.read(serverManagerProvider.notifier).restore();
  await NotificationService.instance.init(
    onTap: (permissionID, sessionID) {
      container.read(_routerProvider).go('/session/$sessionID');
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
          ),
        ),
      ),
    );
  }
}
