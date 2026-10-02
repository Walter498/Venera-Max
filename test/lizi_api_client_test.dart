import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/lizi_api_client.dart';
import 'package:venera/foundation/lizi_community.dart';

void main() {
  const timestamp = 1790953303;
  test('native community signer matches independently computed protocol vector', () {
    final uri = LiziApiProtocol.signedUri(LiziApiProtocol.hosts.first,
      '/app/api/community/posts?section_id=3&page=2', timestamp: timestamp);
    expect(uri.queryParameters['lzsign'], "b59e9175ed5584b2765009dd67587af0");
    expect(uri.queryParameters['t'], '$timestamp');
    expect(uri.queryParameters['section_id'], '3');
    expect(uri.queryParameters['page'], '2');
    final otherPage = LiziApiProtocol.signedUri(LiziApiProtocol.hosts.first,
      '/app/api/community/posts?page=9', timestamp: timestamp);
    expect(otherPage.queryParameters['lzsign'], uri.queryParameters['lzsign']);
  });
  test('signer preserves encoded/multiple query values and replaces stale signatures', () {
    final uri = LiziApiProtocol.signedUri(LiziApiProtocol.hosts.first,
      '/app/api/community/posts?tag=a%20b&tag=c&page=2&lzsign=old&t=1', timestamp: timestamp);
    expect(uri.queryParametersAll['tag'], ['a b', 'c']);
    expect(uri.queryParametersAll['lzsign']!.length, 1);
    expect(uri.queryParametersAll['t'], ['$timestamp']);
    expect(() => LiziApiProtocol.signedUri(LiziApiProtocol.hosts.first, 'https://other.invalid/app/api/test'), throwsArgumentError);
    expect(() => LiziApiProtocol.signedUri(LiziApiProtocol.hosts.first, '/not-api'), throwsArgumentError);
  });
  test('configuration includes public official parameters, never authorization', () {
    final uri = LiziApiProtocol.signedUri(LiziApiProtocol.hosts.first,
      '/app/api/configv2', timestamp: timestamp);
    expect(uri.queryParameters['platform'], 'ios');
    expect(uri.queryParameters['packname'], 'com.jy.zyds');
    expect(uri.queryParameters['appsign256'], '');
    expect(uri.queryParameters.keys, isNot(contains('authorization')));
  });
  test('bad HTML response fails primary; only valid fallback JSON pins the host', () async {
    final requests = <Uri>[];
    final client = LiziApiClient(timestamp: () => timestamp, transport: (uri) async {
      requests.add(uri);
      if (uri.host == 'ai.xajtl.com') return const LiziApiResponse(200, '<html>403</html>');
      return const LiziApiResponse(200, '{"code":201,"data":{"list":[],"has_more":false}}');
    });
    final data = await client.getJson('/app/api/community/posts?page=1');
    expect(data['list'], isEmpty);
    expect(requests.map((uri) => uri.host), ['ai.xajtl.com', 'ai.qsmm.fun']);
    expect(requests.every((uri) => uri.queryParameters['lzsign']!.length == 32), isTrue);
    requests.clear();
    await client.getJson('/app/api/community/posts?page=2');
    expect(requests.length, 1);
    expect(requests.first.host, 'ai.qsmm.fun');
  });
  test('both hosts failing report safe HTTP/path diagnostics, not a signed URL', () async {
    final client = LiziApiClient(timestamp: () => timestamp,
      transport: (_) async => const LiziApiResponse(403, 'sensitive raw response'));
    try {
      await client.getJson('/app/api/community/posts?page=1');
      fail('failure was swallowed');
    } catch (e) {
      expect(e, isA<StateError>());
      expect(e.toString(), contains('HTTP 403'));
      expect(e.toString(), contains('/app/api/community/posts'));
      expect(e.toString(), isNot(contains('lzsign')));
      expect(e.toString(), isNot(contains('sensitive raw response')));
    }
  });
  test('primary network error recovers through valid fallback', () async {
    final client = LiziApiClient(transport: (uri) async {
      if (uri.host == 'ai.xajtl.com') throw Exception('DNS error');
      return const LiziApiResponse(200, {'code': 201, 'data': {'value': 7}});
    });
    expect((await client.getJson('/app/api/rank/list'))['value'], 7);
  });
  test('official community payload models match live field types', () {
    final post = LiziCommunityPost.fromJson(jsonDecode('{"id":1,"createdAt":"2026-10-02T00:00:00Z","community_section_id":3,"community_section":{"name":"日常"},"like_count":2,"comment_count":1,"view_count":9,"comic_user":{"id":1,"NickName":"demo"},"comics":[],"content":"test","is_liked":false}'));
    expect(post.id, 1);
    expect(post.nickname, 'demo');
    expect(post.sectionId, 3);
  });
}
