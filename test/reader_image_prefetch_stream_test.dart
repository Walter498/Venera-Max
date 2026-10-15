import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:venera/network/images.dart';

ImageDownloadProgress progress(int n) => ImageDownloadProgress(currentBytes: n, totalBytes: null);
ImageDownloadProgress image(int n) => ImageDownloadProgress(
  currentBytes: 1,
  totalBytes: 1,
  imageBytes: Uint8List.fromList([n]),
);

// Drain wrapper/controller microtasks without network, timers with long waits,
// or a second implementation of the production wrapper.
Future<void> drain() => Future<void>.delayed(Duration.zero);

void main() {
  tearDown(ImageDownloader.cancelAllLoadingImages);

  test('discarded prefetch handles never register or buffer progress', () async {
    final source = StreamController<ImageDownloadProgress>(sync: true);
    var starts = 0;
    Stream<ImageDownloadProgress> request() =>
        ImageDownloader.debugShareComicImage('prefetch', () {
          starts++;
          return source.stream;
        });

    final handles = List.generate(1000, (_) => request());
    expect(ImageDownloader.debugImageListenerCount, 0);
    await drain();
    for (var n = 0; n < 10000; n++) {
      source.add(progress(n));
    }
    expect(starts, 1);
    expect(ImageDownloader.debugImageListenerCount, 0);
    expect(ImageDownloader.debugLoadingImageCount, 1);

    final finalImage = image(7);
    source.add(finalImage);
    await source.close();
    await drain();
    expect(ImageDownloader.debugLoadingImageCount, 0);
    // All old handles can be subscribed after completion; each sees only the
    // single snapshot, never 10,000 historical progress events.
    for (final handle in [handles.first, handles[499], handles.last]) {
      expect(await handle.toList(), [same(finalImage)]);
    }
    expect(ImageDownloader.debugImageListenerCount, 0);
  });

  test('immediate image is not lost before first listen', () async {
    final finalImage = image(1);
    final stream = ImageDownloader.debugShareComicImage(
      'instant', () => Stream.value(finalImage),
    );
    expect(await stream.toList(), [same(finalImage)]);
    expect(ImageDownloader.debugLoadingImageCount, 0);
  });

  test('held handle replays latest image before completion without history',
      () async {
    final source = StreamController<ImageDownloadProgress>(sync: true);
    final held = ImageDownloader.debugShareComicImage('late-active', () => source.stream);
    await drain();
    source.add(image(1));
    final latest = image(2);
    source.add(latest);
    source.add(progress(500));
    final received = <ImageDownloadProgress>[];
    final subscription = held.listen(received.add);
    await drain();
    expect(received, [same(latest)]);
    expect(ImageDownloader.debugImageListenerCount, 1);
    await subscription.cancel();
    await source.close();
  });

  test('late failure is replayed with its stack and no progress history', () async {
    final source = StreamController<ImageDownloadProgress>(sync: true);
    final held = ImageDownloader.debugShareComicImage('failure', () => source.stream);
    await drain();
    source.add(progress(1));
    final error = StateError('controlled failure');
    final stack = StackTrace.current;
    source.addError(error, stack);
    await source.close();
    await drain();
    expect(ImageDownloader.debugLoadingImageCount, 0);
    final received = <ImageDownloadProgress>[];
    final errors = <Object>[];
    final stacks = <StackTrace>[];
    final done = Completer<void>();
    held.listen(received.add, onError: (Object e, StackTrace s) {
      errors.add(e);
      stacks.add(s);
    }, onDone: done.complete);
    await done.future;
    expect(received, isEmpty);
    expect(errors, [same(error)]);
    expect(stacks, [same(stack)]);
  });

  test('unsubscribe keeps disk prefetch alive and another consumer can join',
      () async {
    var upstreamCancelled = false;
    final source = StreamController<ImageDownloadProgress>(
      sync: true,
      onCancel: () { upstreamCancelled = true; },
    );
    final held = ImageDownloader.debugShareComicImage('leave', () => source.stream);
    final subscription = held.listen((_) {});
    await drain();
    expect(ImageDownloader.debugImageListenerCount, 1);
    await subscription.cancel();
    expect(ImageDownloader.debugImageListenerCount, 0);
    expect(upstreamCancelled, isFalse);
    expect(ImageDownloader.debugLoadingImageCount, 1);
    final finalImage = image(3);
    final joined = ImageDownloader.debugShareComicImage('leave', () {
      fail('joining an active prefetch must not create a second upstream');
    }).toList();
    source.add(finalImage);
    await source.close();
    expect(await joined, [same(finalImage)]);
    expect(ImageDownloader.debugLoadingImageCount, 0);
  });

  test('two actual subscribers share upstream; completion releases map entry',
      () async {
    var starts = 0;
    final source = StreamController<ImageDownloadProgress>(sync: true);
    Stream<ImageDownloadProgress> request() =>
        ImageDownloader.debugShareComicImage('dedup', () {
          starts++;
          return source.stream;
        });
    final first = request().toList();
    final second = request().toList();
    await drain();
    expect(starts, 1);
    expect(ImageDownloader.debugImageListenerCount, 2);
    final chunk = progress(5);
    final finalImage = image(5);
    source.add(chunk);
    source.add(finalImage);
    await source.close();
    expect(await first, [same(chunk), same(finalImage)]);
    expect(await second, [same(chunk), same(finalImage)]);
    expect(ImageDownloader.debugLoadingImageCount, 0);
    final next = image(6);
    expect(await ImageDownloader.debugShareComicImage(
      'dedup', () { starts++; return Stream.value(next); },
    ).toList(), [same(next)]);
    expect(starts, 2);
  });

  test('final snapshot and terminal error survive completion for a held handle',
      () async {
    final source = StreamController<ImageDownloadProgress>(sync: true);
    final held = ImageDownloader.debugShareComicImage(
      'snapshot-error', () => source.stream,
    );
    await drain();
    final cached = image(9);
    final error = StateError('refresh failed');
    source.add(cached);
    source.addError(error, StackTrace.current);
    await source.close();
    await drain();
    final data = <ImageDownloadProgress>[];
    final errors = <Object>[];
    final done = Completer<void>();
    held.listen(data.add, onError: (Object e) {
      errors.add(e);
    }, onDone: done.complete);
    await done.future;
    expect(data, [same(cached)]);
    expect(errors, [same(error)]);
    expect(ImageDownloader.debugLoadingImageCount, 0);
  });

  test('cancel before eager microtask does not start abandoned upstream',
      () async {
    var listened = false;
    final source = StreamController<ImageDownloadProgress>(
      onListen: () { listened = true; },
    );
    final held = ImageDownloader.debugShareComicImage(
      'cancel-before-start', () => source.stream,
    );
    ImageDownloader.cancelAllLoadingImages();
    await drain();
    expect(listened, isFalse);
    expect(await held.toList(), isEmpty);
    expect(ImageDownloader.debugLoadingImageCount, 0);
    // Never-listened single-subscription controllers need not complete close.
    unawaited(source.close());
  });

  test('explicit cancel stops upstream and closes consumers', () async {
    var cancelled = false;
    final source = StreamController<ImageDownloadProgress>(
      onCancel: () { cancelled = true; },
    );
    final received = ImageDownloader.debugShareComicImage(
      'cancel', () => source.stream,
    ).toList();
    await drain();
    ImageDownloader.cancelAllLoadingImages();
    await drain();
    expect(cancelled, isTrue);
    expect(await received, isEmpty);
    expect(ImageDownloader.debugLoadingImageCount, 0);
    await source.close();
  });
}
