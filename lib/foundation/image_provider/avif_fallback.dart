/// AVIF fallback registry for handling incompatible AVIF encodings.
///
/// Flutter's AVIF decoder does not support all encoding configurations
/// (e.g., 10-bit, HDR, certain color spaces). When an AVIF image fails to
/// decode, this registry records the URL so subsequent loads automatically
/// fall back to WebP instead of retrying the broken AVIF indefinitely.
class AvifFallbackRegistry {
  AvifFallbackRegistry._();
  static final instance = AvifFallbackRegistry._();

  final _failedUrls = <String>{};

  /// Record an AVIF URL that failed to decode.
  /// Extracts the pure URL from a cache key (format: url@sourceKey@cid).
  void markFailed(String cacheKey) {
    final url = cacheKey.split('@').first;
    if (url.contains('.avif')) {
      _failedUrls.add(url);
    }
  }

  /// Apply fallback: replace .avif with .webp if the URL is in the failed set.
  String applyFallback(String url) {
    if (_failedUrls.contains(url) && url.contains('.avif')) {
      return url.replaceAll('.avif', '.webp');
    }
    return url;
  }

  /// Clear the registry (for testing or manual reset).
  void clear() {
    _failedUrls.clear();
  }
}
