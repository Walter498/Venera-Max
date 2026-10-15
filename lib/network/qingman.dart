import 'package:venera/foundation/app.dart';
import 'qingman_transport.dart';
export 'qingman_transport.dart';

QingmanTransport? _instance;
QingmanTransport get qingmanTransport =>
    _instance ??= QingmanTransport(App.dataPath);

/// Always resolves to a sanitized envelope. No parser/socket exception or
/// incoming JS message is ever included in the JS engine's generic log catch.
Future<Map<String, dynamic>> handleQingmanMessage(
    Map<dynamic, dynamic> message) async {
  try {
    if (message['action'] == 'profileStatus') {
      return await qingmanTransport.profileStatus();
    }
    if (message['action'] != null && message['action'] != 'request') {
      throw const QingmanException('path');
    }
    final path = message['path'];
    final params = message['params'] ?? <String, dynamic>{};
    if (path is! String || params is! Map) throw const QingmanException('path');
    return await qingmanTransport.request(path, params);
  } on QingmanException catch (e) {
    return {'error': e.toString(), 'code': e.code};
  } catch (_) {
    return {'error': const QingmanException('service').toString(), 'code': 'service'};
  }
}
