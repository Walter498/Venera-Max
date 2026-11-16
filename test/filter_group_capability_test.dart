import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/category_filter_plan.dart';

void main() {
  bool allows({bool server = true, String group = '主題A漫',
    List<String?> params = const [null, 'search:無修正', 'search:教師'],
    Set<String>? declared}) => filterGroupAllowsMultiple(
      hasServerLoader: server, group: group, params: params,
      declaredGroups: declared,
    );

  test('legacy JM: absent metadata does not disable search-tag multi-select', () {
    expect(allows(), isTrue);
  });
  test('explicit empty metadata is not the same as absent metadata', () {
    expect(allows(declared: {}), isFalse);
  });
  test('explicit group declarations are honored', () {
    expect(allows(declared: {'主題A漫'}), isTrue);
    expect(allows(group: '我的收藏', declared: {'主題A漫'}), isFalse);
  });
  test('plain loader or empty group is not server multi-filter capability', () {
    expect(allows(server: false), isFalse);
    expect(allows(params: [null]), isFalse);
  });
  test('native category keys must not accidentally enable same-row multi-select', () {
    expect(allows(params: [null, 'class:1', 'class:3']), isFalse);
    expect(allows(params: [null, 'tag:熱血', 'tag:冒險']), isFalse);
    expect(allows(params: ['hanman', 'search:教師']), isFalse);
  });
  test('all selected values reach category and search requests on every page', () {
    const a = CategoryFilterSelection(group: '主題A漫', label: '無修正',
      category: '無修正', param: 'search:無修正');
    const b = CategoryFilterSelection(group: '主題A漫', label: '教師',
      category: '教師', param: 'search:教師');
    const c = CategoryFilterSelection(group: '角色扮演', label: '御姐',
      category: '御姐', param: 'search:御姐');
    final selected = normalizeCategorySelections([a, b, c, a]);
    expect(selected.length, 3);
    for (final page in [1, 2]) {
      final category = CategoryFilterRequest(selections: selected,
        options: ['mr'], page: page).toJson();
      final search = SearchFilterRequest(keyword: '書名', selections: selected,
        options: ['mr'], page: page).toJson();
      expect(category['filters'], [a.toJson(), b.toJson(), c.toJson()]);
      expect(search['filters'], category['filters']);
      expect(search['keyword'], '書名');
      expect(category['page'], page);
    }
  });
}
