import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'app/router.dart';
import 'app/theme.dart';
import 'core/api/luse_client.dart';
import 'core/api/permission_provider.dart';
import 'core/api/question_provider.dart';
import 'core/api/providers.dart';
import 'core/notifications/notification_service.dart';
import 'core/storage/luse_store.dart';
import 'core/storage/message_queue.dart';
import 'core/storage/settings_provider.dart';
import 'features/sessions/sessions_provider.dart';

final _routerProvider = Provider<GoRouter>((ref) => createRouter(ref));
Timer? _luseTimer;

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

  // Start periodic LuSE background fetch (every 30 minutes) if enabled
  final luseStore = LuseStore();
  if (await luseStore.isEnabled()) {
    _luseTimer = Timer.periodic(
      const Duration(minutes: 30),
      (_) => _fetchLuseAndNotify(),
    );
    _fetchLuseAndNotify();
  }

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

Future<void> _fetchLuseAndNotify() async {
  try {
    final store = LuseStore();
    if (!await store.isEnabled()) return;

    final client = LuseClient();
    final snapshot = await client.fetchStocks();
    if (snapshot.stocks.isEmpty) return;

    if (!await store.hasSnapshotChanged(snapshot)) return;

    final watchlist = await store.getWatchlist();
    final watchlistChanges = watchlist.map((symbol) {
      final stock =
          snapshot.stocks.where((s) => s.symbol == symbol).firstOrNull;
      if (stock == null) return '$symbol: N/A';
      final sign = stock.changePercent >= 0 ? '+' : '';
      return '$symbol: $sign${stock.changePercent.toStringAsFixed(2)}%';
    }).join(', ');

    await NotificationService.instance.showLuseSummary(
      gainers: snapshot.gainers,
      losers: snapshot.losers,
      unchanged: snapshot.unchanged,
      watchlistChanges: watchlistChanges,
    );
    await store.markSnapshotNotified(snapshot);
  } catch (_) {}
}
