import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_qjs/flutter_qjs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/network/images.dart';

// No App.init, parser, source registry, account, device or business network.
// Production downloader owns these actual native QJS exports. Strict close()
// is the native reference oracle (do not suppress its reference-leak errors).
class _Tracked extends JSInvokable {
  final JSInvokable native;
  final dynamic Function(List)? action;
  int frees = 0;
  int calls = 0;
  _Tracked(this.native, [this.action]);

  @override
  dynamic invoke(List args, [dynamic thisVal]) {
    expect(frees, 0, reason: 'must not invoke a released config hook');
    calls++;
    return action == null ? native.invoke(args, thisVal) : action!(args);
  }

  @override
  void free() {
    frees++;
    expect(frees, 1, reason: 'each exported wrapper is freed exactly once');
    native.free();
  }

  @override
  void destroy() {
    frees++;
    expect(frees, 1, reason: 'each task-owned wrapper is destroyed exactly once');
    native.destroy();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FlutterQjs js;
  late List<_Tracked> tracked;

  _Tracked hook(String code, [dynamic Function(List)? action]) {
    final value = _Tracked(js.evaluate(code) as JSInvokable, action);
    tracked.add(value);
    return value;
  }

  Future<Response<ResponseBody>> ok(Map<String, dynamic> _) async => Response(
    requestOptions: RequestOptions(path: '/local-fixture'),
    data: ResponseBody(
      Stream.value(Uint8List.fromList([1, 2, 3])), 200,
      headers: {Headers.contentLengthHeader: ['3']},
    ),
  );

  Stream<ImageDownloadProgress> task(
    Map<String, dynamic> config, {
    bool thumbnail = false,
    Future<Response<ResponseBody>> Function(Map<String, dynamic>)? request,
    Future<void> Function(List<int>)? write,
    Future<Uint8List> Function(Uint8List, dynamic)? modify,
  }) => ImageDownloader.debugLoadImageTask(
    config: () async => config,
    request: request ?? ok,
    write: write ?? (_) async {},
    modify: modify,
    thumbnail: thumbnail,
  );

  setUp(() {
    js = FlutterQjs();
    unawaited(js.dispatch());
    tracked = [];
  });
  tearDown(() {
    try {
      for (final value in tracked) {
        expect(value.frees, 1);
        expect(() => value.native([]), throwsA(anything));
      }
    } finally {
      try {
        // jsFreeRuntime rejects *any* live exported wrapper. Each test returns
        // to the zero-reference baseline, not merely a Dart heap approximation.
        js.close();
      } finally {
        js.port.close();
      }
    }
  });

  for (final thumbnail in [false, true]) {
    final kind = thumbnail ? 'thumbnail' : 'page';
    test('$kind network failure releases uncalled and nested ignored hooks', () async {
      final response = hook('(bytes) => bytes');
      final ignored = hook('() => 9');
      final cycle = <dynamic>[];
      final config = <String, dynamic>{
        'onResponse': response,
        'ignored': [ignored, response, cycle],
      };
      cycle.addAll([cycle, config, ignored]);
      var requests = 0;
      await expectLater(task(config, thumbnail: thumbnail, request: (_) async {
        requests++;
        throw StateError('local transport failure');
      }).drain<void>(), throwsA(anything));
      expect(requests, thumbnail ? 1 : 4);
      expect(response.calls, 0);
      expect(ignored.calls, 0);
    });

    for (final code in [
      '() => { throw new Error("sync failure"); }',
      'async () => { throw new Error("async failure"); }',
      '() => { throw {callback: () => 1}; }',
      'async () => { throw {nested: [() => 1]}; }',
      '() => "not bytes"',
      '() => ({ignored: () => 7})',
    ]) {
      test('$kind rejects hook result: $code', () async {
        final response = hook(code);
        await expectLater(task({'onResponse': response}, thumbnail: thumbnail)
            .drain<void>(), throwsA(anything));
        expect(response.calls, thumbnail ? 1 : 4);
      });
    }

    test('$kind normal success frees unused recovery hook too', () async {
      final response = hook('async (bytes) => bytes');
      final recovery = hook('() => null');
      final events = await task({
        'onResponse': response,
        'onLoadFailed': recovery,
      }, thumbnail: thumbnail).toList();
      expect(events.last.imageBytes, [1, 2, 3]);
      expect(recovery.calls, 0);
    });

    test('$kind cancellation at progress yield runs task finally', () async {
      final response = hook('(bytes) => bytes');
      await task({'onResponse': response}, thumbnail: thumbnail).first;
      expect(response.frees, 1);
      expect(response.calls, 0);
    });
  }

  test('replacement frees retired hooks before request, transfers shared wrapper', () async {
    final retired = hook('(bytes) => bytes');
    final shared = hook('() => 8');
    final nextResponse = hook('(bytes) => bytes');
    final recovery = hook('() => null', (_) => <String, dynamic>{
      'onResponse': nextResponse,
      'nested': [shared, shared],
    });
    var requests = 0;
    await task({
      'onResponse': retired,
      'onLoadFailed': recovery,
      'nested': [shared],
    }, request: (config) async {
      if (++requests == 1) throw StateError('replace config');
      expect(retired.frees, 1);
      expect(recovery.frees, 1);
      expect(shared.frees, 0);
      expect(shared([]), 8);
      return ok(config);
    }).drain<void>();
    expect(requests, 2);
    expect(nextResponse.calls, 1);
  });

  for (final code in [
    '() => { throw new Error("recovery throw"); }',
    'async () => { throw new Error("recovery rejection"); }',
    '() => { throw {callback: () => 1}; }',
    'async () => { throw {nested: [() => 1]}; }',
    '() => [() => 4, {ignored: () => 5}]',
  ]) {
    test('recovery exception/invalid result releases all exports: $code', () async {
      final response = hook('(bytes) => bytes');
      final recovery = hook(code);
      await expectLater(task({
        'onResponse': response,
        'onLoadFailed': recovery,
      }, request: (_) async => throw StateError('network'))
          .drain<void>(), throwsA(anything));
      expect(recovery.calls, 1);
    });
  }

  test('real QJS recovery exports a fresh config and retires the old one', () async {
    final response = hook('(bytes) => bytes');
    final recovery = hook('''() => ({onResponse: (bytes) => bytes,
      ignored: {nested: [() => 2]}})''');
    var requests = 0;
    await task({'onResponse': response, 'onLoadFailed': recovery},
      request: (config) async {
        if (++requests == 1) throw StateError('refresh URL');
        expect(response.frees, 1);
        expect(recovery.frees, 1);
        return ok(config);
      },
    ).drain<void>();
    expect(requests, 2);
  });

  test('replacement can reuse the exact response wrapper without early free', () async {
    final response = hook('(bytes) => bytes');
    final recovery = hook('() => null', (_) => <String, dynamic>{
      'onResponse': response,
    });
    var requests = 0;
    await task({'onResponse': response, 'onLoadFailed': recovery},
      request: (config) async {
        if (++requests == 1) throw StateError('refresh');
        expect(response.frees, 0);
        expect(recovery.frees, 1);
        return ok(config);
      },
    ).drain<void>();
    expect(response.calls, 1);
  });

  test('same config recovery retries keep all hooks live until budget ends', () async {
    final response = hook('(bytes) => bytes');
    late Map<String, dynamic> config;
    final recovery = hook('() => null', (_) => config);
    config = {'onResponse': response, 'onLoadFailed': recovery};
    var requests = 0;
    await expectLater(task(config, request: (_) async {
      requests++;
      expect(response.frees, 0);
      expect(recovery.frees, 0);
      throw StateError('still failing');
    }).drain<void>(), throwsA(anything));
    expect(requests, 7);
    expect(recovery.calls, 6);
  });

  for (final thumbnail in [false, true]) {
    test('invalid headers release config before transport ($thumbnail)', () async {
      final response = hook('(bytes) => bytes');
      var requests = 0;
      await expectLater(task({'headers': 9, 'onResponse': response},
        thumbnail: thumbnail,
        request: (config) async { requests++; return ok(config); },
      ).drain<void>(), throwsA(anything));
      expect(requests, 0);
    });
  }

  for (final lateStage in ['modify', 'write']) {
    test('successful response stays live through late $lateStage retry', () async {
      final response = hook('(bytes) => bytes');
      var attempts = 0;
      final config = <String, dynamic>{'onResponse': response};
      if (lateStage == 'modify') config['modifyImage'] = 'local-script';
      final events = await task(config,
        modify: (bytes, _) async {
          expect(response.frees, 0);
          if (++attempts == 1) throw StateError('modify once');
          return bytes;
        },
        write: (_) async {
          expect(response.frees, 0);
          if (lateStage == 'write' && ++attempts == 1) {
            throw StateError('disk once');
          }
        },
      ).toList();
      expect(events.last.imageBytes, [1, 2, 3]);
      expect(response.calls, 2);
      expect(attempts, 2);
    });
  }

  test('256 dynamic QJS configs retain no task exports at completion', () async {
    for (var page = 0; page < 256; page++) {
      // Same JS function exported repeatedly still produces independent native
      // wrappers, including uncalled callbacks nested in ignored fields.
      final config = js.evaluate('''(() => {
        globalThis.same = globalThis.same || ((bytes) => bytes);
        return {onResponse: same, ignored: [same, {callback: () => 1}],
          onLoadFailed: () => null};
      })()''') as Map<String, dynamic>;
      final response = config['onResponse'] as JSInvokable;
      final recovery = config['onLoadFailed'] as JSInvokable;
      final nested = config['ignored'] as List;
      final alias = nested[0] as JSInvokable;
      final ignored = (nested[1] as Map)['callback'] as JSInvokable;
      await task(config).drain<void>();
      for (final handle in [response, recovery, alias, ignored]) {
        expect(() => handle([]), throwsA(anything), reason: 'page $page');
      }
      // The public API has no ref-count getter. Strict runtime close is the
      // native zero-ref check; recreate lazily on the next page, not after GC.
      js.close();
    }
  });
}
