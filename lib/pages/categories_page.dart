import 'package:flutter/material.dart';
import 'package:venera/components/components.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/category_chip_rows.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/home_layout.dart';
import 'package:venera/pages/search_page.dart';
import 'package:venera/utils/translations.dart';

/// 分類頁：保留來源定義的所有分組與原生搜尋／分類跳轉。
/// tag/class/isend 編碼篩選保留即時網格與多選交集；其他來源參數
/// 視為不透明值，交由原生目的頁處理，避免自行拼接造成查詢錯誤。
class CategoriesPage extends StatefulWidget {
  const CategoriesPage({super.key});

  @override
  State<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends State<CategoriesPage> {
  /// 可切換的源（有分類資料）：首頁顯示源排前面
  List<ComicSource> _availableSources = [];
  int _sourceIndex = 0;
  ComicSource? _source;
  List<CategoryChipRow> _rows = const [];
  final Map<int, String?> _selected = {};
  final Set<String> _selectedTags = {};
  int? _tagRowId;
  final Set<int> _expandedRows = {};
  int _loadGeneration = 0;

  bool get _hasInlineFilters => _rows.any((row) => row.isFilter);

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
          s.categoryData != null &&
          seen.add(s.key)) {
        list.add(s);
      }
    }
    for (final s in ComicSource.all()) {
      if (s.categoryData != null &&
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

  /// 切換源時重建分組並清除舊源的選擇與展開狀態。
  void _switchSource(int index) {
    if (index == _sourceIndex || index >= _availableSources.length) return;
    setState(() {
      _sourceIndex = index;
      _source = _availableSources[index];
      _selected.clear();
      _selectedTags.clear();
      _tagRowId = null;
      _expandedRows.clear();
      _rows = const [];
    });
    _buildRows();
    _reload();
  }

  void _buildRows() {
    final data = _source?.categoryData;
    final rows = data == null
        ? <CategoryChipRow>[]
        : buildCategoryChipRows(data, allLabel: '全部'.tl);
    _selected.clear();
    _selectedTags.clear();
    _tagRowId = null;
    for (final row in rows.where((row) => row.isFilter)) {
      _selected[row.id] = null;
      if (_tagRowId == null && row.isTagFilter) _tagRowId = row.id;
    }
    setState(() => _rows = rows);
  }

  String? get _combinedParam =>
      combineCategoryChipParams(_rows, _selected, _selectedTags, _tagRowId);

  Future<void> _reload() async {
    _loadGeneration++;
    setState(() {
      _loading = false;
      _comics = [];
      _page = 1;
      _hasMore = true;
      _error = null;
    });
    if (!_hasInlineFilters) {
      setState(() => _hasMore = false);
      return;
    }
    if (_selectedTags.length >= 2) {
      await _loadMultiTags();
    } else {
      await _loadMore();
    }
  }

  /// 題材多選：每個標籤並行抓一頁，取【交集】（同時帶全部選中標籤的漫畫）
  Future<void> _loadMultiTags() async {
    final loader = _source?.categoryComicsData?.load;
    if (loader == null) return;
    final generation = _loadGeneration;
    setState(() => _loading = true);
    try {
      // 非題材條件照樣組合進每個請求
      final base = combineCategoryChipParams(_rows, _selected, {}, _tagRowId) ?? '';
      final results = await Future.wait([
        for (final t in _selectedTags)
          loader('', base.isEmpty ? t : '$t|$base', const <String>[], 1),
      ]);
      if (!mounted || generation != _loadGeneration) return;
      Map<String, Comic>? inter;
      for (final r in results) {
        if (!r.success) throw StateError(r.errorMessage ?? 'Tag load failed');
        final m = {for (final c in r.data) c.id: c};
        inter = inter == null
            ? m
            : (Map.fromEntries(
                inter.entries.where((e) => m.containsKey(e.key))));
      }
      setState(() {
        _comics = inter?.values.toList() ?? [];
        _hasMore = false; // 多選交集模式不分頁
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _error = e.toString();
          _loading = false;
          _hasMore = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore || !_hasInlineFilters) return;
    final loader = _source?.categoryComicsData?.load;
    if (loader == null) return;
    final generation = _loadGeneration;
    final page = _page;
    final param = _combinedParam;
    setState(() => _loading = true);
    try {
      final res = await loader('', param, const <String>[], page);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        if (res.success) {
          // 去重（源的翻頁可能回傳重複項）
          final ids = {for (final c in _comics) c.id};
          final fresh = [
            for (final c in res.data)
              if (!ids.contains(c.id)) c,
          ];
          _comics = [..._comics, ...fresh];
          final maxPage = res.subData;
          _hasMore = res.data.isNotEmpty &&
              page < 50 &&
              (maxPage is! int || page < maxPage);
          _page++;
          _error = null;
        } else {
          _error = res.errorMessage;
          _hasMore = false;
        }
      });
    } catch (e) {
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _error = e.toString();
          _hasMore = false;
        });
      }
    } finally {
      if (mounted && generation == _loadGeneration) {
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
          SliverToBoxAdapter(child: _buildSearchBar()),
          for (final row in _rows) SliverToBoxAdapter(child: _buildRow(row)),
          if (_hasInlineFilters) ...[
            const SliverToBoxAdapter(child: Divider(height: 24)),
            if (_comics.isNotEmpty)
              SliverGridComics(comics: _comics, forceBriefMode: true),
            SliverToBoxAdapter(child: _buildFooter()),
          ],
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

  /// 假搜索框：點了跳真正的搜索頁
  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => context.to(() => const SearchPage()),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: context.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(children: [
            Icon(Icons.search, size: 20, color: context.colorScheme.outline),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '搜漫畫 作者名',
                style: TextStyle(color: context.colorScheme.outline),
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: context.colorScheme.primary,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Text('搜索'.tl,
                  style: TextStyle(
                      color: context.colorScheme.onPrimary, fontSize: 13)),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildRow(CategoryChipRow row) {
    final selectedParam = _selected[row.id];
    final expandable = row.options.length > 10;
    final expanded = _expandedRows.contains(row.id);
    final visible = (expandable && !expanded)
        ? row.options.take(9).toList()
        : row.options;
    return Padding(
      key: ValueKey('category-row-${row.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (row.title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
              child: Text(row.title.ts(_source!.key),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final opt in visible)
                _chip(
                  opt.label.ts(_source!.key),
                  selected: row.isFilter && (row.id == _tagRowId
                      ? (opt.param == null
                          ? _selectedTags.isEmpty
                          : _selectedTags.contains(opt.param))
                      : opt.param == selectedParam),
                  onTap: () {
                    if (!row.isFilter) {
                      // Let the native destination load source-specific options.
                      opt.target?.jump(context);
                      return;
                    }
                    if (row.id == _tagRowId) {
                      if (opt.param == null) {
                        _selectedTags.clear();
                      } else if (!_selectedTags.remove(opt.param)) {
                        _selectedTags.add(opt.param!);
                      }
                      _selected[row.id] = null;
                    } else {
                      _selected[row.id] = opt.param;
                    }
                    setState(() {});
                    _reload();
                  },
                ),
              if (expandable)
                _chip(
                  expanded ? '收起' : '展開 ▾',
                  selected: false,
                  onTap: () => setState(() {
                    if (!_expandedRows.remove(row.id)) _expandedRows.add(row.id);
                  }),
                ),
            ],
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
        constraints: const BoxConstraints(minWidth: 66, minHeight: 36),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? context.colorScheme.primaryContainer
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
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
          child: Text('沒有結果',
              style: TextStyle(color: context.colorScheme.outline)),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: _hasMore
            ? (_loading
                ? const CircularProgressIndicator()
                : const SizedBox.shrink())
            : Text('沒有更多了',
                style: TextStyle(
                    fontSize: 12, color: context.colorScheme.outline)),
      ),
    );
  }
}
