import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/network/qingman_transport.dart';

void main() {
  late Directory directory;
  late QingmanTransport transport;
  late Map<String, dynamic> fixture;
  List<int> profileBytes(Map<String, dynamic> p) => utf8.encode(jsonEncode(p));
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('qingman-test-');
    transport = QingmanTransport(directory.path);
    fixture = jsonDecode(await File('test/fixtures/qingman_synthetic.json').readAsString())
        as Map<String, dynamic>;
  });
  tearDown(() async => directory.delete(recursive: true));

  test('int64 snowflake IDs survive native JSON to QuickJS boundary exactly', () {
    final decoded = jsonDecode('{"id":1965626277746577408,"comicId":42,'
      '"data":[{"chapterId":1965626277746577408,"total":2}],'
      '"large":1965626277746577408}');
    final safe = QingmanProtocol.bridgeJson(decoded) as Map;
    expect(safe['id'], '1965626277746577408');
    expect(safe['comicId'], '42');
    expect(safe['large'], '1965626277746577408');
    expect(safe['data'][0]['chapterId'], '1965626277746577408');
    expect(safe['data'][0]['total'], 2);
    expect(jsonEncode(safe), contains('"id":"1965626277746577408"'));
  });

  test('independent Python SHA256 concatenation vector', () {
    expect(QingmanProtocol.sign(fixture['timestamp'], fixture['nonce'],
      fixture['deviceId'], List<int>.generate(33, (i) => i)), fixture['signature']);
  });
  test('AES256-GCM iv12 ciphertext tag16 with timestamp|nonce AAD', () {
    final key = List<int>.generate(32, (i) => i);
    expect(utf8.decode(QingmanProtocol.unseal(fixture['sealed'], key,
      fixture['timestamp'], fixture['nonce'])), fixture['plain']);
    expect(() => QingmanProtocol.unseal(fixture['sealed'], key,
      fixture['timestamp'], 'wrong'), throwsA(anything));
    final tampered = base64.decode(fixture['sealed']);
    tampered[tampered.length - 1] ^= 1;
    expect(() => QingmanProtocol.unseal(base64.encode(tampered), key,
      fixture['timestamp'], fixture['nonce']), throwsA(anything));
  });
  test('strict authenticated origin; bare DNS becomes HTTPS, no paths or IP', () {
    expect(QingmanProtocol.apiOrigin('api.synthetic.example').scheme, 'https');
    expect(QingmanProtocol.apiOrigin('https://api.synthetic.example').host,
      'api.synthetic.example');
    for (final invalid in ['http://api.example', 'https://api.example/',
      'https://api.example?q=1', 'https://api.example#f', 'https://a@api.example',
      'https://api.example:443', 'https://127.0.0.1', 'https://[::1]',
      'https://localhost', 'https://x.local', 'https://-api.example',
      'https://a..example', ' https://api.example']) {
      expect(() => QingmanProtocol.apiOrigin(invalid), throwsA(isA<QingmanException>()), reason: invalid);
    }
  });
  test('missing profile is explicit; no network required', () async {
    expect((await transport.profileStatus())['code'], 'missingProfile');
    await expectLater(transport.request('/api/comic/comments/fu893u94/list',
      {'comicId': '42', 'page': 1, 'size': 20, 'sortType': 0}),
      throwsA(isA<QingmanException>().having((e) => e.code, 'code', 'missingProfile')));
  });
  test('chapter params use chapterId and sort, never require comicId', () async {
    await expectLater(transport.request('/api/comic/comments/fu893u94/chapterList',
      {'chapterId': '42', 'page': 1, 'size': 20, 'sort': 0}),
      throwsA(isA<QingmanException>().having((e) => e.code, 'code', 'missingProfile')));
    await expectLater(transport.request('/api/comic/comments/fu893u94/chapterList',
      {'comicId': '42', 'sortType': 0}),
      throwsA(isA<QingmanException>().having((e) => e.code, 'code', 'path')));
  });
  test('verified metadata paths accepted; reading and catalog query denied', () async {
    for (final item in <(String, Map<String, dynamic>)>[
      ('/api/comic/comics/ie84hfh8/detail', {'comicId': '42'}),
      ('/api/comic/chapter/ie84hfh8/homelist/42', {}),
    ]) {
      await expectLater(transport.request(item.$1, item.$2),
        throwsA(isA<QingmanException>().having((e) => e.code, 'code', 'missingProfile')));
    }
    for (final item in <(String, Map<String, dynamic>)>[
      ('/api/comic/chapter/ie84hfh8/homelist/42', {'page': 1}),
      ('/api/comic/chapter/ie84hfh8/homelist/42?x=1', {}),
      ('/api/comic/chapter/ie84hfh8/homelist/42/detail', {}),
      ('/api/comic/chapter/ie84hfh8/detail', {'chapterId': '42'}),
      ('/api/comic/comics/ie84hfh8/detail', {'id': '42'}),
    ]) {
      await expectLater(transport.request(item.$1, item.$2),
        throwsA(isA<QingmanException>().having((e) => e.code, 'code', 'path')));
    }
  });

  test('verified search permits only a bounded keyword before profile access', () async {
    const path = '/api/comic/history/fu893u94/search';
    await expectLater(transport.request(path, {'keyword': '我独自升级'}),
      throwsA(isA<QingmanException>().having((e) => e.code, 'code', 'missingProfile')));
    for (final params in <Map<String, dynamic>>[
      {}, {'keyword': ''}, {'keyword': '   '}, {'keyword': 42},
      {'keyword': 'title', 'page': 1}, {'keyword': List.filled(201, 'x').join()},
      {'keyword': 'title\nother'},
    ]) {
      await expectLater(transport.request(path, params),
        throwsA(isA<QingmanException>().having((e) => e.code, 'code', 'path')));
    }
  });

  test('only exact read-only paths and bounded scalar query accepted', () async {
    for (final path in ['https://evil.example', '/api/comic/comments/fu893u94/list?x=1',
      '/api/comic/comments/fu893u94/reply', '/bootstrap/domain', '/api/search']) {
      await expectLater(transport.request(path, {'comicId': '42'}),
        throwsA(isA<QingmanException>().having((e) => e.code, 'code', 'path')));
    }
    for (final params in <Map<String, dynamic>>[
      {'comicId': '42', 'host': 'evil.example'}, {'comicId': '42', 'page': 501},
      {'comicId': '42', 'size': 51}, {'comicId': '42', 'sortType': 2},
      {'comicId': '42', 'page': []}, {'comicId': '42&host=bad'},
    ]) {
      await expectLater(transport.request('/api/comic/comments/fu893u94/list', params),
        throwsA(isA<QingmanException>().having((e) => e.code, 'code', 'path')));
    }
  });
  test('Bag Attributes import, replace, restart, clear, stable local device', () async {
    final p = Map<String, dynamic>.from(fixture['profile']);
    await transport.importProfile(profileBytes(p));
    expect((await transport.profileStatus())['installed'], true);
    final id = await File('${directory.path}/qingman/device-id').readAsString();
    expect(id, matches(RegExp(r'^[a-f0-9]{32}$')));
    final restarted = QingmanTransport(directory.path);
    expect((await restarted.profileStatus())['installed'], true);
    await transport.importProfile(profileBytes({...p, 'deviceId': 'synthetic-override-device'}));
    expect((await transport.profileStatus()).keys.toSet(), {'installed', 'version'});
    await transport.clearProfile();
    expect((await transport.profileStatus())['installed'], false);
    expect(await File('${directory.path}/qingman/profile.qmprofile').exists(), false);
    expect(await File('${directory.path}/qingman/device-id').readAsString(), id);
    await transport.importProfile(profileBytes(p));
    expect((await transport.profileStatus())['installed'], true);
  });
  test('invalid replacement does not destroy current profile or echo input', () async {
    final p = Map<String, dynamic>.from(fixture['profile']);
    await transport.importProfile(profileBytes(p));
    final before = await File('${directory.path}/qingman/profile.qmprofile').readAsBytes();
    for (final bad in <List<int>>[
      utf8.encode('SECRET-SENTINEL'), profileBytes({...p, 'version': 2}),
      profileBytes({...p, 'responseKey': base64.encode([1, 2])}),
      profileBytes({...p, 'clientPem': 'SECRET-SENTINEL'}),
      List<int>.filled(QingmanTransport.maxProfileBytes + 1, 0),
    ]) {
      await expectLater(transport.importProfile(bad), throwsA(isA<QingmanException>()
        .having((e) => e.toString().contains('SECRET-SENTINEL'), 'redacted', false)));
    }
    expect(await File('${directory.path}/qingman/profile.qmprofile').readAsBytes(), before);
    expect((await transport.profileStatus())['installed'], true);
  });
}
