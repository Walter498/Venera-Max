import 'package:flutter/material.dart';
import 'package:venera/components/components.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/home_layout.dart';
import 'package:venera/pages/search_page.dart';
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
  final String? param; // null = 全部
  const _FilterOption(this.label, this.param);
}

class _FilterRow {
  final String title;
  final List<_FilterOption> options;
  const _FilterRow(this.title, this.options);
}

class _CategoriesPageState extends State<CategoriesPage> {
  ComicSource? _source;
  List<_FilterRow> _rows = const [];
  final Map<String, String?> _selected = {}; // rowTitle -> param
  bool _expanded = false;

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
    // 優先用「首頁顯示源」裡第一個支援分類載入的源（栗子）
    ComicSource? found;
    for (final key in effectiveHomeDisplaySourceKeys()) {
      final s = ComicSource.find(key);
      if (s != null &&
          s.categoryComicsData != null &&
          s.categoryData != null) {
        found = s;
        break;
      }
    }
    found ??= ComicSource.all().firstWhere(
      (s) => s.categoryComicsData != null && s.categoryData != null,
      orElse: () => ComicSource.all().first,
    );
    _source = found;
    _buildRows();
    _reload();
  }

  void _buildRows() {
    final data = _source?.categoryData;
    if (data == null) return;
    final rows = <_FilterRow>[];
    for (final part in data.categories) {
      if (part is! FixedCategoryPart) continue;
      final options = <_FilterOption>[_FilterOption('全部'.tl, null)];
      var hasRealParam = false;
      for (final item in part.categories) {
        final param = item.target.attributes?['param']?.toString();
        // 「推薦 / 排行」類不是篩選條件，跳過
        if (param == 'rank') continue;
        options.add(_FilterOption(item.label, param));
        if (param != null) hasRealParam = true;
      }
      if (hasRealParam && options.length > 1) {
        rows.add(_FilterRow(part.title, options));
        _selected[part.title] = null;
      }
    }
    setState(() => _rows = rows);
  }

  /// 組合所有篩選行的參數：tag:格斗|class:3|isend:0
  String? get _combinedParam {
    final segs = <String>[];
    for (final row in _rows) {
      final p = _selected[row.title];
      if (p != null && p.isNotEmpty) segs.add(p);
    }
    if (segs.isEmpty) return null;
    return segs.join('|');
  }

  Future<void> _reload() async {
    setState(() {
      _comics = [];
      _page = 1;
      _hasMore = true;
      _error = null;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    final loader = _source?.categoryComicsData?.load;
    if (loader == null) return;
    _loading = true;
    try {
      final res = await loader('', _combinedParam, const <String>[], _page);
      if (!mounted) return;
      setState(() {
        if (res.success) {
          // 去重（源的翻頁可能回傳重複項）
          final ids = {for (final c in _comics) c.id};
          final fresh = [
            for (final c in res.data)
              if (!ids.contains(c.id)) c,
          ];
          _comics = [..._comics, ...fresh];
          _hasMore = res.data.isNotEmpty && _page < 50;
          _page++;
          _error = null;
        } else {
          _error = res.errorMessage;
          _hasMore = false;
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _hasMore = false;
        });
      }
    } finally {
      _loading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      child: SmoothCustomScrollView(
        controller: _scroll,
        slivers: [
          SliverToBoxAdapter(child: _buildSearchBar()),
          for (final row in _rows) SliverToBoxAdapter(child: _buildRow(row)),
          const SliverToBoxAdapter(child: Divider(height: 24)),
          if (_comics.isNotEmpty)
            SliverGridComics(comics: _comics, forceBriefMode: true),
          SliverToBoxAdapter(child: _buildFooter()),
        ],
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

  Widget _buildRow(_FilterRow row) {
    final selectedParam = _selected[row.title];
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
              selected: opt.param == selectedParam,
              onTap: () {
                setState(() => _selected[row.title] = opt.param);
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
