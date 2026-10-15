import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:venera/utils/image.dart' as reader;

// Needs the project's pinned flutter_qjs and lodepng native test libraries.
// No source/network/device credentials or mocked JavaScript runtime are used.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAADklEQVR4nGP4z8DwHwQBEPgD/U6VwW8AAAAASUVORK5CYII=',
);

Future<void> _expectPixels(Uint8List bytes) async {
  final decoded = await reader.Image.decodeImage(bytes);
  expect(decoded.width, 2);
  expect(decoded.height, 1);
  expect(decoded.getPixel(0, 0).r, 255);
  expect(decoded.getPixel(0, 0).g, 0);
  expect(decoded.getPixel(1, 0).r, 0);
  expect(decoded.getPixel(1, 0).g, 255);
}

void _expectClosed(List<String> events, {int? refs}) {
  expect(events.where((e) => e == 'runtime.ready'), hasLength(1));
  expect(events.where((e) => e == 'runtime.closed'), hasLength(1));
  expect(events.where((e) => e == 'port.closed'), hasLength(1));
  expect(events.where((e) => e == 'images.cleared'), hasLength(1));
  final owned = events.where((e) => e == 'ref.owned').length;
  expect(events.where((e) => e == 'ref.destroyed'), hasLength(owned));
  if (refs != null) expect(owned, refs);
  expect(events.indexOf('images.cleared'), lessThan(events.indexOf('runtime.closed')));
  expect(events.indexOf('runtime.closed'), lessThan(events.indexOf('port.closed')));
  if (owned > 0) {
    expect(events.lastIndexOf('ref.destroyed'), lessThan(events.indexOf('runtime.closed')));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('real PNG identity worker closes each runtime and preserves detached output', () async {
    final outputs = <Uint8List>[];
    for (var i = 0; i < 16; i++) {
      final events = <String>[];
      outputs.add(await reader.runImageScriptForTesting(
        _png,
        'function modifyImage(image) { return image; }',
        onLifetimeEvent: events.add,
      ));
      _expectClosed(events);
    }
    // Read outputs after all producing runtimes have already been closed.
    for (final bytes in outputs) {
      await _expectPixels(bytes);
    }
  });

  test('script completion functions are destroyed before strict runtime close', () async {
    for (var i = 0; i < 16; i++) {
      final events = <String>[];
      final bytes = await reader.runImageScriptForTesting(
        _png,
        '''
          function modifyImage(image) {
            let copy = image.copyRange(0, 0, image.width, image.height);
            let unused = Image.empty(2, 1);
            return copy;
          }
          ({first: () => 1, nested: [() => 2]});
        ''',
        onLifetimeEvent: events.add,
      );
      _expectClosed(events, refs: 2);
      await _expectPixels(bytes);
    }
  });

  test('throw and syntax errors still close runtime, images and port', () async {
    for (var i = 0; i < 16; i++) {
      for (final script in [
        'function modifyImage(image) { Image.empty(2, 1); throw new Error("fixture"); }',
        'function modifyImage(image) { throw new Error("fixture"); } modifyImage;',
        'function modifyImage(image) { throw {callback: () => 1}; }',
        'function modifyImage(image) { throw () => 1; }',
        'function modifyImage( {',
      ]) {
        final events = <String>[];
        await expectLater(
          reader.runImageScriptForTesting(_png, script, onLifetimeEvent: events.add),
          throwsA(isNotNull),
        );
        _expectClosed(events);
      }
    }
  });

  test('initialization parse errors also run cleanup', () async {
    final events = <String>[];
    await expectLater(
      reader.runImageScriptForTesting(
        _png,
        'function modifyImage(image) { return image; }',
        initScript: 'class Image {',
        onLifetimeEvent: events.add,
      ),
      throwsA(isNotNull),
    );
    _expectClosed(events);
  });

  test('production Isolate.run tasks survive failures and remain reusable', () async {
    for (var i = 0; i < 8; i++) {
      await expectLater(
        reader.modifyImageWithScript(_png, 'function modifyImage(image) { throw new Error("fixture"); }'),
        throwsA(isNotNull),
      );
      await _expectPixels(await reader.modifyImageWithScript(
        _png,
        'function modifyImage(image) { return image; }',
      ));
    }
  });

  test('decode disposes frame handles and rejects invalid input', () async {
    final oldCreate = ui.Image.onCreate;
    final oldDispose = ui.Image.onDispose;
    final live = <ui.Image>{};
    ui.Image.onCreate = live.add;
    ui.Image.onDispose = live.remove;
    try {
      for (var i = 0; i < 16; i++) {
        await _expectPixels(_png);
        expect(live, isEmpty);
        await expectLater(reader.Image.decodeImage(Uint8List.fromList([0, 1, 2])), throwsA(isNotNull));
        expect(live, isEmpty);
      }
    } finally {
      ui.Image.onCreate = oldCreate;
      ui.Image.onDispose = oldDispose;
    }
  });
}
