import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spark/features/local_server/local_server_provider.dart';
import 'package:spark/features/local_server/opencode_installer.dart';

void main() {
  group('installCommandFor', () {
    test('unix uses official install script', () {
      final command = installCommandFor(
        TargetPlatform.linux,
        npmAvailable: false,
      );
      expect(command, isNotNull);
      expect(command!.executable, 'bash');
      expect(command.args.first, '-lc');
      expect(
        command.args[1],
        contains('curl -fsSL https://opencode.ai/install'),
      );
    });

    test('macos uses official install script', () {
      final command = installCommandFor(
        TargetPlatform.macOS,
        npmAvailable: true,
      );
      expect(command!.executable, 'bash');
      expect(command.args[1], contains('opencode.ai/install'));
    });

    test('windows prefers npm', () {
      final command = installCommandFor(
        TargetPlatform.windows,
        npmAvailable: true,
      );
      expect(command!.executable, 'npm');
      expect(command.args, ['install', '-g', 'opencode-ai']);
    });

    test('windows without npm has no silent install', () {
      final command = installCommandFor(
        TargetPlatform.windows,
        npmAvailable: false,
      );
      expect(command, isNull);
    });
  });

  group('upgradeCommandFor', () {
    test('runs opencode upgrade against the binary', () {
      final command = upgradeCommandFor('/usr/bin/opencode');
      expect(command.executable, '/usr/bin/opencode');
      expect(command.args, ['upgrade']);
    });
  });

  group('findFreePort', () {
    test('returns a free loopback port at or above start', () async {
      final port = await findFreePort(start: 45123, attempts: 5);
      expect(port, isNotNull);
      expect(port, greaterThanOrEqualTo(45123));
      expect(port, lessThan(45128));
    });
  });

  group('ServerLogBuffer', () {
    test('splits lines and drops empties', () {
      final buffer = ServerLogBuffer();
      buffer.add('hello\n\nworld\n');
      expect(buffer.snapshot(), ['hello', 'world']);
    });

    test('bounds to max keeping newest', () {
      final buffer = ServerLogBuffer(max: 3);
      for (var i = 0; i < 10; i++) {
        buffer.add('line$i');
      }
      expect(buffer.snapshot(), ['line7', 'line8', 'line9']);
    });
  });

  group('LocalServerState', () {
    test('statusLabel reflects state', () {
      const noBinary = LocalServerState();
      expect(noBinary.statusLabel, 'Not installed');

      const withBinary = LocalServerState(binaryPath: '/usr/bin/opencode');
      expect(withBinary.statusLabel, 'Stopped');

      const locating = LocalServerState(status: LocalServerStatus.locating);
      expect(locating.statusLabel, 'Looking for opencode…');

      const missing = LocalServerState(status: LocalServerStatus.missing);
      expect(missing.statusLabel, 'opencode not found');

      const starting = LocalServerState(status: LocalServerStatus.starting);
      expect(starting.statusLabel, 'Starting local server…');

      const healthy = LocalServerState(
        status: LocalServerStatus.healthy,
        port: 4096,
      );
      expect(healthy.statusLabel, 'Running on 127.0.0.1:4096');

      const failed = LocalServerState(
        status: LocalServerStatus.failed,
        error: 'boom',
      );
      expect(failed.statusLabel, 'boom');
    });

    test('copyWith clear flags null out fields', () {
      const state = LocalServerState(
        binaryPath: '/bin/opencode',
        version: '1.0.0',
        port: 4096,
        error: 'x',
      );
      final cleared = state.copyWith(
        clearBinary: true,
        clearVersion: true,
        clearPort: true,
        clearError: true,
      );
      expect(cleared.binaryPath, isNull);
      expect(cleared.version, isNull);
      expect(cleared.port, isNull);
      expect(cleared.error, isNull);
      expect(cleared.status, state.status);
    });

    test('isRunning covers starting and healthy', () {
      expect(
        const LocalServerState(status: LocalServerStatus.starting).isRunning,
        isTrue,
      );
      expect(
        const LocalServerState(status: LocalServerStatus.healthy).isRunning,
        isTrue,
      );
      expect(
        const LocalServerState(status: LocalServerStatus.idle).isRunning,
        isFalse,
      );
      expect(
        const LocalServerState(status: LocalServerStatus.failed).isRunning,
        isFalse,
      );
    });
  });
}
