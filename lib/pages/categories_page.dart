import 'package:flutter/material.dart';
import 'package:venera/components/components.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/home_layout.dart';
import 'package:venera/foundation/category_filter_plan.dart';
import 'package:venera/foundation/res.dart';
import 'package:venera/utils/translations.dart';

/// Category page: source-native filter groups with one paged result query.
/// The host preserves each source's category/param values and delegates
/// multi-condition translation to the source when it explicitly supports it.
class CategoriesPage extends StatefulWidget {
  const CategoriesPage({super.key});

  @override
  State<CategoriesPage> createState() => _CategoriesPageState();
}

class _FilterOption {
  final String label;

  /// The source's own parameter for this item, passed through unchanged.
  final String? param;

  /// The source's own category name for this item (its native query target),
  /// never a synthesized one. Sources identify their queries by this value.
  final String nativeCategory;

  const _FilterOption(this.label, this.param, {required this.nativeCategory});
}

class _FilterRow {
  final String title;
  final List<_FilterOption> options;
  final bool allowsMulti;
  const _FilterRow(this.title, this.options, {this.allowsMulti = false});
}

class _CategoriesPageState extends State<CategoriesPage> {
  /// 可切換的源（有分類資料 + 分類載入器）：首頁顯示源排前面
  List<ComicSource> _availableSources = [];
  int _sourceIndex = 0;
  ComicSource? _source;
  List<_FilterRow> _rows = const [];
  /// Row title -> selected source-native params.
  /// Each row declares whether it is a multi-select group.
  final Map<String, Set<String>> _selected = {};
  final Set<String> _expandedRows = {};
  int _requestGeneration = 0;

  List<Comic> _comics = [];
  int _page = 1;
  bool _loading = false;
  bool _hasMore = true;
  String? _error;
  int? _total;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _initSource();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) {
        _loadMore();
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _initSource() {
    // 首頁顯示源裡支援分類的排前面，其餘支援分類的源排在後面
    final list = <ComicSource>[];
    final seen = <String>{};
    for (final key in effectiveHomeDisplaySourceKeys()) {
      final s = ComicSource.find(key);
      if (s != null &&
          s.categoryComicsData != null &&
          s.categoryData != null &&
          seen.add(s.key)) {
        list.add(s);
      }
    }
    for (final s in ComicSource.all()) {
      if (s.categoryComicsData != null &&
          s.categoryData != null &&
          seen.add(s.key)) {
        list.add(s);
      }
    }
    _availableSources = list;
    _sourceIndex = 0;
    _source = list.isNotEmpty ? list.first : null;
    _buildRows();
    _reload();
  }

  /// 切換源：篩選 chips 換成新源的分類，每行都保留「全部」，然後重載
  void _switchSource(int index) {
    if (index == _sourceIndex || index >= _availableSources.length) return;
    setState(() {
      _sourceIndex = index;
      _source = _availableSources[index];
      _selected.clear();
      _expandedRows.clear();
      _rows = const [];
      _optionsCache.clear();
    });
    _buildRows();
    _reload();
  }

  void _buildRows() {
    final data = _source?.categoryData;
    if (data == null) return;
    final rows = <_FilterRow>[];
    for (final part in data.categories) {
      if (part is! FixedCategoryPart) continue;
      final options = <_FilterOption>[
        _FilterOption('全部'.tl, null, nativeCategory: part.title),
      ];
      var hasRealParam = false;
      for (final item in part.categories) {
        final attr = item.target.attributes;
        final param = attr?['param']?.toString();
        // 「推薦 / 排行」類不是篩選條件，跳過
        if (param == 'rank') continue;
        options.add(
          _FilterOption(
            item.label,
            param,
            nativeCategory: attr?['category']?.toString() ?? part.title,
          ),
        );
        if (param != null) hasRealParam = true;
      }
      if (hasRealParam && options.length > 1) {
        final data = _source?.categoryComicsData;
        final allowsMulti = filterGroupAllowsMultiple(
          hasServerLoader: data?.loadWithFilters != null,
          group: part.title,
          params: options.map((option) => option.param),
          declaredGroups: data?.multiSelectGroups,
        );
        rows.add(_FilterRow(part.title, options, allowsMulti: allowsMulti));
        _selected[part.title] = <String>{};
      }
    }
    setState(() => _rows = rows);
  }

  /// The source's own option defaults (first value of each option list).
  /// These are loaded once per source/category page, not once per chip.
  final Map<String, List<String>> _optionsCache = {};

  List<String> _optionsFor(String rowTitle) => _optionsCache[rowTitle] ?? const [];

  Future<void> _loadOptionsForRows() async {
    final data = _source?.categoryComicsData;
    if (data == null) return;
    for (final row in _rows) {
      if (_optionsCache.containsKey(row.title)) continue;
      // Every option in a row shares the source's option list for that query.
      final native =
          row.options.firstWhere((o) => o.param != null, orElse: () => row.options.first)
              .nativeCategory;
      List<String> values = const [];
      try {
        if (data.optionsLoader != null) {
          final res = await data.optionsLoader!(native, row.options.first.param);
          if (res.success) {
            values = [
              for (final o in res.data)
                if (o.options.isNotEmpty) o.options.keys.first,
            ];
          }
        }
        if (values.isEmpty && data.options != null) {
          values = [
            for (final o in data.options!)
              if (o.options.isNotEmpty) o.options.keys.first,
          ];
        }
      } catch (_) {}
      _optionsCache[row.title] = values;
    }
  }

  /// Current selections keep the source-native values intact. The host does
  /// not merge params or intersect pages from unrelated requests.
  List<CategoryFilterSelection> get _selections {
    final result = <CategoryFilterSelection>[];
    for (final row in _rows) {
      final selected = _selected[row.title] ?? const <String>{};
      for (final param in selected) {
        final option = row.options.firstWhere(
          (o) => o.param == param,
          orElse: () => _FilterOption('', null, nativeCategory: row.title),
        );
        if (option.param == null || option.param!.trim().isEmpty) continue;
        result.add(CategoryFilterSelection(
          group: row.title,
          label: option.label,
          param: option.param,
          category: option.nativeCategory,
        ));
      }
    }
    return normalizeCategorySelections(result);
  }

  Future<void> _reload() async {
    ++_requestGeneration;
    setState(() {
      _comics = [];
      _page = 1;
      _hasMore = true;
      _loading = false;
      _error = null;
      _total = null;
    });
    await _loadOptionsForRows();
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    final data = _source?.categoryComicsData;
    if (data == null || _rows.isEmpty) return;
    final generation = _requestGeneration;
    final page = _page;
    final selections = _selections;
    final options = _optionsFor(_rows.first.title);
    if (selections.length > 1 && data.loadWithFilters == null) {
      setState(() {
        _error = '此來源未提供多條件分類查詢，請一次選擇一個條件';
        _hasMore = false;
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final Res<List<Comic>> res;
      if (data.loadWithFilters != null) {
        res = await data.loadWithFilters!(CategoryFilterRequest(
          selections: selections,
          options: options,
          page: page,
        ));
      } else {
        final selected = selections.firstOrNull;
        res = await data.load(
          selected?.category ?? _rows.first.title,
          selected?.param,
          options,
          page,
        );
      }
      if (!mounted || generation != _requestGeneration) return;
      if (!res.success) throw StateError(res.errorMessage ?? '載入失敗');
      _comics = [..._comics, ...res.data];
      _total = res.total;
      final more = res.data.isNotEmpty &&
          (res.subData is! int || page < (res.subData as int));
      setState(() {
        _hasMore = more;
        _page = page + 1;
        _error = null;
      });
    } catch (e) {
      if (mounted && generation == _requestGeneration) {
        setState(() {
          _error = e.toString();
          _hasMore = false;
        });
      }
    } finally {
      if (mounted && generation == _requestGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      child: SmoothCustomScrollView(
        controller: _scroll,
        slivers: [
          if (_availableSources.length > 1)
            SliverToBoxAdapter(child: _buildSourceTabs()),
          const SliverToBoxAdapter(child: SizedBox(height: 12)),
          for (final row in _rows) SliverToBoxAdapter(child: _buildRow(row)),
          if (_total != null || _comics.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text(
                  _total == null
                      ? '已載入 ${_comics.length} 本'
                      : '共 $_total 本 · 已載入 ${_comics.length} 本',
                  style: TextStyle(color: context.colorScheme.outline),
                ),
              ),
            ),
          const SliverToBoxAdapter(child: Divider(height: 24)),
          if (_comics.isNotEmpty)
            SliverGridComics(comics: _comics, forceBriefMode: true),
          SliverToBoxAdapter(child: _buildFooter()),
        ],
      ),
    );
  }

  /// 源切換列：橫向 chips，切換後下方篩選 chips 跟著換
  Widget _buildSourceTabs() {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        itemCount: _availableSources.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final selected = i == _sourceIndex;
          return InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => _switchSource(i),
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: selected
                    ? context.colorScheme.primaryContainer
                    : context.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Text(
                _availableSources[i].name,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  color: selected
                      ? context.colorScheme.primary
                      : context.colorScheme.onSurface,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildRow(_FilterRow row) {
    final allowsMulti = row.allowsMulti;
    final selectedParams = _selected[row.title] ?? <String>{};
    // Only a source-marked tag row is multi-select. Other rows mirror a
    // native single-select filter; the host must not guess their semantics.
    // 題材行（選項多）：預設顯示前 9 個 + 展開鈕；其他行全部平鋪
    final expandable = row.options.length > 10;
    final expanded = _expandedRows.contains(row.title);
    final visible = (expandable && !expanded)
        ? row.options.take(9).toList()
        : row.options;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final opt in visible)
            _chip(
              opt.label,
              selected: opt.param == null
                  ? selectedParams.isEmpty
                  : selectedParams.contains(opt.param),
              onTap: () {
                if (allowsMulti) {
                  // Explicit multi-select group: "全部" clears the group.
                  final selected = _selected.putIfAbsent(row.title, () => <String>{});
                  if (opt.param == null) {
                    selected.clear();
                  } else if (!selected.remove(opt.param)) {
                    selected.add(opt.param!);
                  }
                } else {
                  // Native single-select group: selecting a new item replaces
                  // the previous value instead of creating a guessed OR/AND.
                  final selected = _selected.putIfAbsent(row.title, () => <String>{});
                  selected
                    ..clear()
                    ..addAll(opt.param == null ? const <String>{} : {opt.param!});
                }
                setState(() {});
                _reload();
              },
            ),
          if (expandable)
            _expandChip(
              expanded ? '收起' : '展開',
              expanded: expanded,
              onTap: () => setState(() {
                if (expanded) {
                  _expandedRows.remove(row.title);
                } else {
                  _expandedRows.add(row.title);
                }
              }),
            ),
        ],
      ),
    );
  }

  Widget _expandChip(String label,
      {required bool expanded, required VoidCallback onTap}) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        width: 66,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: context.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label, style: TextStyle(color: context.colorScheme.onSurfaceVariant)),
            const SizedBox(width: 3),
            Icon(
              expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
              size: 15,
              color: context.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label,
      {required bool selected, required VoidCallback onTap}) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        width: 66,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? context.colorScheme.primaryContainer
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            color: selected
                ? context.colorScheme.primary
                : context.colorScheme.onSurface,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildFooter() {
    if (_error != null && _comics.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Column(children: [
          Text('載入失敗：$_error'),
          const SizedBox(height: 12),
          FilledButton(onPressed: _reload, child: const Text('重試')),
        ]),
      );
    }
    if (_comics.isEmpty && _loading) {
      return const Padding(
        padding: EdgeInsets.all(48),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_comics.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: _hasMore
              ? TextButton(onPressed: _loadMore, child: const Text('本頁未命中，繼續篩選下一頁'))
              : Text('沒有結果', style: TextStyle(color: context.colorScheme.outline)),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: _hasMore
            ? (_loading
                ? const CircularProgressIndicator()
                : TextButton(onPressed: _loadMore, child: const Text('載入更多')))
            : Text('沒有更多了',
                style: TextStyle(
                    fontSize: 12, color: context.colorScheme.outline)),
      ),
    );
  }
}
