import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/pages/reader/reader.dart';
import 'package:venera/pages/reader/shader_image.dart';

class _CollisionProvider extends ImageProvider<_CollisionProvider> {
  const _CollisionProvider(this.id);
  final int id;

  @override
  Future<_CollisionProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  int get hashCode => 7;

  @override
  bool operator ==(Object other) =>
      other is _CollisionProvider && other.id == id;
}

Future<ui.Image> _image() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 2, 3), Paint());
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(2, 3);
  } finally {
    picture.dispose();
  }
}

void main() {
  var enabled = true;
  var strength = 1.0;
  late List<Completer<ui.Image?>> jobs;
  late List<ui.Image> sources;
  late List<double> producedStrengths;

  setUp(() {
    enabled = true;
    strength = 1;
    jobs = [];
    sources = [];
    producedStrengths = [];
    EnhancedComicImage.debugEnabled = () => enabled;
    EnhancedComicImage.debugParameters = () => (strength, 0.0, 0.0, 0.0);
    EnhancedComicImage.debugRunShader = (source) {
      sources.add(source);
      producedStrengths.add(strength);
      final job = Completer<ui.Image?>();
      jobs.add(job);
      return job.future;
    };
  });

  tearDown(() {
    EnhancedComicImage.debugEnabled = null;
    EnhancedComicImage.debugParameters = null;
    EnhancedComicImage.debugRunShader = null;
    ComicImage.clear();
  });

  Widget view(ui.Image source) => Directionality(
        textDirection: TextDirection.ltr,
        child: EnhancedComicImage(image: source),
      );

  testWidgets('same in-flight signature produces only one task', (tester) async {
    final original = (await tester.runAsync(_image))!;
    final result = (await tester.runAsync(_image))!;
    await tester.pumpWidget(view(original));
    for (var i = 0; i < 10; i++) {
      await tester.pumpWidget(view(original));
    }
    expect(jobs, hasLength(1));
    expect(identical(sources.single, original), isFalse);
    jobs.single.complete(result);
    await tester.pump();
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, same(result));
    expect(sources.single.debugDisposed, isTrue);
    await tester.pumpWidget(view(original));
    expect(jobs, hasLength(1));
    await tester.pumpWidget(const SizedBox());
    expect(result.debugDisposed, isTrue);
    expect(original.debugDisposed, isFalse);
    original.dispose();
  });

  testWidgets('coalesces changing signatures to the latest parameters',
      (tester) async {
    final original = (await tester.runAsync(_image))!;
    final stale = (await tester.runAsync(_image))!;
    final latest = (await tester.runAsync(_image))!;
    await tester.pumpWidget(view(original));
    strength = 2;
    await tester.pumpWidget(view(original));
    strength = 3;
    await tester.pumpWidget(view(original));
    expect(jobs, hasLength(1));
    jobs[0].complete(stale);
    await tester.pump();
    expect(stale.debugDisposed, isTrue);
    expect(jobs, hasLength(2));
    expect(producedStrengths, [1.0, 3.0]);
    jobs[1].complete(latest);
    await tester.pump();
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, same(latest));
    await tester.pumpWidget(const SizedBox());
    original.dispose();
  });

  testWidgets('image replacement never displays old page and runs latest source',
      (tester) async {
    final original = (await tester.runAsync(_image))!;
    final replacement = (await tester.runAsync(_image))!;
    final stale = (await tester.runAsync(_image))!;
    final result = (await tester.runAsync(_image))!;
    await tester.pumpWidget(view(original));
    await tester.pumpWidget(view(replacement));
    original.dispose();
    expect(jobs, hasLength(1));
    expect(tester.widget<RawImage>(find.byType(RawImage)).image,
        same(replacement));
    jobs[0].complete(stale);
    await tester.pump();
    expect(stale.debugDisposed, isTrue);
    expect(jobs, hasLength(2));
    expect(sources[1].isCloneOf(replacement), isTrue);
    jobs[1].complete(result);
    await tester.pump();
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, same(result));
    await tester.pumpWidget(const SizedBox());
    replacement.dispose();
  });

  testWidgets('dispose releases late output and owned source clone',
      (tester) async {
    final original = (await tester.runAsync(_image))!;
    final lateResult = (await tester.runAsync(_image))!;
    await tester.pumpWidget(view(original));
    await tester.pumpWidget(const SizedBox());
    // The parent may release its ImageInfo while GPU work is still pending.
    original.dispose();
    expect(sources.single.debugDisposed, isFalse);
    jobs.single.complete(lateResult);
    await tester.pump();
    expect(lateResult.debugDisposed, isTrue);
    expect(sources.single.debugDisposed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failure falls back and next rebuild can recover', (tester) async {
    final original = (await tester.runAsync(_image))!;
    final recovered = (await tester.runAsync(_image))!;
    await tester.pumpWidget(view(original));
    jobs.single.completeError(StateError('GPU failed'));
    await tester.pump();
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, same(original));
    expect(jobs, hasLength(1)); // No hot automatic retry loop.
    await tester.pumpWidget(view(original));
    expect(jobs, hasLength(2));
    jobs[1].complete(recovered);
    await tester.pump();
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, same(recovered));
    await tester.pumpWidget(const SizedBox());
    original.dispose();
  });

  testWidgets('disable invalidates work even after re-enable with same signature',
      (tester) async {
    final original = (await tester.runAsync(_image))!;
    final stale = (await tester.runAsync(_image))!;
    await tester.pumpWidget(view(original));
    enabled = false;
    await tester.pumpWidget(view(original));
    enabled = true;
    await tester.pumpWidget(view(original));
    jobs[0].complete(stale);
    await tester.pump();
    expect(stale.debugDisposed, isTrue);
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, same(original));
    expect(jobs, hasLength(2));
    enabled = false;
    await tester.pumpWidget(view(original));
    final disabledResult = (await tester.runAsync(_image))!;
    jobs[1].complete(disabledResult);
    await tester.pump();
    expect(disabledResult.debugDisposed, isTrue);
    expect(jobs, hasLength(2));
    await tester.pumpWidget(const SizedBox());
    original.dispose();
  });

  testWidgets('global GPU slots are bounded and disposed queued work never runs',
      (tester) async {
    final original = (await tester.runAsync(_image))!;
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Column(children: [
        for (var i = 0; i < 50; i++)
          EnhancedComicImage(key: ValueKey(i), image: original, height: 1),
      ]),
    ));
    expect(jobs, hasLength(2));
    expect(EnhancedComicImage.debugRunningCount, 2);
    expect(EnhancedComicImage.debugQueuedCount, 32);
    await tester.pumpWidget(const SizedBox());
    expect(EnhancedComicImage.debugQueuedCount, 0);
    for (final job in List.of(jobs)) {
      job.complete(null);
    }
    await tester.pump();
    expect(jobs, hasLength(2));
    for (final source in sources) {
      expect(source.debugDisposed, isTrue);
    }
    original.dispose();
  });

  test('size cache is bounded LRU and full keys survive hash collisions', () {
    ComicImage.clear();
    const first = _CollisionProvider(0);
    const second = _CollisionProvider(1);
    ComicImage.debugRememberSize(first, const Size(20, 30));
    ComicImage.debugRememberSize(second, const Size(40, 50));
    expect(ComicImage.debugCachedSize(first), const Size(20, 30));
    expect(ComicImage.debugCachedSize(second), const Size(40, 50));
    final capacity = ComicImage.debugSizeCacheCapacity;
    for (var i = 2; i < capacity; i++) {
      ComicImage.debugRememberSize(_CollisionProvider(i), const Size(2, 3));
    }
    // Touch first; second is now the least recently used entry.
    expect(ComicImage.debugCachedSize(first), const Size(20, 30));
    ComicImage.debugRememberSize(_CollisionProvider(capacity), const Size(7, 9));
    expect(ComicImage.debugCachedSize(second), isNull);
    expect(ComicImage.debugCachedSize(first), const Size(20, 30));
    for (var i = capacity + 1; i < capacity + 100; i++) {
      ComicImage.debugRememberSize(_CollisionProvider(i), const Size(2, 3));
    }
    expect(ComicImage.debugSizeCacheLength, capacity);
    ComicImage.clear();
    expect(ComicImage.debugSizeCacheLength, 0);
  });
}
