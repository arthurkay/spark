import 'dart:convert';

import '../../core/api/opencode_client.dart';
import 'pty_shell_runner.dart';

class FileOpsResult {
  const FileOpsResult(this.success, {this.error});
  final bool success;
  final String? error;
}

class FileOpsService {
  FileOpsService({required this.client});

  final OpencodeClient client;
  PtyShellRunner? _runner;

  PtyShellRunner get _pty {
    _runner ??= PtyShellRunner(client: client);
    return _runner!;
  }

  Future<FileOpsResult> createFile(String path,
      {String? directory, String? content}) async {
    try {
      if (content != null && content.isNotEmpty) {
        final base64Content = _base64Encode(content);
        final result = await _pty.run(
          'echo "$base64Content" | base64 -d > "$path"',
          directory: directory,
        );
        if (result.exitCode != 0) {
          return FileOpsResult(false,
              error: 'Failed to create file (exit code ${result.exitCode})');
        }
      } else {
        final result = await _pty.run('touch "$path"', directory: directory);
        if (result.exitCode != 0) {
          return FileOpsResult(false,
              error: 'Failed to create file (exit code ${result.exitCode})');
        }
      }
      return FileOpsResult(true);
    } catch (e) {
      return FileOpsResult(false, error: e.toString());
    }
  }

  Future<FileOpsResult> createDirectory(String path,
      {String? directory}) async {
    try {
      final result = await _pty.run('mkdir -p "$path"', directory: directory);
      if (result.exitCode != 0) {
        return FileOpsResult(false,
            error: 'Failed to create directory (exit code ${result.exitCode})');
      }
      return FileOpsResult(true);
    } catch (e) {
      return FileOpsResult(false, error: e.toString());
    }
  }

  Future<FileOpsResult> deleteFile(String path, {String? directory}) async {
    try {
      final result = await _pty.run('rm -f "$path"', directory: directory);
      if (result.exitCode != 0) {
        return FileOpsResult(false,
            error: 'Failed to delete file (exit code ${result.exitCode})');
      }
      return FileOpsResult(true);
    } catch (e) {
      return FileOpsResult(false, error: e.toString());
    }
  }

  Future<FileOpsResult> deleteDirectory(String path,
      {String? directory}) async {
    try {
      final result = await _pty.run('rm -rf "$path"', directory: directory);
      if (result.exitCode != 0) {
        return FileOpsResult(false,
            error: 'Failed to delete directory (exit code ${result.exitCode})');
      }
      return FileOpsResult(true);
    } catch (e) {
      return FileOpsResult(false, error: e.toString());
    }
  }

  Future<FileOpsResult> rename(String from, String to,
      {String? directory}) async {
    try {
      final result = await _pty.run('mv "$from" "$to"', directory: directory);
      if (result.exitCode != 0) {
        return FileOpsResult(false,
            error: 'Failed to rename (exit code ${result.exitCode})');
      }
      return FileOpsResult(true);
    } catch (e) {
      return FileOpsResult(false, error: e.toString());
    }
  }

  String _base64Encode(String text) {
    final bytes = text.codeUnits;
    return base64Encode(bytes);
  }
}
