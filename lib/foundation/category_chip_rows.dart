import 'package:venera/foundation/comic_source/comic_source.dart';

/// Only the existing encoded filter protocol can be combined with `|`.
/// Other category params are opaque source values, not filter expressions.
bool isCategoryFilterTarget(PageJumpTarget target) {
  if (target.page != 'category') return false;
  final param = target.attributes?['param'];
  return param is String &&
      (param.startsWith('tag:') ||
          param.startsWith('class:') ||
          param.startsWith('isend:'));
}

class CategoryChipOption {
  final String label;
  final PageJumpTarget? target;

  const CategoryChipOption(this.label, this.target);

  String? get param => target?.attributes?['param']?.toString();
}

class CategoryChipRow {
  /// Titles need not be unique (some sources have two identically named parts).
  final int id;
  final String title;
  final List<CategoryChipOption> options;
  final bool isFilter;

  const CategoryChipRow(this.id, this.title, this.options, this.isFilter);

  bool get isTagFilter =>
      isFilter &&
      options.any((option) => option.param?.startsWith('tag:') == true);
}

/// Navigation chips keep the complete PageJumpTarget: page, source, category,
/// keyword/text, params and options. Never turn a search target into a category.
List<CategoryChipRow> buildCategoryChipRows(
  CategoryData data, {
  required String allLabel,
}) {
  final rows = <CategoryChipRow>[];
  for (var index = 0; index < data.categories.length; index++) {
    final part = data.categories[index];
    final items = part.categories;
    if (items.isEmpty) continue;
    final isFilter = items.every((item) => isCategoryFilterTarget(item.target));
    rows.add(CategoryChipRow(
      index,
      part.title,
      [
        if (isFilter) CategoryChipOption(allLabel, null),
        for (final item in items) CategoryChipOption(item.label, item.target),
      ],
      isFilter,
    ));
  }
  return rows;
}

String? combineCategoryChipParams(
  Iterable<CategoryChipRow> rows,
  Map<int, String?> selected,
  Set<String> tags,
  int? tagRowId,
) {
  final params = <String>[];
  for (final row in rows.where((row) => row.isFilter)) {
    if (row.id == tagRowId) {
      if (tags.length == 1) params.add(tags.first);
      continue;
    }
    final value = selected[row.id];
    if (value != null && value.isNotEmpty) params.add(value);
  }
  return params.isEmpty ? null : params.join('|');
}
