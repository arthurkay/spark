import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../core/api/providers.dart';
import '../../core/api/permission_provider.dart';
import '../../core/models/server_config.dart';
import '../../core/notifications/notification_service.dart';
import '../../core/storage/settings_provider.dart';
import '../../shared/widgets/app_toast.dart';
import '../connection/connection_screen.dart';
import '../luse/providers/luse_provider.dart';

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
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ConnectionScreen()),
    );
  }

  void _editServer(ServerConfig config) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ConnectionScreen(serverId: config.id),
      ),
    );
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
          const Gap(28),
          Text('Market Data').small.semiBold.muted,
          const Gap(10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.muted,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(LucideIcons.chartBar, size: 18),
                const Gap(10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('LuSE stock tracking'),
                      Text(
                        'Track Zambian stock market daily data',
                      ).xSmall.muted,
                    ],
                  ),
                ),
                const Gap(8),
                Switch(
                  value: ref.watch(luseEnabledProvider),
                  onChanged: (_) {
                    ref.read(luseEnabledProvider.notifier).toggle();
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
