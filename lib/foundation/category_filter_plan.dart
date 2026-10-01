/// OR within a row (region/status), AND across rows. Tags are AND.
/// For lizimh, one tag narrows the server query and the remaining tags are
/// checked against every returned comic's own tag list. Paging stays enabled.
List<String?> buildCategoryQueries(
  List<List<String>> rows, {
  List<String> tags = const [],
}) {
  var combinations = <String>[''];
  for (final choices in rows) {
    if (choices.isEmpty) continue;
    combinations = [
      for (final prefix in combinations)
        for (final choice in choices)
          prefix.isEmpty ? choice : '$prefix|$choice',
    ];
  }
  if (tags.isNotEmpty) {
    combinations = [
      for (final p in combinations)
        p.isEmpty ? tags.first : '${tags.first}|$p',
    ];
  }
  return combinations.map((p) => p.isEmpty ? null : p).toList();
}

bool matchesAllCategoryTags(Iterable<String> actual, Iterable<String> selected) {
  String normalize(String s) => s.replaceFirst(RegExp(r'^tag:'), '').trim().toLowerCase();
  final available = actual.map(normalize).toSet();
  return selected.every((s) => available.contains(normalize(s)));
}
