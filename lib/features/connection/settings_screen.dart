import 'dart:ui' show PlatformDispatcher;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../core/api/providers.dart';
import '../../core/api/permission_provider.dart';
import '../../core/models/server_config.dart';
import '../../core/notifications/notification_service.dart';
import '../../core/storage/settings_provider.dart';
import '../../shared/widgets/app_toast.dart';
import '../../core/storage/settings_store.dart';
import '../chat/tts_cache.dart';
import '../chat/tts_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  static const _themeOptions = [
    ('system', 'System (adaptive)'),
    ('light', 'Light'),
    ('dark', 'Dark'),
  ];

  String _labelFor(String value) {
    return _themeOptions
        .firstWhere((o) => o.$1 == value, orElse: () => _themeOptions.first)
        .$2;
  }

  void _addServer() {
    context.push('/servers/add');
  }

  void _editServer(ServerConfig config) {
    context.push('/servers/${config.id}/edit');
  }

  void _confirmDelete(ServerConfig config) {
    openSheetOverlay(
      context: context,
      position: OverlayPosition.bottom,
      barrierDismissible: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(LucideIcons.trash2, color: Colors.red),
                  const Gap(8),
                  const Text('Delete server').h4,
                ],
              ),
              const Gap(12),
              Text(
                'Remove "${config.name}" from your saved servers?',
              ).muted,
              const Gap(20),
              DestructiveButton(
                onPressed: () {
                  closeSheet(sheetContext);
                  ref
                      .read(serverManagerProvider.notifier)
                      .removeServer(config.id);
                  showAppToast(context, title: 'Server removed');
                },
                child: const Text('Delete'),
              ),
              const Gap(8),
              OutlineButton(
                onPressed: () => closeSheet(sheetContext),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final managerState = ref.watch(serverManagerProvider);
    final themeMode = ref.watch(themeModeProvider);
    final configs = managerState.configs;
    final activeId = managerState.activeId;

    return Scaffold(
      headers: [
        AppBar(
          leading: [
            IconButton.ghost(
              icon: const Icon(LucideIcons.arrowLeft),
              onPressed: () => context.pop(),
            ),
          ],
          title: const Text('Settings'),
        ),
      ],
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            children: [
              Expanded(child: Text('Servers').small.semiBold.muted),
              GhostButton(
                density: ButtonDensity.compact,
                onPressed: _addServer,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.plus, size: 14),
                    Gap(4),
                    Text('Add'),
                  ],
                ),
              ),
            ],
          ),
          const Gap(10),
          if (configs.isEmpty)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.muted,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  'No servers saved yet.',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.mutedForeground),
                ),
              ),
            )
          else
            for (final config in configs)
              _ServerTile(
                config: config,
                isActive: config.id == activeId,
                onActivate: () => ref
                    .read(serverManagerProvider.notifier)
                    .setActive(config.id),
                onEdit: () => _editServer(config),
                onDelete: () => _confirmDelete(config),
              ),
          const Gap(28),
          Text('Appearance').small.semiBold.muted,
          const Gap(10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.muted,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(LucideIcons.paintbrush, size: 18),
                const Gap(10),
                Expanded(child: const Text('Theme')),
                const Gap(8),
                Select<String>(
                  value: themeMode,
                  onChanged: (value) {
                    if (value != null) {
                      ref.read(themeModeProvider.notifier).setMode(value);
                    }
                  },
                  itemBuilder: (context, value) => Text(_labelFor(value)),
                  popup: (context) => SelectPopup(
                    items: SelectItemList(
                      children: [
                        for (final option in _themeOptions)
                          SelectItem(
                            value: option.$1,
                            builder: (context) => Text(option.$2).small,
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Gap(28),
          Text('Narration').small.semiBold.muted,
          const Gap(10),
          const _VoiceTile(),
          const Gap(8),
          const _NarrationCacheTile(),
          const Gap(28),
          Text('Permissions').small.semiBold.muted,
          const Gap(10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.muted,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(LucideIcons.zap, size: 18),
                const Gap(10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Auto-approve permissions'),
                      Text(
                        'Automatically allow all permission requests',
                      ).xSmall.muted,
                    ],
                  ),
                ),
                const Gap(8),
                Switch(
                  value: ref.watch(autoApprovePermissionsProvider),
                  onChanged: (value) {
                    ref.read(autoApprovePermissionsProvider.notifier).state =
                        value;
                    if (value) {
                      ref.read(pendingPermissionsProvider.notifier).state =
                          const {};
                      NotificationService.instance.cancelPermission();
                    }
                  },
                ),
              ],
            ),
          ),
          const Gap(8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.muted,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(LucideIcons.panelLeft, size: 18),
                const Gap(10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Collapse file permissions'),
                      Text(
                        'Hide details for glob, read, edit, write until tapped',
                      ).xSmall.muted,
                    ],
                  ),
                ),
                const Gap(8),
                Switch(
                  value: ref.watch(collapseFilePermissionsProvider),
                  onChanged: (_) {
                    ref.read(collapseFilePermissionsProvider.notifier).toggle();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ServerTile extends StatelessWidget {
  const _ServerTile({
    required this.config,
    required this.isActive,
    required this.onActivate,
    required this.onEdit,
    required this.onDelete,
  });

  final ServerConfig config;
  final bool isActive;
  final VoidCallback onActivate;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isActive
            ? theme.colorScheme.primary.withAlpha(20)
            : theme.colorScheme.muted,
        borderRadius: BorderRadius.circular(12),
        border: isActive
            ? Border.all(color: theme.colorScheme.primary.withAlpha(60))
            : null,
      ),
      child: Row(
        children: [
          Icon(
            LucideIcons.server,
            size: 18,
            color: isActive
                ? theme.colorScheme.primary
                : theme.colorScheme.mutedForeground,
          ),
          const Gap(10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(config.name).medium,
                const Gap(2),
                Text(config.connection.baseUrl).small.muted,
              ],
            ),
          ),
          if (isActive)
            const SecondaryBadge(child: Text('active'))
          else
            GhostButton(
              density: ButtonDensity.compact,
              onPressed: onActivate,
              child: const Text('Switch'),
            ),
          const Gap(4),
          IconButton.ghost(
            icon: const Icon(LucideIcons.pencil, size: 16),
            onPressed: onEdit,
          ),
          IconButton.ghost(
            icon: const Icon(LucideIcons.trash2, size: 16),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

/// Shows what the narration cache holds and lets it be emptied.
///
/// Narrations are kept so replaying a message never repeats the model
/// round-trip. The cache is bounded (oldest-played evicted first), but it is
/// still the user's data, so it has to be visible and clearable.
class _NarrationCacheTile extends StatefulWidget {
  const _NarrationCacheTile();

  @override
  State<_NarrationCacheTile> createState() => _NarrationCacheTileState();
}

class _NarrationCacheTileState extends State<_NarrationCacheTile> {
  NarrationCacheStats? _stats;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final stats = await NarrationCache.instance.stats();
    if (mounted) setState(() => _stats = stats);
  }

  Future<void> _clear() async {
    await NarrationCache.instance.clear();
    if (!mounted) return;
    showAppToast(context, title: 'Narrations cleared');
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final stats = _stats;
    final count = stats?.count ?? 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.muted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(LucideIcons.audioLines, size: 18),
          const Gap(10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Saved narrations'),
                Text(
                  stats == null
                      ? 'Checking…'
                      : count == 0
                          ? 'Nothing saved yet'
                          : '$count message${count == 1 ? '' : 's'} · ${stats.sizeLabel}',
                ).xSmall.muted,
              ],
            ),
          ),
          const Gap(8),
          OutlineButton(
            size: ButtonSize.small,
            density: ButtonDensity.compact,
            onPressed: count == 0 ? null : _clear,
            child: const Text('Clear').small,
          ),
        ],
      ),
    );
  }
}

/// Chooses the narration voice from what the device's engine offers.
///
/// Selection persists via [SettingsStore] and is applied by the controller at
/// the start of every narration, so previews here can't leak into playback.
class _VoiceTile extends ConsumerStatefulWidget {
  const _VoiceTile();

  @override
  ConsumerState<_VoiceTile> createState() => _VoiceTileState();
}

class _VoiceTileState extends ConsumerState<_VoiceTile> {
  String? _currentLabel;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final voice = await SettingsStore().loadTtsVoice();
    if (mounted) {
      setState(() => _currentLabel =
          voice == null ? null : '${voice.name} (${voice.locale})');
    }
  }

  void _openPicker() {
    final controller = ref.read(ttsControllerProvider);
    openSheetOverlay(
      context: context,
      position: OverlayPosition.bottom,
      barrierDismissible: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            // Bounded: engines ship hundreds of voices across every language.
            constraints: const BoxConstraints(maxHeight: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(LucideIcons.audioLines, size: 18),
                    const Gap(8),
                    const Text('Narration voice').h4,
                  ],
                ),
                const Gap(4),
                Text('Tap to use a voice, play to hear a sample.').xSmall.muted,
                const Gap(12),
                Flexible(
                  child: FutureBuilder(
                    future: controller.availableVoices(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      // The device's language first, then other English
                      // variants, then the rest — an alphabetical list opens
                      // on Arabic with the useful voices pages away.
                      final lang = PlatformDispatcher
                          .instance.locale.languageCode
                          .toLowerCase();
                      int rank(TtsVoice v) {
                        final locale = v.locale.toLowerCase();
                        if (locale.startsWith(lang)) return 0;
                        if (locale.startsWith('en')) return 1;
                        return 2;
                      }

                      final voices = [...snapshot.data!]..sort((a, b) {
                          final byRank = rank(a).compareTo(rank(b));
                          if (byRank != 0) return byRank;
                          final byLocale = a.locale.compareTo(b.locale);
                          if (byLocale != 0) return byLocale;
                          return a.name.compareTo(b.name);
                        });
                      if (voices.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child:
                                const Text('No voices reported by the engine')
                                    .muted
                                    .small,
                          ),
                        );
                      }
                      return ListView.builder(
                        itemCount: voices.length + 1,
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            return _voiceRow(
                              sheetContext,
                              label: 'System default',
                              sublabel: 'Whatever the engine picks',
                              voice: null,
                            );
                          }
                          final voice = voices[index - 1];
                          return _voiceRow(
                            sheetContext,
                            label: voice.locale,
                            sublabel: voice.name,
                            voice: voice,
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _voiceRow(
    BuildContext sheetContext, {
    required String label,
    required String sublabel,
    required TtsVoice? voice,
  }) {
    final controller = ref.read(ttsControllerProvider);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        await controller.setVoiceSelection(voice);
        if (!sheetContext.mounted) return;
        closeSheet(sheetContext);
        if (!mounted) return;
        showAppToast(context,
            title: voice == null ? 'Using system voice' : 'Voice selected');
        await _refresh();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label).small.semiBold,
                  Text(sublabel).xSmall.muted,
                ],
              ),
            ),
            if (voice != null)
              IconButton.ghost(
                size: ButtonSize.small,
                density: ButtonDensity.compact,
                icon: const Icon(LucideIcons.play, size: 16),
                onPressed: () => controller.previewVoice(voice),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _openPicker,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.muted,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(LucideIcons.micVocal, size: 18),
            const Gap(10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Voice'),
                  Text(_currentLabel ?? 'System default').xSmall.muted,
                ],
              ),
            ),
            const Gap(8),
            const Icon(LucideIcons.chevronRight, size: 16).iconMutedForeground,
          ],
        ),
      ),
    );
  }
}
