String userFacingNetworkError(Object error) {
  final text = error.toString();
  if (RegExp(r'ENOTFOUND|DNS|failed to lookup|nodename', caseSensitive: false).hasMatch(text)) {
    return '網路地址暫時無法解析';
  }
  if (RegExp(r'timeout|超时|timed out', caseSensitive: false).hasMatch(text)) {
    return '連線逾時';
  }
  final http = RegExp(r'HTTP\s+(\d{3})', caseSensitive: false).firstMatch(text);
  if (http != null) return '伺服器回應 ${http.group(1)}';
  return '網路請求失敗';
}
