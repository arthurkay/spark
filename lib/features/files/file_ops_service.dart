import '../../core/api/opencode_client.dart';
import 'file_write_service.dart';
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
        // Content goes through PtyFileWriter, which streams the payload as
        // stdin of a running `base64 -d`. A single `echo "<base64>"` command
        // line is truncated by the TTY past ~4 KB and mangles non-ASCII text.
        await PtyFileWriter(client: client)
            .write(path: path, directory: directory, content: content);
      } else {
        final result =
            await _pty.run('touch ${shellQuote(path)}', directory: directory);
        if (result.exitCode != 0) {
          return FileOpsResult(false,
              error: 'Failed to create file (exit code ${result.exitCode})');
        }
      }
      return FileOpsResult(true);
    } on FileWriteException catch (e) {
      return FileOpsResult(false, error: e.message);
    } catch (e) {
      return FileOpsResult(false, error: e.toString());
    }
  }

  Future<FileOpsResult> createDirectory(String path,
      {String? directory}) async {
    try {
      final result =
          await _pty.run('mkdir -p ${shellQuote(path)}', directory: directory);
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
      final result =
          await _pty.run('rm -f ${shellQuote(path)}', directory: directory);
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
      final result =
          await _pty.run('rm -rf ${shellQuote(path)}', directory: directory);
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
      final result = await _pty.run('mv ${shellQuote(from)} ${shellQuote(to)}',
          directory: directory);
      if (result.exitCode != 0) {
        return FileOpsResult(false,
            error: 'Failed to rename (exit code ${result.exitCode})');
      }
      return FileOpsResult(true);
    } catch (e) {
      return FileOpsResult(false, error: e.toString());
    }
  }
}
