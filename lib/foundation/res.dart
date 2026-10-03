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

  /// Optional server-reported total for paged category / search results.
  /// Null means the source does not report one; callers must not invent it.
  final int? total;

  @override
  String toString() => _data.toString();

  Res.fromErrorRes(Res another, {this.subData, this.total})
      : _data = null,
        errorMessage = another.errorMessage;

  /// network result
  const Res(this._data, {this.errorMessage, this.subData, this.total});

  const Res.error(String err)
      : _data = null,
        subData = null,
        total = null,
        errorMessage = err;
}
