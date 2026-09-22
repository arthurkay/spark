import 'dart:io';

import 'package:flutter/foundation.dart';

bool get isDesktopPlatform =>
    defaultTargetPlatform == TargetPlatform.windows ||
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.linux;

Future<String?> findOpencodeBinary() async {
  final fromPath = await _which();
  if (fromPath != null) return fromPath;
  for (final candidate in _candidatePaths()) {
    try {
      if (File(candidate).existsSync()) return candidate;
    } catch (_) {}
  }
  return null;
}

Future<String?> _which() async {
  try {
    final ProcessResult result;
    if (Platform.isWindows) {
      result = await Process.run('where', ['opencode'], runInShell: true);
    } else {
      result = await Process.run('which', ['opencode']);
    }
    if (result.exitCode != 0) return null;
    final lines = (result.stdout as String)
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) return null;
    final path = lines.first;
    if (File(path).existsSync()) return path;
    return null;
  } catch (_) {
    return null;
  }
}

List<String> _candidatePaths() {
  final home =
      Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '';
  if (home.isEmpty) return const [];
  if (Platform.isWindows) {
    return [
      '$home\\.opencode\\bin\\opencode.exe',
      '$home\\.opencode\\bin\\opencode.cmd',
      '$home\\scoop\\shims\\opencode.exe',
      r'C:\ProgramData\chocolatey\bin\opencode.exe',
      r'C:\ProgramData\chocolatey\bin\opencode.cmd',
    ];
  }
  return [
    '$home/.opencode/bin/opencode',
    '$home/.local/bin/opencode',
    '/usr/local/bin/opencode',
    '/opt/homebrew/bin/opencode',
    '/usr/bin/opencode',
  ];
}

Future<String?> opencodeVersion(String binary) async {
  try {
    final result = await Process.run(binary, [
      '--version',
    ], runInShell: Platform.isWindows).timeout(const Duration(seconds: 10));
    if (result.exitCode != 0) return null;
    final out = (result.stdout as String).trim();
    if (out.isEmpty) return null;
    return out.split('\n').first.trim();
  } catch (_) {
    return null;
  }
}

Future<bool> isOnPath(String command) async {
  try {
    final ProcessResult result;
    if (Platform.isWindows) {
      result = await Process.run('where', [command], runInShell: true);
    } else {
      result = await Process.run('which', [command]);
    }
    return result.exitCode == 0;
  } catch (_) {
    return false;
  }
}
