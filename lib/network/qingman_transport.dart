import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/api.dart';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/gcm.dart';

part 'qingman_profile.dart';

/// Deliberately contains only fixed, non-sensitive messages.
class QingmanException implements Exception {
  final String code;
  const QingmanException(this.code);
  @override
  String toString() => switch (code) {
    'missingProfile' => '青漫尚未导入配置，请在青漫配置页导入 .qmprofile',
    'profile' => '青漫配置无效或无法保存，请重新导入有效配置',
    'tls' => '青漫 TLS 验证失败（证书、域名或客户端身份不匹配）',
    'path' => '青漫请求不在已验证的只读接口白名单中',
    'expired' => '青漫令牌无效或过期，请稍后重试',
    'changed' => '青漫配置已变更，请重新加载',
    'timeout' => '青漫请求超时，请稍后重试',
    'limit' => '青漫请求或响应超过安全限制',
    'busy' => '青漫请求繁忙，请稍后重试',
    _ => '青漫服务暂不可用，请稍后重试',
  };
}

/// Pure protocol primitives; no access to installed profile or session material.
class QingmanProtocol {
  /// Native jsonDecode retains int64; stringify before QuickJS parses numbers.
  static dynamic bridgeJson(dynamic value, [String? field]) {
    if (value is int && (value > 9007199254740991 ||
        value < -9007199254740991 || field == 'id' ||
        (field?.endsWith('Id') ?? false))) {
      return value.toString();
    }
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(),
        bridgeJson(item, key.toString())));
    }
    if (value is List) return value.map((item) => bridgeJson(item, field)).toList();
    return value;
  }

  static String sign(String timestamp, String nonce, String deviceId,
      List<int> suffix) => sha256.convert([
        ...utf8.encode(timestamp), ...utf8.encode(nonce),
        ...utf8.encode(deviceId), ...suffix,
      ]).toString();

  static Uint8List unseal(String encoded, List<int> key,
      String timestamp, String nonce) {
    final wire = base64.decode(base64.normalize(encoded));
    if (wire.length < 29 || key.length != 32) {
      throw const QingmanException('service');
    }
    final cipher = GCMBlockCipher(AESEngine())
      ..init(false, AEADParameters(KeyParameter(Uint8List.fromList(key)),
          128, Uint8List.sublistView(wire, 0, 12),
          Uint8List.fromList(utf8.encode('$timestamp|$nonce'))));
    return cipher.process(Uint8List.sublistView(wire, 12));
  }

  /// Authenticated bootstrap may select a DNS host, never a URL path or IP.
  static Uri apiOrigin(String value) {
    if (RegExp(r'^[a-zA-Z0-9.-]+$').hasMatch(value)) value = 'https://$value';
    if (!RegExp(r'^https://[a-zA-Z0-9.-]+$').hasMatch(value)) {
      throw const QingmanException('service');
    }
    final uri = Uri.parse(value);
    final host = uri.host.toLowerCase();
    final labels = host.split('.');
    if (host.length > 253 || labels.length < 2 ||
        InternetAddress.tryParse(host) != null ||
        !RegExp(r'^[a-z]{2,63}$').hasMatch(labels.last) ||
        labels.any((s) => s.isEmpty || s.length > 63 ||
          !RegExp(r'^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$').hasMatch(s)) ||
        host.endsWith('.localhost') || host.endsWith('.local') ||
        host.endsWith('.internal')) {
      throw const QingmanException('service');
    }
    return uri;
  }
}

class _Session {
  final Uri origin;
  final String token;
  final DateTime expires;
  const _Session(this.origin, this.token, this.expires);
}

/// Separate from AppDio, proxies, interceptors, cookies and source HTTP clients.
/// No profile/key/token getter, export API, arbitrary host or redirect facility.
class QingmanTransport {
  QingmanTransport(String dataPath)
      : _directory = Directory('$dataPath/qingman');

  final Directory _directory;
  _Profile? _profile;
  _Session? _session;
  Future<_Session>? _bootstrapFlight;
  Future<_Profile>? _profileFlight;
  Future<void> _mutation = Future<void>.value();
  int _generation = 0;
  int _active = 0;

  static const maxProfileBytes = 256 * 1024;
  static const _maxResponse = 2 * 1024 * 1024;
  static const _deadline = Duration(seconds: 20);
  static final _bootstrapUri = Uri.https('mu8xm4cx.zermh.com', '/bootstrap/domain');

  // Root may extend only after verifying exact read-only search/catalog paths.
  // No prefix matching. Reply reading is intentionally unavailable (anonymous 401).
  static const readOnlyPaths = <String>{
    '/api/comic/comments/fu893u94/list',
    '/api/comic/comments/fu893u94/chapterList',
    '/api/comic/comics/ie84hfh8/detail',
    '/api/comic/history/fu893u94/search',
  };

  static bool _isCatalog(String path) => RegExp(
    r'^/api/comic/chapter/ie84hfh8/homelist/[0-9]{1,20}$').hasMatch(path);

  Future<Map<String, dynamic>> profileStatus() async {
    await _mutation;
    try {
      await _loadProfile();
      return {'installed': true, 'version': 1};
    } on QingmanException catch (e) {
      return {'installed': false, 'error': e.toString(), 'code': e.code};
    } catch (_) {
      return {'installed': false, 'error': const QingmanException('profile').toString(),
        'code': 'profile'};
    }
  }

  Future<Map<String, dynamic>> request(String path, Map<dynamic, dynamic> params) async {
    try {
      if (!readOnlyPaths.contains(path) && !_isCatalog(path)) {
        throw const QingmanException('path');
      }
      final query = _query(path, params);
      await _mutation;
      if (_active >= 8) throw const QingmanException('busy');
      _active++;
      final generation = _generation;
      try {
        final profile = await _loadProfile();
        var session = await _getSession(profile, generation);
        var result = await _business(profile, session, path, query);
        _checkGeneration(generation);
        // Only an explicit HTTP 401 permits one re-bootstrap; 403 is never retried.
        if (result.status == 401) {
          if (identical(_session, session)) _session = null;
          session = await _getSession(profile, generation);
          result = await _business(profile, session, path, query);
          _checkGeneration(generation);
        }
        if (result.status == 401) throw const QingmanException('expired');
        if (result.status < 200 || result.status >= 300) {
          throw const QingmanException('service');
        }
        // Only business JSON crosses the bridge, never bootstrap headers/material.
        return {'status': result.status,
          'body': jsonEncode(QingmanProtocol.bridgeJson(jsonDecode(result.body)))};
      } finally {
        _active--;
      }
    } on QingmanException {
      rethrow;
    } on HandshakeException {
      throw const QingmanException('tls');
    } on TlsException {
      throw const QingmanException('tls');
    } on TimeoutException {
      throw const QingmanException('timeout');
    } catch (_) {
      throw const QingmanException('service');
    }
  }

  Map<String, String> _query(String path, Map<dynamic, dynamic> params) {
    if (_isCatalog(path)) {
      if (params.isNotEmpty) throw const QingmanException('path');
      return {};
    }
    if (path == '/api/comic/history/fu893u94/search') {
      final keyword = params['keyword'];
      if (params.length != 1 || keyword is! String ||
          keyword.trim().isEmpty || utf8.encode(keyword).length > 200 ||
          RegExp(r'[\x00-\x1f\x7f-\x9f]').hasMatch(keyword)) {
        throw const QingmanException('path');
      }
      return {'keyword': keyword};
    }
    if (path == '/api/comic/comics/ie84hfh8/detail') {
      final id = params['comicId'];
      if (params.length != 1 || (id is! String && id is! int) ||
          !RegExp(r'^\d{1,20}$').hasMatch(id.toString())) {
        throw const QingmanException('path');
      }
      return {'comicId': id.toString()};
    }
    final chapter = path.endsWith('/chapterList');
    final idKey = chapter ? 'chapterId' : 'comicId';
    final sortKey = chapter ? 'sort' : 'sortType';
    final keys = {idKey, 'page', 'size', sortKey};
    if (params.keys.any((k) => k is! String || !keys.contains(k))) {
      throw const QingmanException('path');
    }
    final out = <String, String>{};
    for (final entry in params.entries) {
      final value = entry.value;
      if (value is! String && value is! int) throw const QingmanException('path');
      final text = value.toString();
      if (!RegExp(r'^\d{1,20}$').hasMatch(text)) throw const QingmanException('path');
      out[entry.key as String] = text;
    }
    if (out[idKey] == null) throw const QingmanException('path');
    for (final key in ['page', 'size', sortKey]) {
      final value = int.tryParse(out[key] ?? (key == sortKey ? '0' : '1'));
      final max = key == 'page' ? 500 : key == 'size' ? 50 : 1;
      if (value == null || value < (key == sortKey ? 0 : 1) || value > max) {
        throw const QingmanException('path');
      }
    }
    return out;
  }

  void _checkGeneration(int generation) {
    if (generation != _generation) throw const QingmanException('changed');
  }

  Future<_Session> _getSession(_Profile profile, int generation) async {
    _checkGeneration(generation);
    final current = _session;
    if (current != null && DateTime.now().isBefore(current.expires)) return current;
    final flight = _bootstrapFlight;
    if (flight != null) return flight;
    final next = _bootstrap(profile, generation);
    _bootstrapFlight = next;
    try {
      final session = await next;
      _checkGeneration(generation);
      _session = session;
      return session;
    } finally {
      if (identical(_bootstrapFlight, next)) _bootstrapFlight = null;
    }
  }

  Future<_Session> _bootstrap(_Profile profile, int generation) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final nonce = _randomHex(16);
    final body = jsonEncode({'timestamp': timestamp, 'nonce': nonce,
      'deviceId': profile.deviceId,
      'sign': QingmanProtocol.sign(timestamp, nonce, profile.deviceId, profile.signSuffix)});
    final result = await _post(_bootstrapUri, body: body);
    _checkGeneration(generation);
    if (result.status != 200) throw const QingmanException('service');
    final outer = jsonDecode(result.body);
    if (outer is! Map || outer['code'] != 1 || outer['data'] is! String) {
      throw const QingmanException('service');
    }
    final decoded = jsonDecode(utf8.decode(QingmanProtocol.unseal(
      outer['data'] as String, profile.responseKey, timestamp, nonce)));
    if (decoded is! Map || decoded['apiDomain'] is! String ||
        decoded['appAccessToken'] is! String) {
      throw const QingmanException('service');
    }
    final origin = QingmanProtocol.apiOrigin(decoded['apiDomain'] as String);
    final token = decoded['appAccessToken'] as String;
    if (token.isEmpty || token.length > 8192 ||
        RegExp(r'[\x00-\x20\x7f]').hasMatch(token)) {
      throw const QingmanException('service');
    }
    // No verified server TTL field: bounded five-minute memory lease, plus one 401 refresh.
    return _Session(origin, token, DateTime.now().add(const Duration(minutes: 5)));
  }

  Future<_WireResult> _business(_Profile profile, _Session session,
      String path, Map<String, String> query) {
    final catalog = _isCatalog(path);
    return _post(session.origin.replace(path: path,
        queryParameters: catalog ? null : query),
      method: catalog ? 'GET' : 'POST',
      context: profile.context, headers: {
        'X-Device-Id': profile.deviceId, 'X-QM-App-Access': session.token,
      });
  }

  Future<_WireResult> _post(Uri uri, {SecurityContext? context,
      String method = 'POST', String? body,
      Map<String, String> headers = const {}}) async {
    final client = HttpClient(context: context)
      ..connectionTimeout = const Duration(seconds: 10)
      ..idleTimeout = const Duration(seconds: 5)
      ..findProxy = ((_) => 'DIRECT');
    // Never set badCertificateCallback: Dart checks the chain AND the DNS hostname.
    HttpClientRequest? pending;
    try {
      return await (() async {
        final request = await client.openUrl(method, uri);
        pending = request;
        request.followRedirects = false;
        request.maxRedirects = 0;
        request.headers.set('User-Agent', 'qingman/4.4.5');
        request.headers.set('Accept', 'application/json');
        request.headers.set('userPlatform', 'ios');
        request.headers.set('X-Register-Channel', 'webios');
        headers.forEach((key, value) => request.headers.set(key, value));
        if (body != null) {
          request.headers.contentType = ContentType.json;
          request.add(utf8.encode(body));
        }
        final response = await request.close();
        if (response.statusCode >= 300 && response.statusCode < 400) {
          throw const QingmanException('service');
        }
        if (response.contentLength > _maxResponse) throw const QingmanException('limit');
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in response) {
          if (bytes.length + chunk.length > _maxResponse) throw const QingmanException('limit');
          bytes.add(chunk);
        }
        return _WireResult(response.statusCode, utf8.decode(bytes.takeBytes()));
      })().timeout(_deadline);
    } finally {
      pending?.abort();
      client.close(force: true);
    }
  }
}

class _WireResult {
  final int status;
  final String body;
  const _WireResult(this.status, this.body);
}

String _randomHex(int bytes) {
  final random = Random.secure();
  return List.generate(bytes, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}
