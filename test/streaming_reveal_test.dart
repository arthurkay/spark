import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:spark/shared/widgets/streaming_text.dart';

/// Walks the cursor from 0 to the end, returning every revealed prefix.
List<String> walkReveal(String text, {int catchUpTicks = 8}) {
  final steps = <String>[];
  var revealed = 0;
  var guard = 0;
  while (revealed < text.length) {
    final next = nextRevealIndex(text, revealed, catchUpTicks: catchUpTicks);
    expect(next, greaterThan(revealed), reason: 'reveal must make progress');
    revealed = next;
    steps.add(text.substring(0, revealed));
    if (++guard > 10000) fail('reveal did not terminate');
  }
  return steps;
}

void main() {
  group('nextRevealIndex', () {
    test('a fully revealed cursor stays at the end', () {
      expect(nextRevealIndex('hello world', 11), 11);
    });

    test('a cursor past the end clamps to the end', () {
      expect(nextRevealIndex('short', 99), 5);
    });

    test('empty text has nothing to reveal', () {
      expect(nextRevealIndex('', 0), 0);
    });

    test('a single word with no break reveals whole', () {
      expect(nextRevealIndex('hello', 0), 5);
    });

    test('never paints a partial word', () {
      const text =
          'The handler needs a null check before it dereferences the pointer.';
      for (final prefix in walkReveal(text)) {
        if (prefix.length == text.length) continue;
        // A prefix must end at a break, so no half-word is ever on screen.
        expect(prefix.endsWith(' ') || prefix.endsWith('\n'), isTrue,
            reason: 'partial word: "$prefix"');
      }
    });

    test('every step is a true prefix and the walk reassembles the text', () {
      const text = 'One two three four five six seven eight nine ten.';
      final steps = walkReveal(text);
      for (final step in steps) {
        expect(text.startsWith(step), isTrue);
      }
      expect(steps.last, text);
    });

    test('a large backlog advances further per tick than a small one', () {
      final long = 'word ' * 200;
      const short = 'word word word ';
      final bigStep = nextRevealIndex(long, 0);
      final smallStep = nextRevealIndex(short, 0);
      expect(bigStep, greaterThan(smallStep));
    });

    test('a burst catches up in a bounded number of ticks', () {
      final text = 'word ' * 200; // 1000 chars arriving at once
      expect(walkReveal(text).length, lessThan(40));
    });

    test('one long unbroken token still advances', () {
      final url = 'x' * 500;
      final next = nextRevealIndex(url, 0);
      expect(next, greaterThan(0));
      expect(next, lessThan(url.length));
    });

    test('newlines count as word breaks', () {
      const text = 'first line here\nsecond line here\nthird line here';
      for (final prefix in walkReveal(text)) {
        if (prefix.length == text.length) continue;
        expect(prefix.endsWith(' ') || prefix.endsWith('\n'), isTrue);
      }
    });

    test('a slower catch-up reveals in more steps', () {
      final text = 'word ' * 100;
      expect(
        walkReveal(text, catchUpTicks: 16).length,
        greaterThan(walkReveal(text, catchUpTicks: 4).length),
      );
    });
  });

  group('StreamingText widget', () {
    Widget host(String text, {required bool streaming}) => Directionality(
          textDirection: TextDirection.ltr,
          child: StreamingText(
            text: text,
            streaming: streaming,
            builder: (context, shown) => Text(shown),
          ),
        );

    String shownText(WidgetTester tester) =>
        tester.widget<Text>(find.byType(Text)).data!;

    testWidgets('a completed message renders whole immediately',
        (tester) async {
      const text = 'This turn already finished before it was built.';
      await tester.pumpWidget(host(text, streaming: false));
      expect(shownText(tester), text);
    });

    testWidgets('a live stream reveals progressively, then completes',
        (tester) async {
      const text = 'The handler needs a null check before it dereferences.';
      await tester.pumpWidget(host(text, streaming: true));
      // Nothing revealed on the first frame of a fresh stream.
      expect(shownText(tester), isEmpty);

      await tester.pump(const Duration(milliseconds: 50));
      final first = shownText(tester);
      expect(first, isNotEmpty);
      expect(first.length, lessThan(text.length),
          reason: 'must not dump the whole message at once');
      expect(text.startsWith(first), isTrue);

      await tester.pump(const Duration(milliseconds: 50));
      final second = shownText(tester);
      expect(second.length, greaterThan(first.length),
          reason: 'each tick must reveal more');

      // Runs to completion rather than stalling part-way.
      await tester.pump(const Duration(seconds: 3));
      expect(shownText(tester), text);
    });

    testWidgets('every revealed prefix ends on a word boundary',
        (tester) async {
      const text = 'one two three four five six seven eight nine ten eleven';
      await tester.pumpWidget(host(text, streaming: true));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        final shown = shownText(tester);
        if (shown.isEmpty || shown.length == text.length) continue;
        expect(shown.endsWith(' '), isTrue, reason: 'partial word: "$shown"');
      }
    });

    testWidgets('finishing the turn reveals the tail at once', (tester) async {
      const text = 'A fairly long sentence that has not been revealed yet.';
      await tester.pumpWidget(host(text, streaming: true));
      await tester.pump(const Duration(milliseconds: 50));
      expect(shownText(tester).length, lessThan(text.length));
      // The model stopped: show everything instead of trickling out the rest.
      await tester.pumpWidget(host(text, streaming: false));
      expect(shownText(tester), text);
    });

    testWidgets('a long message joined mid-stream is not replayed',
        (tester) async {
      final text = 'word ' * 100;
      await tester.pumpWidget(host(text, streaming: true));
      // Above the cold-start limit, so it renders whole on the first frame.
      expect(shownText(tester), text);
    });

    testWidgets('appended text keeps animating from where it was',
        (tester) async {
      await tester.pumpWidget(host('short start here', streaming: true));
      await tester.pump(const Duration(seconds: 2));
      expect(shownText(tester), 'short start here');
      await tester.pumpWidget(
          host('short start here plus more words', streaming: true));
      await tester.pump(const Duration(milliseconds: 50));
      final shown = shownText(tester);
      expect(shown.length, greaterThan('short start here'.length));
      expect(shown.length,
          lessThanOrEqualTo('short start here plus more words'.length));
    });
  });
}
