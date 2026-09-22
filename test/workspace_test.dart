import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spark/core/models/file_node.dart';
import 'package:spark/features/workspace/workspace_providers.dart';

FileNode _file(String path) {
  final name = path.split('/').last;
  return FileNode(name: name, path: path, isDirectory: false);
}

FileNode _dir(String path) {
  final name = path.split('/').last;
  return FileNode(name: name, path: path, isDirectory: true);
}

void main() {
  group('fuzzyMatchScore', () {
    test('empty query matches everything', () {
      expect(fuzzyMatchScore('', 'lib/main.dart'), 0);
    });

    test('exact substring scores positively', () {
      final score = fuzzyMatchScore('main', 'lib/main.dart');
      expect(score, isNotNull);
      expect(score, greaterThan(0));
    });

    test('subsequence match across path', () {
      expect(fuzzyMatchScore('mdart', 'lib/main.dart'), isNotNull);
    });

    test('non-matching query returns null', () {
      expect(fuzzyMatchScore('xyz', 'lib/main.dart'), isNull);
    });

    test('prefers basename hits over weak mid-path hits', () {
      final base = fuzzyMatchScore('main', 'main.dart')!;
      final mid = fuzzyMatchScore('main', 'lib/umainx')!;
      expect(base, greaterThan(mid));
    });
  });

  group('rankFiles', () {
    test('returns limited results for empty query', () {
      final files = [for (var i = 0; i < 80; i++) _file('f$i.dart')];
      expect(rankFiles('', files, limit: 10), hasLength(10));
    });

    test('ranks exact name matches first', () {
      final files = [
        _file('lib/util/main_helper.dart'),
        _file('lib/main.dart'),
        _file('tool/maintain.dart'),
      ];
      final ranked = rankFiles('main.dart', files);
      expect(ranked.first.path, 'lib/main.dart');
    });

    test('filters out non-matches', () {
      final files = [_file('lib/main.dart'), _file('lib/other.dart')];
      final ranked = rankFiles('zzz', files);
      expect(ranked, isEmpty);
    });
  });

  group('sortFileNodes', () {
    test('directories first then case-insensitive name', () {
      final nodes = [
        _file('b.dart'),
        _dir('Zeta'),
        _file('A.dart'),
        _dir('alpha'),
      ];
      final sorted = sortFileNodes(nodes);
      expect(sorted.map((n) => n.name).toList(), [
        'alpha',
        'Zeta',
        'A.dart',
        'b.dart',
      ]);
    });
  });

  group('WorkspaceController tabs', () {
    late ProviderContainer container;
    late WorkspaceController controller;

    setUp(() {
      container = ProviderContainer();
      addTearDown(container.dispose);
      controller = container.read(workspaceProvider.notifier);
    });

    test('open, activate, dirty, save, close', () {
      controller.ensureSession('ses_1');
      expect(controller.state.sessionId, 'ses_1');

      controller.openTab(
        path: 'lib/main.dart',
        name: 'main.dart',
        buffer: 'a',
        saved: 'a',
      );
      expect(controller.state.activePath, 'lib/main.dart');
      expect(controller.state.activeTab?.dirty, isFalse);

      controller.updateBuffer('lib/main.dart', 'b');
      expect(controller.state.activeTab?.dirty, isTrue);
      expect(controller.state.hasDirtyTabs, isTrue);

      controller.markSaved('lib/main.dart', 'b');
      expect(controller.state.activeTab?.dirty, isFalse);

      controller.openTab(
        path: 'lib/other.dart',
        name: 'other.dart',
        buffer: 'x',
        saved: 'x',
      );
      expect(controller.state.tabs, hasLength(2));
      expect(controller.state.activePath, 'lib/other.dart');

      controller.closeTab('lib/other.dart');
      expect(controller.state.activePath, 'lib/main.dart');
      expect(controller.state.tabs, hasLength(1));

      controller.closeTab('lib/main.dart');
      expect(controller.state.tabs, isEmpty);
      expect(controller.state.activePath, isNull);
    });

    test('ensureSession clears previous workspace', () {
      controller.ensureSession('ses_1');
      controller.openTab(path: 'a.dart', name: 'a.dart');
      controller.ensureSession('ses_2');
      expect(controller.state.tabs, isEmpty);
      expect(controller.state.sessionId, 'ses_2');
    });

    test('toggleDir adds and removes', () {
      controller.toggleDir('lib');
      expect(controller.state.expandedDirs, contains('lib'));
      controller.toggleDir('lib');
      expect(controller.state.expandedDirs, isNot(contains('lib')));
    });

    test(
      'crlf content is not dirty after editor line-ending normalization',
      () {
        controller.openTab(
          path: 'lib/main.dart',
          name: 'main.dart',
          buffer: 'a\r\nb\r\n',
          saved: 'a\r\nb\r\n',
        );
        expect(controller.state.activeTab?.dirty, isFalse);
        controller.updateBuffer('lib/main.dart', 'a\nb\n');
        expect(controller.state.activeTab?.dirty, isFalse);
        controller.updateBuffer('lib/main.dart', 'a\nb changed\n');
        expect(controller.state.activeTab?.dirty, isTrue);
      },
    );
  });
}
