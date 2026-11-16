/// A page belongs to its original native query, never to a synthesized param.
class NativeFilterPage<T> {
  const NativeFilterPage(this.items, this.hasMore);
  final List<T> items;
  final bool hasMore;
}

/// Queries with differing page boundaries are intersected over all fetched
/// items, not just each query's current first page. Keys must include source.
class NativeFilterAccumulator<T> {
  NativeFilterAccumulator(this.keyOf);
  final String Function(T) keyOf;
  final Map<String, Map<String, T>> _queries = {};
  void add(String query, Iterable<T> items) {
    final map = _queries.putIfAbsent(query, () => {});
    for (final item in items) { map[keyOf(item)] = item; }
  }
  List<T> intersectRows(List<List<String>> rows) {
    Map<String, T>? intersection;
    for (final row in rows) {
      final union = <String, T>{};
      for (final query in row) { union.addAll(_queries[query] ?? {}); }
      if (intersection == null) { intersection = union; }
      else { intersection.removeWhere((key, _) => !union.containsKey(key)); }
    }
    return intersection?.values.toList() ?? [];
  }
}
