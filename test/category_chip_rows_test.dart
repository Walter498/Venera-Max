import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/category_chip_rows.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';

CategoryItem category(String label, String? param) => CategoryItem(
  label,
  PageJumpTarget('fixture', 'category', {'category': label, 'param': param}),
);

CategoryItem search(String label, {bool useText = false}) => CategoryItem(
  label,
  PageJumpTarget('fixture', 'search', {
    useText ? 'text' : 'keyword': label,
    'options': ['mv'],
  }),
);

CategoryData data(List<BaseCategoryPart> parts) => CategoryData(
  title: 'Fixture', categories: parts, enableRankingPage: false, key: 'fixture',
);

void main() {
  test('actual JMRecode fixture retains all six groups and 65 targets', () {
    final fixture = jsonDecode(File('test/fixtures/jm_category_parts.json').readAsStringSync()) as List;
    final input = data([
      for (final part in fixture)
        FixedCategoryPart(part['title'] as String, [
          for (final item in part['items'])
            CategoryItem(item['label'] as String,
                PageJumpTarget.parse('jm_recode', item['target'])),
        ]),
    ]);
    final rows = buildCategoryChipRows(input, allLabel: 'All');
    expect(rows, hasLength(6));
    expect(rows.map((row) => row.options.length), [1, 10, 17, 13, 18, 6]);
    expect(rows.every((row) => !row.isFilter), isTrue);
    expect(rows[0].options.single.target!.attributes!['category'], '每週必看');
    expect(rows[0].options.single.param, isNull);
    expect(rows[1].options.first.param, '0');
    expect(rows[2].options.first.target!.page, 'search');
    expect(rows[2].options.first.target!.attributes!['keyword'], isNotEmpty);
    expect(rows[4].title, rows[5].title);
    expect(rows[4].id, isNot(rows[5].id));
    for (var index = 0; index < rows.length; index++) {
      for (var option = 0; option < rows[index].options.length; option++) {
        expect(identical(rows[index].options[option].target,
            input.categories[index].categories[option].target), isTrue);
      }
    }
  });

  test('keyword/text, source key and complete option lists are preserved', () {
    final items = [search('topic:a'), search('topic:b', useText: true)];
    final rows = buildCategoryChipRows(data([FixedCategoryPart('Search', items)]), allLabel: 'All');
    expect(rows.single.options, hasLength(2));
    for (var index = 0; index < items.length; index++) {
      expect(identical(rows.single.options[index].target, items[index].target), isTrue);
      expect(rows.single.options[index].target!.sourceKey, 'fixture');
      expect(rows.single.options[index].target!.attributes!['options'], ['mv']);
    }
  });

  test('opaque category parameters are navigation, never joined with pipes', () {
    final rows = buildCategoryChipRows(data([
      FixedCategoryPart('Categories', [category('A', 'doujin'), category('B', null)]),
      FixedCategoryPart('Rank', [category('Rank', 'rank')]),
    ]), allLabel: 'All');
    expect(rows, hasLength(2));
    expect(rows.every((row) => !row.isFilter), isTrue);
    expect(combineCategoryChipParams(rows, {0: 'doujin', 1: 'rank'}, {}, null), isNull);
  });

  test('existing tag/class/isend filters and multi-tag base parameters survive', () {
    final rows = buildCategoryChipRows(data([
      FixedCategoryPart('Tags', [category('A', 'tag:A'), category('B', 'tag:B')]),
      FixedCategoryPart('Region', [category('Region', 'class:3')]),
      FixedCategoryPart('Status', [category('Status', 'isend:0')]),
    ]), allLabel: 'All');
    expect(rows.every((row) => row.isFilter), isTrue);
    expect(rows.first.isTagFilter, isTrue);
    expect(rows.first.options.first.target, isNull);
    final selected = <int, String?>{0: null, 1: 'class:3', 2: 'isend:0'};
    expect(combineCategoryChipParams(rows, selected, {'tag:A'}, 0), 'tag:A|class:3|isend:0');
    expect(combineCategoryChipParams(rows, selected, {'tag:A', 'tag:B'}, 0), 'class:3|isend:0');
    expect(combineCategoryChipParams(rows, {}, {}, 0), isNull);
  });

  test('duplicate titles do not overwrite filter selection', () {
    final rows = buildCategoryChipRows(data([
      FixedCategoryPart('Same', [category('Region', 'class:3')]),
      FixedCategoryPart('Same', [category('Status', 'isend:1')]),
    ]), allLabel: 'All');
    expect(rows[0].id, isNot(rows[1].id));
    expect(combineCategoryChipParams(rows, {0: 'class:3', 1: 'isend:1'}, {}, null), 'class:3|isend:1');
  });

  test('random category parts and empty groups are handled', () {
    final rows = buildCategoryChipRows(data([
      const FixedCategoryPart('Empty', []),
      RandomCategoryPart('Random', [search('A'), search('B')], 2),
    ]), allLabel: 'All');
    expect(rows, hasLength(1));
    expect(rows.single.id, 1);
    expect(rows.single.options, hasLength(2));
  });

  test('mixed search/category rows retain every original destination', () {
    final items = [category('A', 'tag:A'), search('B')];
    final rows = buildCategoryChipRows(data([FixedCategoryPart('Mixed', items)]), allLabel: 'All');
    expect(rows.single.isFilter, isFalse);
    expect(rows.single.options, hasLength(2));
    expect(rows.single.options[0].target!.page, 'category');
    expect(rows.single.options[1].target!.page, 'search');
  });
}
