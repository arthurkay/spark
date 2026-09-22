import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/opencode_client.dart';
import '../../core/api/providers.dart';
import '../../core/models/file_node.dart';

String normalizeLineEndings(String text) =>
    text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

class WorkspaceTab {
  const WorkspaceTab({
    required this.path,
    required this.name,
    required this.buffer,
    required this.saved,
    this.isBinary = false,
    this.loading = false,
    this.error,
  });

  final String path;
  final String name;
  final String buffer;
  final String saved;
  final bool isBinary;
  final bool loading;
  final String? error;

  bool get dirty =>
      !isBinary && normalizeLineEndings(buffer) != normalizeLineEndings(saved);

  WorkspaceTab copyWith({
    String? buffer,
    String? saved,
    bool? isBinary,
    bool? loading,
    String? error,
    bool clearError = false,
  }) {
    return WorkspaceTab(
      path: path,
      name: name,
      buffer: buffer ?? this.buffer,
      saved: saved ?? this.saved,
      isBinary: isBinary ?? this.isBinary,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

@immutable
class WorkspaceState {
  const WorkspaceState({
    this.sessionId,
    this.tabs = const [],
    this.activePath,
    this.expandedDirs = const {},
  });

  final String? sessionId;
  final List<WorkspaceTab> tabs;
  final String? activePath;
  final Set<String> expandedDirs;

  WorkspaceTab? get activeTab {
    final path = activePath;
    if (path == null) return null;
    for (final tab in tabs) {
      if (tab.path == path) return tab;
    }
    return null;
  }

  bool get hasDirtyTabs => tabs.any((t) => t.dirty);

  WorkspaceState copyWith({
    String? sessionId,
    List<WorkspaceTab>? tabs,
    String? activePath,
    Set<String>? expandedDirs,
    bool clearActivePath = false,
  }) {
    return WorkspaceState(
      sessionId: sessionId ?? this.sessionId,
      tabs: tabs ?? this.tabs,
      activePath: clearActivePath ? null : (activePath ?? this.activePath),
      expandedDirs: expandedDirs ?? this.expandedDirs,
    );
  }
}

class WorkspaceController extends Notifier<WorkspaceState> {
  @override
  WorkspaceState build() => const WorkspaceState();

  void ensureSession(String sessionId) {
    if (state.sessionId == sessionId) return;
    state = WorkspaceState(sessionId: sessionId);
  }

  void openTab({
    required String path,
    required String name,
    String buffer = '',
    String? saved,
    bool isBinary = false,
    bool loading = false,
    String? error,
  }) {
    final existing = _tabAt(path);
    if (existing != null) {
      _replaceTab(
        existing,
        existing.copyWith(
          buffer: buffer.isEmpty ? existing.buffer : buffer,
          saved: saved ?? existing.saved,
          isBinary: isBinary,
          loading: loading,
          error: error,
          clearError: error == null,
        ),
      );
      state = state.copyWith(activePath: path);
      return;
    }
    final tab = WorkspaceTab(
      path: path,
      name: name,
      buffer: buffer,
      saved: saved ?? buffer,
      isBinary: isBinary,
      loading: loading,
      error: error,
    );
    state = state.copyWith(tabs: [...state.tabs, tab], activePath: path);
  }

  void setActive(String path) {
    if (_tabAt(path) == null) return;
    state = state.copyWith(activePath: path);
  }

  void closeTab(String path) {
    final tabs = [...state.tabs]..removeWhere((t) => t.path == path);
    String? active = state.activePath;
    if (active == path) {
      if (tabs.isEmpty) {
        active = null;
      } else {
        final index = state.tabs.indexWhere((t) => t.path == path);
        final next = tabs[index < tabs.length ? index : tabs.length - 1];
        active = next.path;
      }
    }
    state = state.copyWith(
      tabs: tabs,
      activePath: active,
      clearActivePath: active == null,
    );
  }

  void updateBuffer(String path, String content) {
    final tab = _tabAt(path);
    if (tab == null || tab.buffer == content) return;
    _replaceTab(tab, tab.copyWith(buffer: content));
  }

  void markSaved(String path, String content) {
    final tab = _tabAt(path);
    if (tab == null) return;
    _replaceTab(
      tab,
      tab.copyWith(buffer: content, saved: content, clearError: true),
    );
  }

  void setLoading(String path, bool loading) {
    final tab = _tabAt(path);
    if (tab == null || tab.loading == loading) return;
    _replaceTab(tab, tab.copyWith(loading: loading));
  }

  void setError(String path, String message) {
    final tab = _tabAt(path);
    if (tab == null) return;
    _replaceTab(tab, tab.copyWith(error: message, loading: false));
  }

  void toggleDir(String path) {
    final expanded = {...state.expandedDirs};
    if (!expanded.add(path)) expanded.remove(path);
    state = state.copyWith(expandedDirs: expanded);
  }

  WorkspaceTab? _tabAt(String path) {
    for (final tab in state.tabs) {
      if (tab.path == path) return tab;
    }
    return null;
  }

  void _replaceTab(WorkspaceTab existing, WorkspaceTab next) {
    if (identical(existing, next)) return;
    final tabs = [
      for (final tab in state.tabs) identical(tab, existing) ? next : tab,
    ];
    state = state.copyWith(tabs: tabs);
  }
}

final workspaceProvider = NotifierProvider<WorkspaceController, WorkspaceState>(
  WorkspaceController.new,
);

@immutable
class FileListQuery {
  const FileListQuery(this.path, this.directory);

  final String path;
  final String? directory;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FileListQuery &&
          other.path == path &&
          other.directory == directory;

  @override
  int get hashCode => Object.hash(path, directory);
}

final fileListProvider = FutureProvider.autoDispose
    .family<List<FileNode>, FileListQuery>((ref, query) async {
      final client = ref.watch(opencodeClientProvider);
      if (client == null) return const [];
      final nodes = await client.listFiles(
        query.path,
        directory: query.directory,
      );
      return sortFileNodes(nodes);
    });

List<FileNode> sortFileNodes(List<FileNode> nodes) {
  final sorted = [...nodes];
  sorted.sort((a, b) {
    if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return sorted;
}

const defaultSkipDirs = {
  '.git',
  '.hg',
  '.svn',
  'node_modules',
  '.dart_tool',
  'build',
  '.idea',
  '.vscode',
  'Pods',
  'DerivedData',
  '.gradle',
  'dist',
  'coverage',
};

Future<List<FileNode>> collectFiles(
  OpencodeClient client, {
  String? directory,
  String path = '',
  int maxFiles = 500,
  int maxDepth = 12,
  Set<String> skipDirs = defaultSkipDirs,
}) async {
  final out = <FileNode>[];
  final queue = <(String path, int depth)>[(path, 0)];
  final seen = <String>{};

  while (queue.isNotEmpty && out.length < maxFiles) {
    final (current, depth) = queue.removeAt(0);
    if (!seen.add(current) || depth > maxDepth) continue;
    final List<FileNode> nodes;
    try {
      nodes = await client.listFiles(current, directory: directory);
    } catch (_) {
      continue;
    }
    for (final node in sortFileNodes(nodes)) {
      if (out.length >= maxFiles) break;
      if (node.isDirectory) {
        final name = node.name;
        if (skipDirs.contains(name)) continue;
        queue.add((node.path, depth + 1));
      } else {
        out.add(node);
      }
    }
  }
  return out;
}

@visibleForTesting
int? fuzzyMatchScore(String query, String target) {
  if (query.isEmpty) return 0;
  final q = query.toLowerCase();
  final t = target.toLowerCase();
  if (q.length > t.length) return null;

  var score = 0;
  var qi = 0;
  var lastMatch = -2;
  for (var ti = 0; ti < t.length && qi < q.length; ti++) {
    if (t[ti] != q[qi]) continue;
    score += 1;
    if (ti == lastMatch + 1) score += 3;
    if (ti == 0 ||
        t[ti - 1] == '/' ||
        t[ti - 1] == '_' ||
        t[ti - 1] == '-' ||
        t[ti - 1] == '.') {
      score += 4;
    }
    lastMatch = ti;
    qi++;
  }
  if (qi < q.length) return null;
  if (lastMatch == t.length - 1) score += 2;
  score += (t.length - q.length).clamp(0, 20) ~/ 4;
  return score;
}

List<FileNode> rankFiles(String query, List<FileNode> files, {int limit = 50}) {
  if (query.trim().isEmpty) {
    return files.take(limit).toList();
  }
  final scored = <(int, FileNode)>[];
  for (final file in files) {
    final score =
        fuzzyMatchScore(query, file.path) ?? fuzzyMatchScore(query, file.name);
    if (score != null) scored.add((score, file));
  }
  scored.sort((a, b) {
    if (a.$1 != b.$1) return b.$1.compareTo(a.$1);
    return a.$2.path.length.compareTo(b.$2.path.length);
  });
  return scored.take(limit).map((e) => e.$2).toList();
}
