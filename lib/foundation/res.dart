class Res<T> {
  /// error info
  final String? errorMessage;

  /// data
  final T? _data;

  /// is there an error
  bool get error => errorMessage != null;

  /// whether succeed
  bool get success => !error;

  /// data
  T get data => _data ?? (throw Exception(errorMessage));

  /// get data, or null if there is an error
  T? get dataOrNull => _data;

  final dynamic subData;

  /// Backend confirmed by this response, independent of the selected route.
  final String? effectiveProvider;

  static String? parseEffectiveProvider(dynamic value) {
    if (value is! String || value.trim().isEmpty) return null;
    return value.trim();
  }

  /// New responses use effectiveProvider; older candidates may use provider.
  static String? parseCommentProvider(dynamic value) {
    if (value is! Map) return null;
    return parseEffectiveProvider(value['effectiveProvider']) ??
        parseEffectiveProvider(value['provider']);
  }

  /// Optional server-reported total for paged category / search results.
  /// Null means the source does not report one; callers must not invent it.
  final int? total;

  /// Explicit runtime absence; null preserves legacy/unknown availability.
  final bool? available;

  /// Read-only discussion metadata, independent of pagination in [subData].
  final Map<String, dynamic>? commentContext;

  /// Keep only explicit provider and valid counts. Never coerce unknown to zero.
  static Map<String, dynamic>? parseCommentContext(dynamic value) {
    if (value is! Map || value['provider'] is! String ||
        (value['provider'] as String).trim().isEmpty) {
      return null;
    }
    final result = <String, dynamic>{'provider': value['provider']};
    for (final key in ['comicFavoriteCount', 'chapterLikeCount']) {
      final count = value[key];
      if (count is int && count >= 0 && count <= 9007199254740991) {
        result[key] = count;
      }
    }
    return Map<String, dynamic>.unmodifiable(result);
  }

  @override
  String toString() => _data.toString();

  Res.fromErrorRes(Res another, {this.subData, this.total, this.available})
      : _data = null,
        effectiveProvider = null,
        commentContext = null,
        errorMessage = another.errorMessage;

  /// network result
  const Res(this._data, {this.errorMessage, this.subData, this.total, this.available,
    this.commentContext, this.effectiveProvider});

  const Res.error(String err)
      : _data = null,
        subData = null,
        total = null,
        available = null,
        effectiveProvider = null,
        commentContext = null,
        errorMessage = err;
}
