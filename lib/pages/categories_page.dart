import 'package:flutter/material.dart';
import 'package:venera/components/components.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/home_layout.dart';
import 'package:venera/foundation/res.dart';
import 'package:venera/utils/translations.dart';

/// 分類頁（2026-09-16 改版：仿栗子官方 App 圖一佈局）
/// 頂部搜索框 → 題材 / 地區 / 狀態篩選 chips → 即時結果網格（可翻頁）。
/// 篩選條件可組合（tag: X|class: Y|isend: Z），組合參數由源端解析
/// （栗子源 v2.25.0+ 支援；其他源選單一條件時正常，多條件視源而定）。
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
  const _FilterRow(this.title, this.options);
}

class _CategoriesPageState extends State<CategoriesPage> {
  /// 可切換的源（有分類資料 + 分類載入器）：首頁顯示源排前面
  List<ComicSource> _availableSources = [];
  int _sourceIndex = 0;
  ComicSource? _source;
  List<_FilterRow> _rows = const [];
  final Map<String, Set<String>> _selected = {}; // rowTitle -> param（單選行用）
  /// 題材行（tag:）多選集合（2026-09-17 用戶要求：標籤可多選）
  final Set<String> _selectedTags = {};
  String? _tagRowTitle;
  bool _expanded = false;
  int _requestGeneration = 0;

  List<Comic> _comics = [];
  int _page = 1;
  bool _loading = false;
  bool _hasMore = true;
  String? _error;
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
      _selectedTags.clear();
      _tagRowTitle = null;
      _expanded = false;
      _rows = const [];
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
        rows.add(_FilterRow(part.title, options));
        _selected[part.title] = <String>{};
        // 題材行（參數是 tag: 開頭的）支持多選
        if (_tagRowTitle == null &&
            options.any((o) => o.param?.startsWith('tag:') == true)) {
          _tagRowTitle = part.title;
        }
      }
    }
    setState(() => _rows = rows);
  }

  /// One source-native query: the category name and param the source itself
  /// defines, plus the options list that source expects. Nothing here is
  /// synthesized from another source's protocol.
  ({String category, String? param, List<String> options})? _queryFor(
    _FilterRow row,
    String param,
  ) {
    final opt = row.options.firstWhere(
      (o) => o.param == param,
      orElse: () => _FilterOption('', '', nativeCategory: row.title),
    );
    return (
      category: opt.nativeCategory,
      param: opt.param,
      options: _optionsFor(row.title),
    );
  }

  /// The source's own option defaults (first value of each option list), so a
  /// loader that reads `options[0]` receives a real value instead of nothing.
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

  /// Params selected in [row]. The tag row keeps its selection in
  /// [_selectedTags]; every other row in [_selected]. Both are read here so a
  /// tag pick actually reaches the source and the intersection.
  Set<String> _rowParams(String title) => title == _tagRowTitle
      ? _selectedTags
      : (_selected[title] ?? const <String>{});

  /// Selected (row, param) pairs, in row order.
  List<({_FilterRow row, String param})> get _selectedPairs => [
    for (final row in _rows)
      for (final param in _rowParams(row.title))
        (row: row, param: param),
  ];

  /// Per-query accumulated results, keyed by 'category\u0000param'. Keeping
  /// them per query (rather than one merged list) is what lets a row union its
  /// selections and different rows intersect without losing pagination.
  final Map<String, List<Comic>> _byQuery = {};
  final Map<String, bool> _queryHasMore = {};

  static String _queryKey(String category, String? param) =>
      '$category\u0000${param ?? ''}';

  /// Union within each row, intersect across rows. A row with nothing selected
  /// is not a constraint.
  List<Comic> _applyFilters() {
    final rows = <List<Comic>>[];
    for (final row in _rows) {
      final params = _rowParams(row.title);
      if (params.isEmpty) continue;
      final union = <String, Comic>{};
      for (final param in params) {
        final opt = row.options.firstWhere(
          (o) => o.param == param,
          orElse: () => _FilterOption('', '', nativeCategory: row.title),
        );
        for (final c in _byQuery[_queryKey(opt.nativeCategory, opt.param)] ?? const <Comic>[]) {
          union['${c.sourceKey}:${c.id}'] = c;
        }
      }
      rows.add(union.values.toList());
    }
    if (rows.isEmpty) {
      final all = <String, Comic>{};
      for (final list in _byQuery.values) {
        for (final c in list) {
          all['${c.sourceKey}:${c.id}'] = c;
        }
      }
      return all.values.toList();
    }
    var kept = rows.first;
    for (var i = 1; i < rows.length; i++) {
      final keys = {for (final c in rows[i]) '${c.sourceKey}:${c.id}'};
      kept = [for (final c in kept) if (keys.contains('${c.sourceKey}:${c.id}')) c];
    }
    return kept;
  }

  bool get _anyQueryHasMore => _queryHasMore.values.any((v) => v);

  Future<void> _reload() async {
    ++_requestGeneration;
    _byQuery.clear();
    _queryHasMore.clear();
    setState(() {
      _comics = [];
      _page = 1;
      _hasMore = true;
      _loading = false;
      _error = null;
    });
    await _loadOptionsForRows();
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    final loader = _source?.categoryComicsData?.load;
    if (loader == null) return;
    final generation = _requestGeneration;
    final page = _page;
    var pairs = _selectedPairs;
    if (pairs.isEmpty) {
      // Nothing selected: the source's own default listing, unchanged.
      final first = _rows.isNotEmpty ? _rows.first : null;
      if (first == null) return;
      pairs = [(row: first, param: '')];
    }
    setState(() => _loading = true);
    try {
      var anyMore = false;
      for (final pair in pairs) {
        final opt = pair.row.options.firstWhere(
          (o) => o.param == pair.param,
          orElse: () => _FilterOption('', '', nativeCategory: pair.row.title),
        );
        final key = _queryKey(opt.nativeCategory, opt.param);
        if (_queryHasMore[key] == false) continue;
        final res = await loader(
          opt.nativeCategory,
          opt.param,
          _optionsFor(pair.row.title),
          page,
        );
        if (!mounted || generation != _requestGeneration) return;
        if (!res.success) throw StateError(res.errorMessage ?? '載入失敗');
        (_byQuery[key] ??= []).addAll(res.data);
        final more = res.data.isNotEmpty &&
            (res.subData is! int || page < (res.subData as int));
        _queryHasMore[key] = more;
        if (more) anyMore = true;
      }
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _comics = _applyFilters();
        _hasMore = anyMore;
        _page = page + 1;
        _error = null;
      });
    } catch (e) {
      if (mounted && generation == _requestGeneration) {
        setState(() { _error = e.toString(); _hasMore = false; });
      }
    } finally {
      if (mounted && generation == _requestGeneration) {
        setState(() => _loading = false);
        if (_comics.isEmpty && _hasMore && _selectedPairs.isNotEmpty && _page < 50) {
          Future.microtask(_loadMore);
        }
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
          for (final row in _rows) SliverToBoxAdapter(child: _buildRow(row)),
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
    final selectedParams = _selected[row.title] ?? <String>{};
    // 題材行（選項多）：預設顯示前 9 個 + 展開鈕；其他行全部平鋪
    final expandable = row.options.length > 10;
    final visible = (expandable && !_expanded)
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
              selected: row.title == _tagRowTitle
                  ? (opt.param == null
                      ? _selectedTags.isEmpty
                      : _selectedTags.contains(opt.param))
                  : (opt.param == null ? selectedParams.isEmpty : selectedParams.contains(opt.param)),
              onTap: () {
                if (row.title == _tagRowTitle) {
                  // 題材行：多選切換；「全部」= 清空選擇
                  if (opt.param == null) {
                    _selectedTags.clear();
                  } else if (!_selectedTags.remove(opt.param)) {
                    _selectedTags.add(opt.param!);
                  }
                  _selected[row.title] = <String>{};
                } else {
                  final selected = _selected.putIfAbsent(row.title, () => <String>{});
                  if (opt.param == null) {
                    selected.clear();
                  } else if (!selected.remove(opt.param)) {
                    selected.add(opt.param!);
                  }
                }
                setState(() {});
                _reload();
              },
            ),
          if (expandable)
            _chip(
              _expanded ? '收起' : '展開 ▾',
              selected: false,
              onTap: () => setState(() => _expanded = !_expanded),
            ),
        ],
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
