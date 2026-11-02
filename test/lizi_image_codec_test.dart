import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_qjs/flutter_qjs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/network/images.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final evidence = <Map<String, dynamic>>[];
  final cases = <String, Map<String, dynamic>>{
    '278': {
      'url': 'https://t1.imge.store/101/62539/58958c1c5505bf45/fd7d13b4/1.webp',
      'sha': '4f058a996c36be0a6545ad36ff467901c981f3b817c6777361a90cf03df9350b',
      'width': 690, 'height': 690,
    },
    '279': {
      'url': 'https://t1.imge.store/102/62539/60840ab2ab/QUNoz/1.webp',
      'sha': '2cab2929412223e349cde11acbbfff1bef07a442ae5301c273055682bdd0f24e',
      'width': 690, 'height': 690,
    },
    'ai34': {
      'url': 'https://t1.imge.store/101/75959/mhx_7546393/1.webp',
      'sha': '3070d2fd955a7561bf714bca28649b54838cb9a6e22975cc40b659013a9120ae',
      'width': 690, 'height': 2000,
    },
    'dafeng': {
      'url': 'https://t1.imge.store/102/59797/78c979ae67f479a3/c101bd00/13.webp',
      'sha': '358d5779ae2517785807dbc5c21cedb1124f45fe9aef1126142b9be5dfb29cbb',
      'width': 1200, 'height': 1669,
    },
    'legacy': {
      'url': 'https://media.imgo.buzz/3/62539/3890284/66.jpg',
      'sha': '49b3d73f299b6f5f197c57947f7380779d9c2f7e24956454882e3ab0fa0e7b29',
      'width': 690, 'height': 2000,
    },
  };

  tearDownAll(() async {
    final out = Directory('build/lizi-codec-evidence');
    await out.create(recursive: true);
    await File('${out.path}/native-results.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert(evidence),
    );
  });

  for (final thumbnail in [false, true]) {
    for (final entry in cases.entries) {
      test('${thumbnail ? 'thumbnail' : 'reader'} ${entry.key} real bytes through native QJS and Flutter codec', () async {
        final js = FlutterQjs();
        unawaited(js.dispatch());
        JSInvokable? configFunction;
        final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
        try {
          js.evaluate('''
            class ComicSource {
              loadSetting(k) {
                if (this.settings && this.settings[k]) return this.settings[k].default;
                throw new Error('Unknown setting '+k);
              }
              loadData(k) { return null; }
              saveData(k,v) {}
              deleteData(k) {}
            }
          ''');
          js.evaluate(await File('test/fixtures/lizimh_image_codec_release.js').readAsString());
          js.evaluate('''
            globalThis.src = new Lizimh();
            Lizimh.lines = [{name:'legacy',url:'https://media.imgo.buzz'}];
          ''');
          configFunction = js.evaluate(thumbnail
              ? '(url)=>src.comic.onThumbnailLoad(url)'
              : '(url)=>src.comic.onImageLoad(url,"62539","279")') as JSInvokable;
          final rawUrl = entry.value['url'] as String;
          final versionedKey = '$rawUrl#__lizi_decoder=v1';
          dynamic config = configFunction([versionedKey]);
          if (config is Future) config = await config;
          expect(config, isA<Map>());
          expect(config['url'], rawUrl, reason: 'Cache suffix must not change real network URL');
          Uint8List? output;
          String? inputSha;
          await for (final progress in ImageDownloader.debugLoadImageTask(
            config: () async => Map<String, dynamic>.from(config as Map),
            thumbnail: thumbnail,
            request: (cfg) async {
              final req = await client.getUrl(Uri.parse(cfg['url'] as String));
              req.headers.set('User-Agent', 'Mozilla/5.0');
              req.headers.set('Accept-Encoding', 'identity');
              final response = await req.close().timeout(const Duration(seconds: 30));
              expect(response.statusCode, 200);
              final builder = BytesBuilder(copy: false);
              await for (final chunk in response) { builder.add(chunk); }
              final bytes = builder.takeBytes();
              inputSha = sha256.convert(bytes).toString();
              return Response<ResponseBody>(
                requestOptions: RequestOptions(path: cfg['url'] as String),
                data: ResponseBody(Stream.value(bytes), 200,
                  headers: {Headers.contentLengthHeader: ['${bytes.length}']}),
              );
            },
            write: (data) async { output = Uint8List.fromList(data); },
          )) {
            if (progress.imageBytes != null) output = progress.imageBytes;
          }
          expect(output, isNotNull);
          final decodedSha = sha256.convert(output!).toString();
          expect(decodedSha, entry.value['sha']);
          final codec = await ui.instantiateImageCodec(output!);
          try {
            final frame = await codec.getNextFrame();
            expect(frame.image.width, entry.value['width']);
            expect(frame.image.height, entry.value['height']);
            frame.image.dispose();
          } finally { codec.dispose(); }
          evidence.add({
            'kind': thumbnail ? 'thumbnail' : 'reader', 'sample': entry.key,
            'inputSHA256': inputSha, 'decodedSHA256': decodedSha,
            'width': entry.value['width'], 'height': entry.value['height'],
            'nativeQuickJS': true, 'productionDownloader': true, 'flutterFrameDecoded': true,
          });
        } finally {
          client.close(force: true);
          configFunction?.free();
          try { js.close(); } finally { js.port.close(); }
        }
      }, timeout: const Timeout(Duration(minutes: 2)));
    }
  }
}
