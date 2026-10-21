import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/chapter_metadata.dart';
import 'package:venera/foundation/chapter_metadata_session.dart';

void main() {
  List<String> catalog(int count) =>
      List.generate(count, (index) => 'chapter-${index + 1}');

  test('requests all 385 chapters at once, including offscreen chapters', () async {
    final ids = catalog(385);
    final calls = <List<String>>[];
    final results = <Map<String, ChapterMetadata>>[];
    final session = ChapterMetadataSession(
      load: (requested) async {
        calls.add(List.of(requested));
        return {
          for (final id in requested)
            id: const ChapterMetadata(likesCount: 0),
        };
      },
      onResult: results.add,
    );
    addTearDown(session.dispose);

    await session.request(ids);

    expect(calls, hasLength(1));
    expect(calls.single, orderedEquals(ids));
    expect(calls.single, hasLength(385));
    expect(results.single.keys, unorderedEquals(ids));
    expect(results.single['chapter-385']!.likesCount, 0);
  });

  test('deduplicates repeated IDs and requests during and after a flight', () async {
    final response = Completer<Map<String, ChapterMetadata>>();
    final calls = <List<String>>[];
    var deliveries = 0;
    final session = ChapterMetadataSession(
      load: (ids) {
        calls.add(List.of(ids));
        return response.future;
      },
      onResult: (_) => deliveries++,
    );
    addTearDown(session.dispose);

    final first = session.request(['a', 'b', 'a']);
    final repeated = session.request(['b', 'a']);
    expect(repeated, same(first));
    response.complete({'a': const ChapterMetadata(likesCount: 0)});
    await first;
    await repeated;
    // Empty/missing enrichment is not a reason to refresh in the same entry.
    // Repeated calls model rebuild/mode/resume callers, not widget events.
    for (var i = 0; i < 3; i++) {
      await session.request(['a', 'b']);
    }

    expect(calls, [orderedEquals(['a', 'b'])]);
    expect(deliveries, 1);
  });

  test('queues only new chapters and retains results across batches', () async {
    final firstResponse = Completer<Map<String, ChapterMetadata>>();
    final calls = <List<String>>[];
    final batches = <Set<String>>[];
    final accumulated = <String, ChapterMetadata>{};
    final session = ChapterMetadataSession(
      load: (ids) {
        calls.add(List.of(ids));
        if (calls.length == 1) {
          return firstResponse.future;
        }
        return Future.value({
          for (final id in ids)
            id: const ChapterMetadata(tencentUpdateTime: '2022-04-23'),
        });
      },
      onResult: (result) {
        batches.add(result.keys.toSet());
        // The production page owns the accumulator; session delivers deltas.
        accumulated.addAll(result);
      },
    );
    addTearDown(session.dispose);

    final flight = session.request(catalog(385));
    final queued = session.request([...catalog(385), 'chapter-386', 'chapter-386']);
    firstResponse.complete({
      for (final id in catalog(385))
        id: const ChapterMetadata(updateTime: '2026-01-17'),
    });
    await flight;
    await queued;
    await session.request([...catalog(386), 'chapter-387']);

    expect(calls, hasLength(3));
    expect(calls.first, orderedEquals(catalog(385)));
    expect(calls[1], ['chapter-386']);
    expect(calls[2], ['chapter-387']);
    expect(batches.map((batch) => batch.length), [385, 1, 1]);
    expect(accumulated, hasLength(387));
    expect(accumulated['chapter-1']!.updateTime, '2026-01-17');
    expect(accumulated['chapter-385']!.updateTime, '2026-01-17');
    expect(accumulated['chapter-386']!.tencentUpdateTime, '2022-04-23');
  });

  test('catalog result covers queued IDs without a duplicate request', () async {
    final response = Completer<Map<String, ChapterMetadata>>();
    final calls = <List<String>>[];
    final session = ChapterMetadataSession(
      load: (ids) {
        calls.add(List.of(ids));
        return response.future;
      },
      onResult: (_) {},
    );
    addTearDown(session.dispose);
    final flight = session.request(['a']);
    final queued = session.request(['a', 'b']);
    response.complete({
      'a': const ChapterMetadata(),
      'b': const ChapterMetadata(tencentUpdateTime: '2022-04-23'),
    });
    await flight;
    await queued;
    await session.request(['b']);
    expect(calls, [orderedEquals(['a'])]);
  });

  for (final synchronous in [false, true]) {
    test('retries a failed request once (synchronous: $synchronous)', () async {
      final calls = <List<String>>[];
      final results = <Map<String, ChapterMetadata>>[];
      final session = ChapterMetadataSession(
        load: (ids) {
          calls.add(List.of(ids));
          if (calls.length == 1) {
            if (synchronous) {
              throw StateError('source failed');
            }
            return Future.error(StateError('source failed'));
          }
          return Future.value({'a': const ChapterMetadata(likesCount: 7)});
        },
        onResult: results.add,
      );
      addTearDown(session.dispose);
      await session.request(['a', 'b']);
      await session.request(['a', 'b']);
      expect(calls, [orderedEquals(['a', 'b']), orderedEquals(['a', 'b'])]);
      expect(results, hasLength(1));
      expect(results.single['a']!.likesCount, 7);
    });
  }

  test('two failures stop retrying; a new chapter still gets its own request', () async {
    final calls = <List<String>>[];
    var deliveries = 0;
    final session = ChapterMetadataSession(
      load: (ids) async {
        calls.add(List.of(ids));
        throw StateError('offline');
      },
      onResult: (_) => deliveries++,
    );
    addTearDown(session.dispose);
    await session.request(['a']);
    await session.request(['a']);
    expect(calls, [orderedEquals(['a']), orderedEquals(['a'])]);
    await session.request(['a', 'b']);
    expect(calls, [
      orderedEquals(['a']), orderedEquals(['a']),
      orderedEquals(['b']), orderedEquals(['b']),
    ]);
    expect(deliveries, 0);
  });

  test('new entry reloads likes and retries dates missing in the prior entry', () async {
    final calls = <List<String>>[];
    final results = <Map<String, ChapterMetadata>>[];
    Future<Map<String, ChapterMetadata>> load(List<String> ids) async {
      calls.add(List.of(ids));
      return {
        'a': calls.length == 1
            ? const ChapterMetadata(likesCount: 0, likesSource: 'tencent')
            : const ChapterMetadata(
                updateTime: '2026-01-17', tencentUpdateTime: '2022-04-23',
                likesCount: 12, likesSource: 'tencent'),
      };
    }

    final first = ChapterMetadataSession(load: load, onResult: results.add);
    addTearDown(first.dispose);
    await first.request(['a', 'missing']);
    await first.request(['a', 'missing']);
    first.dispose();
    final second = ChapterMetadataSession(load: load, onResult: results.add);
    addTearDown(second.dispose);
    await second.request(['a', 'missing']);

    expect(calls, [orderedEquals(['a', 'missing']), orderedEquals(['a', 'missing'])]);
    expect(results, hasLength(2));
    expect(results.first['a']!.likesCount, 0);
    expect(results.first['a']!.tencentUpdateTime, isNull);
    expect(results.last['a']!.likesCount, 12);
    expect(results.last['a']!.tencentUpdateTime, '2022-04-23');
  });

  for (final fails in [false, true]) {
    test('dispose drops late ${fails ? 'failure' : 'success'} and queued work', () async {
      final response = Completer<Map<String, ChapterMetadata>>();
      final calls = <List<String>>[];
      final writes = <Map<String, ChapterMetadata>>[];
      final old = ChapterMetadataSession(
        load: (ids) {
          calls.add(List.of(ids));
          return response.future;
        },
        onResult: writes.add,
      );
      addTearDown(old.dispose);
      final flight = old.request(['a']);
      final queued = old.request(['a', 'b']);
      old.dispose();
      final current = ChapterMetadataSession(
        load: (_) async => {'a': const ChapterMetadata(likesCount: 9)},
        onResult: writes.add,
      );
      addTearDown(current.dispose);
      await current.request(['a']);
      if (fails) {
        response.completeError(StateError('late error'));
      } else {
        response.complete({'a': const ChapterMetadata(likesCount: 1)});
      }
      await flight;
      await queued;
      await old.request(['c']);
      expect(calls, [orderedEquals(['a'])]);
      expect(writes, hasLength(1));
      expect(writes.single['a']!.likesCount, 9);
    });
  }
}
