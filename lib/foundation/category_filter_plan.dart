/// Source-native category filter state.
///
/// This file intentionally has no source or UI imports. The source layer owns
/// the loader typedef; the page and parser share only this data contract.
class CategoryFilterSelection {
  final String group;
  final String label;
  final String? param;
  final String category;

  const CategoryFilterSelection({
    required this.group,
    required this.label,
    required this.param,
    required this.category,
  });

  Map<String, dynamic> toJson() => {
        'group': group,
        'label': label,
        'param': param,
        'category': category,
      };
}

class CategoryFilterRequest {
  final List<CategoryFilterSelection> selections;
  final List<String> options;
  final int page;

  const CategoryFilterRequest({
    required this.selections,
    required this.options,
    required this.page,
  });

  Map<String, dynamic> toJson() => {
        'filters': [for (final item in selections) item.toJson()],
        'options': options,
        'page': page,
      };
}

List<CategoryFilterSelection> normalizeCategorySelections(
  Iterable<CategoryFilterSelection> input,
) {
  final seen = <String>{};
  final result = <CategoryFilterSelection>[];
  for (final item in input) {
    final param = item.param?.trim();
    if (param == null || param.isEmpty) continue;
    final key = '${item.group}\u0000${item.category}\u0000$param';
    if (seen.add(key)) result.add(item);
  }
  return result;
}

/// Builds the legacy source-native combinations used by older source adapters.
/// Choices inside a row are OR alternatives; rows are AND constraints.
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
      for (final prefix in combinations)
        prefix.isEmpty ? tags.first : '${tags.first}|$prefix',
    ];
  }
  return combinations.map((value) => value.isEmpty ? null : value).toList();
}

String normalizeCategoryTag(String value) {
  final trimmed = value.trim();
  final separator = trimmed.indexOf(':');
  return (separator >= 0 ? trimmed.substring(separator + 1) : trimmed)
      .trim()
      .toLowerCase();
}

bool categoryTagMatches(String actual, String wanted) =>
    normalizeCategoryTag(actual) == normalizeCategoryTag(wanted);

bool matchesAllCategoryTags(Iterable<String> actual, Iterable<String> selected) {
  final available = actual.map(normalizeCategoryTag).toSet();
  return selected.every((wanted) => available.contains(normalizeCategoryTag(wanted)));
}
