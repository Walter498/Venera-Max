import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:venera/foundation/log.dart';
import 'package:venera/network/app_dio.dart';

/// Shared protocol for the App's native community/rank/update readers.
/// This is isolated from ComicSource: other sources keep their own protocols.
abstract final class LiziApiProtocol {
  static const hosts = ['http://ai.xajtl.com', 'http://ai.qsmm.fun'];
  // Public application protocol constant, never an account JWT.
  static const _prefix = "q2sIObYXCp2uBZgCNBlY93J3z67hK0wS";

  static Uri signedUri(String host, String target, {int? timestamp}) {
    final relative = Uri.parse(target);
    if (relative.hasScheme || relative.hasAuthority ||
        !relative.path.startsWith('/app/api/')) {
      throw ArgumentError('Expected a relative Lizi API path');
    }
    final t = timestamp ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final params = <String, List<String>>{
      for (final entry in relative.queryParametersAll.entries)
        if (entry.key != 'lzsign' && entry.key != 't')
          entry.key: List<String>.from(entry.value),
    };
    if (relative.path == '/app/api/configv2' ||
        relative.path == '/app/api/home/data') {
      params.putIfAbsent('packname', () => ['com.jy.zyds']);
      params.putIfAbsent('appsign256', () => ['']);
    }
    if (relative.path == '/app/api/configv2') {
      params.putIfAbsent('platform', () => ['ios']);
    }
    params['t'] = ['$t'];
    params['lzsign'] = [md5.convert(utf8.encode('$_prefix${relative.path}$t')).toString()];
    return Uri.parse(host).replace(path: relative.path, queryParameters: params);
  }
}

class LiziApiResponse {
  const LiziApiResponse(this.status, this.body);
  final int status;
  final Object? body;
}

typedef LiziApiTransport = Future<LiziApiResponse> Function(Uri uri);

/// Shared by community and the native home tabs. Only a validated successful
/// reply pins the host; DNS/HTTP/HTML failures never become empty data.
class LiziApiClient {
  LiziApiClient({LiziApiTransport? transport, this.timestamp})
      : _transport = transport ?? _networkRequest;

  static final instance = LiziApiClient();
  final LiziApiTransport _transport;
  final int Function()? timestamp;
  int _hostIndex = 0;
  String get api => LiziApiProtocol.hosts[_hostIndex];

  static Future<LiziApiResponse> _networkRequest(Uri uri) async {
    final dio = AppDio(BaseOptions(
      responseType: ResponseType.plain,
      // Byte-for-byte the header set the official client sends: it does not
      // send Accept, and it does send Content-Type and gzip.
      headers: {
        'User-Agent': 'Dart/3.5 (dart:io)',
        'Content-Type': 'application/json; charset=utf-8',
        'Accept-Encoding': 'gzip',
      },
      validateStatus: (_) => true,
    ), const Duration(seconds: 15));
    final response = await dio.get(uri.toString());
    return LiziApiResponse(response.statusCode ?? 0, response.data);
  }

  Future<Map<String, dynamic>> getJson(String target) async {
    final start = _hostIndex;
    final errors = <String>[];
    for (var i = 0; i < LiziApiProtocol.hosts.length; i++) {
      final index = (start + i) % LiziApiProtocol.hosts.length;
      final host = LiziApiProtocol.hosts[index];
      final uri = LiziApiProtocol.signedUri(host, target, timestamp: timestamp?.call());
      LiziApiResponse response;
      try {
        response = await _transport(uri);
      } catch (e) {
        Log.info('LiziAPI', 'GET ${uri.path} @ $host failed: $e');
        errors.add('$host: 連線失敗');
        continue;
      }
      // Server replies with an HTML error page for a rejected request; the
      // status alone does not say whether it was the CDN or the API.
      final raw0 = response.body;
      final isHtml = raw0 is String && raw0.trimLeft().startsWith('<');
      Log.info(
        'LiziAPI',
        'GET ${uri.path} @ $host -> HTTP ${response.status}'
        '${isHtml ? ' (HTML 錯誤頁)' : ''}',
      );
      if (response.status != 200) {
        // PWS/CDN intermittently answers a signed request with its own HTML
        // 403; one short retry against the same host clears it.
        if (response.status == 403 && isHtml) {
          await Future<void>.delayed(const Duration(milliseconds: 700));
          try {
            final retry = await _transport(uri);
            final retryHtml =
                retry.body is String && (retry.body as String).trimLeft().startsWith('<');
            Log.info('LiziAPI', 'retry ${uri.path} @ $host -> HTTP ${retry.status}');
            if (retry.status == 200) {
              _hostIndex = index;
              dynamic raw1 = retry.body;
              if (raw1 is String) raw1 = jsonDecode(raw1);
              if (raw1 is Map) {
                final data1 = raw1['data'];
                if (data1 is Map) return Map<String, dynamic>.from(data1);
              }
            }
            if (!retryHtml && retry.status != 200) {
              errors.add('$host: HTTP ${retry.status}');
              continue;
            }
          } catch (_) {}
        }
        errors.add('$host: HTTP ${response.status}${isHtml ? ' (HTML)' : ''}');
        continue;
      }
      dynamic raw = response.body;
      try { if (raw is String) raw = jsonDecode(raw); }
      catch (_) { errors.add('$host: 非 JSON 回應'); continue; }
      if (raw is! Map) { errors.add('$host: 回應格式錯誤'); continue; }
      final code = raw['code'];
      if (code != 201 && code != 200) {
        errors.add('$host: API code $code');
        continue;
      }
      final data = raw['data'];
      if (data is! Map) { errors.add('$host: 資料格式錯誤'); continue; }
      _hostIndex = index;
      return Map<String, dynamic>.from(data);
    }
    // Never echo JWT, signatures or raw response content through our errors.
    throw StateError('栗子接口 ${Uri.parse(target).path} 請求失敗 (${errors.join('; ')})');
  }
}
