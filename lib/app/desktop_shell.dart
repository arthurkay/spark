import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../core/api/providers.dart';
import '../core/api/sse_client.dart';
import '../features/sessions/sessions_provider.dart';
import '../features/sessions/workspace_provider.dart';
import '../shared/widgets/workspace_utils.dart';
import 'motion.dart';

const double desktopBreakpoint = 1024;

String? sessionIdFromPath(String path) {
  return RegExp(r'^/session/([^/]+)').firstMatch(path)?.group(1);
}

class DesktopShell extends ConsumerStatefulWidget {
  const DesktopShell({super.key, required this.path, required this.child});

  final String path;
  final Widget child;

  @override
  ConsumerState<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends ConsumerState<DesktopShell> {
  final _expanded = <String>{};
  final _collapsed = <String>{};

  bool _isExpanded(WorkspaceGroup group, String? selectedSessionId) {
    final id = group.project.id;
    if (_collapsed.contains(id)) return false;
    if (_expanded.contains(id)) return true;
    return group.sessions.any((s) => s.id == selectedSessionId);
  }

  String? get _selectedSessionId => sessionIdFromPath(widget.path);

  String _groupLabel(WorkspaceGroup group) {
    if (group.project.isGlobal) return 'Global';
    if (group.project.id == '__other__') return 'Other';
    return group.project.worktree
            .split('/')
            .where((s) => s.isNotEmpty)
            .lastOrNull ??
        group.project.worktree;
  }

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final width = MediaQuery.sizeOf(context).width;
    if (width < desktopBreakpoint) return widget.child;

    final hasServers = ref.watch(serverManagerProvider).configs.isNotEmpty;
    if (!hasServers) return widget.child;
    if (RegExp(r'^/session/[^/]+/workspace$').hasMatch(widget.path)) {
      return widget.child;
    }

    ref.listen<AsyncValue<OpencodeEvent>>(eventStreamProvider, (prev, next) {
      final event = next.value;
      if (event == null) return;
      if (event.type == 'server.reconnected') {
        ref.read(sessionsRefreshProvider.notifier).state++;
        ref.read(projectsRefreshProvider.notifier).state++;
        ref.read(vcsRefreshProvider.notifier).state++;
      } else if (event.type == 'vcs.branch.updated') {
        ref.read(vcsRefreshProvider.notifier).state++;
      }
    });

    final sessionsAsync = ref.watch(allSessionsProvider);
    final projectsAsync = ref.watch(projectsProvider);
    final busyIds = ref.watch(sessionActivityProvider);
    final theme = Theme.of(context);
    final selectedSessionId = _selectedSessionId;

    final sessions = sessionsAsync.value ?? const [];
    final projects = projectsAsync.value ?? const [];
    final groups = buildWorkspaceGroups(sessions, projects);

    final sessionEntries = <Widget>[];
    for (final group in groups) {
      if (group.sessions.isEmpty) continue;
      final expanded = _isExpanded(group, selectedSessionId);
      sessionEntries.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
          child: GestureDetector(
            onTap: () => setState(() {
              if (expanded) {
                _expanded.remove(group.project.id);
                _collapsed.add(group.project.id);
              } else {
                _collapsed.remove(group.project.id);
                _expanded.add(group.project.id);
              }
            }),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              color: Colors.transparent,
              child: Row(
                children: [
                  AnimatedRotation(
                    turns: expanded ? 0.25 : 0,
                    duration: Motion.base,
                    child: Icon(
                      LucideIcons.chevronRight,
                      size: 13,
                      color: theme.colorScheme.mutedForeground,
                    ),
                  ),
                  const Gap(4),
                  Expanded(
                    child: Text(
                      _groupLabel(group),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ).xSmall.muted,
                  ),
                  Text('${group.sessions.length}').xSmall.muted,
                ],
              ),
            ),
          ),
        ),
      );
      if (!expanded) continue;
      for (final session in group.sessions) {
        final busy = busyIds.contains(session.id);
        final selected = session.id == selectedSessionId;
        final title = session.title?.trim().isNotEmpty == true
            ? session.title!
            : 'Untitled session';
        sessionEntries.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: GestureDetector(
              onTap: () => context.push('/session/${session.id}'),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                decoration: BoxDecoration(
                  color: selected
                      ? theme.colorScheme.secondary
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      busy
                          ? LucideIcons.loaderCircle
                          : LucideIcons.messagesSquare,
                      size: 15,
                      color: busy
                          ? theme.colorScheme.primary
                          : theme.colorScheme.mutedForeground,
                    ),
                    const Gap(8),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ).small,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }
    }

    final onHome = widget.path == '/' || widget.path.isEmpty;
    final onSettings = widget.path.startsWith('/settings');

    Widget navButton({
      required bool selected,
      required IconData icon,
      required String label,
      required VoidCallback onTap,
    }) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            decoration: BoxDecoration(
              color: selected
                  ? theme.colorScheme.secondary
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 15,
                  color: selected
                      ? theme.colorScheme.foreground
                      : theme.colorScheme.mutedForeground,
                ),
                const Gap(8),
                Text(label).small,
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        Container(
          width: 260,
          color: theme.colorScheme.card,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: Row(
                  children: [
                    SvgPicture.asset(
                      'assets/logo/spark.svg',
                      width: 22,
                      height: 22,
                      colorFilter: ColorFilter.mode(
                        theme.colorScheme.foreground,
                        BlendMode.srcIn,
                      ),
                    ),
                    const Gap(8),
                    const Text('SparkCode').h4,
                  ],
                ),
              ),
              navButton(
                selected: onHome,
                icon: LucideIcons.house,
                label: 'Projects',
                onTap: () => context.go('/'),
              ),
              navButton(
                selected: onSettings,
                icon: LucideIcons.settings,
                label: 'Settings',
                onTap: () => context.go('/settings'),
              ),
              Expanded(
                child: sessionEntries.isEmpty
                    ? const SizedBox.shrink()
                    : ListView(
                        padding: const EdgeInsets.only(bottom: 8),
                        children: sessionEntries,
                      ),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: PrimaryButton(
                  onPressed: () => context.push('/new-session'),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(LucideIcons.plus, size: 16),
                      Gap(8),
                      Text('New session'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Container(width: 1, color: theme.colorScheme.border),
        Expanded(child: widget.child),
      ],
    );
  }
}
