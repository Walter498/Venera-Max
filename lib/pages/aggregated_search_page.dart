import "package:flutter/material.dart";
import "package:venera/components/components.dart";
import "package:venera/foundation/app.dart";
import "package:venera/foundation/appdata.dart";
import "package:venera/foundation/category_filter_plan.dart";
import "package:venera/foundation/comic_source/comic_source.dart";
import 'package:venera/foundation/comic_tag_enricher.dart';
import "package:venera/utils/translations.dart";

class AggregatedSearchPage extends StatefulWidget {
  const AggregatedSearchPage({super.key, required this.keyword, this.sourceKeys});

  final String keyword;
  final List<String>? sourceKeys;

  @override
  State<AggregatedSearchPage> createState() => _AggregatedSearchPageState();
}

class _AggregatedSearchPageState extends State<AggregatedSearchPage> {
  late final List<ComicSource> sources;

  late final SearchBarController controller;

  var _keyword = "";

  /// Tags the sources actually returned with their results.

  /// Tags the user picked. Filtering is applied to whatever the sources
  /// returned; tags a source never sends simply have nothing to match, and the
  /// sheet says so instead of pretending the filter succeeded.
  final Set<String> _tagFilter = {};

  final Map<String, Set<String>> _availableTagGroups = {};

  /// Bumped whenever the results change so the panel rebuilds with new tags.
  int _resultsRevision = 0;

  void _onResultsChanged() {
    if (mounted) setState(() => _resultsRevision++);
  }

  void _clearTagFilter() => setState(_tagFilter.clear);

  bool get _allSourcesSupportServerFilters =>
      sources.isNotEmpty &&
      sources.every((source) => source.searchPageData?.loadWithFilters != null);

  String? _groupForTag(String tag) {
    for (final entry in _availableTagGroups.entries) {
      if (entry.value.contains(tag)) return entry.key;
    }
    return null;
  }

  Widget buildFilterAction(Map<String, Set<String>> groups) {
    return IconButton(
      tooltip: "Filter by tag".tl,
      icon: Badge(isLabelVisible: _tagFilter.isNotEmpty, label: Text('${_tagFilter.length}'), child: Icon(_tagFilter.isEmpty ? Icons.filter_alt_outlined : Icons.filter_alt)),
      onPressed: () async {
        var picked = {..._tagFilter};
        await showModalBottomSheet(
          context: context, showDragHandle: true,
          builder: (sheet) => StatefulBuilder(builder: (context, setSheet) {
            return SizedBox(height: context.height * .68, child: Column(children: [
              ListTile(title: Text('Filter by tag'.tl), subtitle: Text('Source categories'.tl), trailing: TextButton(onPressed: () => setSheet(picked.clear), child: Text('Clear'.tl))),
              Expanded(child: groups.isEmpty ? Center(child: Text('This source provides no filter tags'.tl)) : ListView(padding: const EdgeInsets.symmetric(horizontal: 12), children: [
                for (final entry in groups.entries) ...[
                  Padding(padding: const EdgeInsets.fromLTRB(4,10,4,4), child: Text(entry.key, style: const TextStyle(fontWeight: FontWeight.w700))),
                  Wrap(spacing: 6, runSpacing: 6, children: [for (final tag in entry.value) FilterChip(label: Text(tag), selected: picked.contains(tag), onSelected: (on) => setSheet(() {
                                      if (on) {
                                        if (!_allSourcesSupportServerFilters) {
                                          picked.removeWhere((existing) =>
                                              _groupForTag(existing) == entry.key);
                                        }
                                        picked.add(tag);
                                      } else {
                                        picked.remove(tag);
                                      }
                                    }))]),
                ],
              ])),
              Padding(padding: const EdgeInsets.fromLTRB(16,4,16,16), child: SizedBox(width: double.infinity, child: FilledButton(onPressed: () { setState(() { _tagFilter..clear()..addAll(picked); }); Navigator.pop(sheet); }, child: Text('Apply'.tl))))
            ]));
          }),
        );
      },
    );
  }

  @override
  void initState() {
    var all = ComicSource.all()
        .where((e) => e.searchPageData != null)
        .map((e) => e.key)
        .toList();
    var settings = widget.sourceKeys ?? (appdata.settings['searchSources'] as List);
    var sources = <String>[];
    for (var source in settings) {
      if (all.contains(source)) {
        sources.add(source);
      }
    }
    this.sources = sources.map((e) => ComicSource.find(e)!).toList();
    _keyword = widget.keyword;
    // Aggregated search also feeds the shared search history; without this,
    // searches run in aggregated mode never showed up under recent searches.
    if (widget.keyword.trim().isNotEmpty) {
      appdata.addSearchHistory(widget.keyword);
    }
    controller = SearchBarController(
      currentText: widget.keyword,
      onSearch: (text) {
        if (text.trim().isNotEmpty) {
          appdata.addSearchHistory(text);
        }
        setState(() {
          _keyword = text;
        });
      },
    );
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return SmoothCustomScrollView(
      scrollbarTopPadding: context.padding.top + 56,
      slivers: [
        SliverSearchBar(
          controller: controller,
          action: buildFilterAction(_availableTagGroups),
        ),
        // 2026-09-16 改版：所有源結果合併成單一直落列表（不再按源分行橫滑）
        _MergedSearchResults(
          key: ValueKey('$_keyword\u0000$_resultsRevision'),
          sources: sources,
          keyword: _keyword,
          tagFilter: _tagFilter,
          onAvailableTags: (tags) {
            if (!mounted) return;
            setState(() {
              _availableTagGroups.clear();
              for (final source in sources) {
                final data = source.categoryData;
                if (data == null) continue;
                for (final part in data.categories) {
                  final labels = <String>{};
                  for (final item in part.categories) {
                    if (item.target.attributes?['param'] != null) labels.add(item.label.trim());
                  }
                  if (labels.isNotEmpty) _availableTagGroups.putIfAbsent(part.title, () => <String>{}).addAll(labels);
                }
              }
              // A selected tag that is no longer present must not keep
              // filtering everything out silently.
              final allTags = _availableTagGroups.values.expand((e) => e).toSet();
              _tagFilter.removeWhere((t) => !allTags.contains(t));
            });
          },
          onChanged: _onResultsChanged,
          filterActionBuilder: buildFilterAction,
        ),
      ],
    );
  }
}

/// 聚合搜索結果：所有源並行搜索，結果合併成單一直落列表（詳細模式，
/// 卡片上會標示來源）。
///
/// 排序規則：先按搜索結果輪詢混排；同名（重名，忽略空白/大小寫）的
/// 全部保留並收攏一處，組內按【真實話數】降序（背景 loadInfo 數章節表，
/// 不依賴源文件；失敗退回副標題/簡介的「更新至N话」文字解析）。
class _MergedSearchResults extends StatefulWidget {
  const _MergedSearchResults({
    super.key,
    required this.sources,
    required this.keyword,
    this.tagFilter = const <String>{},
    this.onAvailableTags,
    this.onChanged,
    this.filterActionBuilder,
  });

  final List<ComicSource> sources;
  final String keyword;
  final Set<String> tagFilter;
  final void Function(Map<String, Set<String>> groups)? onAvailableTags;
  final VoidCallback? onChanged;
  final Widget Function(Map<String, Set<String>> availableGroups)? filterActionBuilder;

  @override
  State<_MergedSearchResults> createState() => _MergedSearchResultsState();
}

class _MergedSearchResultsState extends State<_MergedSearchResults> {
  bool _loading = true;
  List<Comic> _merged = const [];
  int _failedSources = 0;

  /// 同名組成員的【真實話數】（loadInfo 數出來的）：'sourceKey:id' -> 話數
  final Map<String, int> _chapterCounts = {};
  final Set<String> _serverFilteredSources = {};

  List<CategoryFilterSelection> _filtersFor(ComicSource source) {
    final data = source.categoryData;
    if (data == null) return const [];
    final result = <CategoryFilterSelection>[];
    for (final part in data.categories) {
      if (part is! FixedCategoryPart) continue;
      for (final item in part.categories) {
        final label = item.label.trim();
        if (!widget.tagFilter.contains(label)) continue;
        final attr = item.target.attributes;
        final param = attr?["param"]?.toString();
        if (param == null || param == 'rank') continue;
        result.add(CategoryFilterSelection(
          group: part.title,
          label: label,
          param: param,
          category: attr?["category"]?.toString() ?? part.title,
        ));
      }
    }
    return normalizeCategorySelections(result);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<List<Comic>?> _searchOne(ComicSource source) async {
    try {
      final data = source.searchPageData!;
      final options =
          (data.searchOptions ?? []).map((e) => e.defaultValue).toList();
      final filters = _filtersFor(source);
      if (filters.isNotEmpty && data.loadWithFilters != null) {
        _serverFilteredSources.add(source.key);
        final res = await data.loadWithFilters!(SearchFilterRequest(
          keyword: widget.keyword,
          selections: filters,
          options: options,
          page: 1,
        ));
        return res.error ? null : res.data;
      }
      if (data.loadPage != null) {
        final res = await data.loadPage!(widget.keyword, 1, options);
        return res.error ? null : res.data;
      } else if (data.loadNext != null) {
        final res = await data.loadNext!(widget.keyword, null, options);
        return res.error ? null : res.data;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _load() async {
    // 所有源同時開搜，耗時 = 最慢的源，而不是相加
    final results =
        await Future.wait([for (final s in widget.sources) _searchOne(s)]);
    if (!mounted) return;
    var failed = 0;
    final perSource = <List<Comic>>[];
    for (final r in results) {
      if (r == null) {
        failed++;
      } else {
        perSource.add(r);
      }
    }
    setState(() {
      _merged = _merge(perSource);
      _failedSources = failed;
      _loading = false;
    });
    final groups = <String, Set<String>>{};
    for (final source in widget.sources) {
      final data = source.categoryData;
      if (data == null) continue;
      for (final part in data.categories) {
        if (part is! FixedCategoryPart) continue;
        final tags = groups.putIfAbsent(part.title, () => <String>{});
        for (final item in part.categories) {
          if (item.target.attributes?["param"] != null) tags.add(item.label.trim());
        }
      }
    }
    widget.onAvailableTags?.call(groups);
    // Detail tags are source-agnostic and may be richer than search cards.
    await Future.wait([for (final comic in _merged) ComicTagEnricher.instance.enrich(comic)]);
    if (mounted) setState(() {});
    // 背景校準：同名組用 loadInfo 數【真實話數】重排（不阻塞首屏）
    _resolveChapterCounts();
  }

  /// 背景校準：對「多源同名」的組，逐一調 loadInfo 數章節表
  /// （任何源都數得到，不依賴源在搜索結果裡寫話數），話數多的排前。
  Future<void> _resolveChapterCounts() async {
    final groups = <String, List<int>>{};
    for (var i = 0; i < _merged.length; i++) {
      groups.putIfAbsent(_normalize(_merged[i].title), () => []).add(i);
    }
    final dups = [for (final g in groups.values) if (g.length > 1) g];
    if (dups.isEmpty) return;
    var changed = false;
    await Future.wait(dups.map((idxList) async {
      final counts =
          await Future.wait(idxList.map((i) => _realChapterCount(_merged[i])));
      // 存起來給卡片顯示（同名組每張卡標自己的話數）
      for (var k = 0; k < idxList.length; k++) {
        final c = _merged[idxList[k]];
        if (counts[k] > 0) _chapterCounts['${c.sourceKey}:${c.id}'] = counts[k];
      }
      final order = List.generate(idxList.length, (k) => k)
        ..sort((a, b) => counts[b].compareTo(counts[a]));
      // 有變化才重排（避免無謂的跳動）
      if (!List.generate(order.length, (k) => k)
          .every((k) => order[k] == k)) {
        final sorted = [for (final k in order) _merged[idxList[k]]];
        for (var k = 0; k < idxList.length; k++) {
          _merged[idxList[k]] = sorted[k];
        }
        changed = true;
      }
    }));
    if (changed && mounted) setState(() {});
  }

  /// Every tag the loaded results actually carry. Sources that send none
  /// contribute nothing here, which the filter sheet reports rather than
  /// pretending a tag filter is available.
  Set<String> _collectTags() => {
    for (final c in _merged)
      for (final tag in c.tags ?? const <String>[])
        if (tag.trim().isNotEmpty) tag.trim(),
  };

  bool _matchesTags(Comic c) {
    if (widget.tagFilter.isEmpty || _serverFilteredSources.contains(c.sourceKey)) {
      return true;
    }
    return widget.tagFilter.every((wanted) =>
        ComicTagEnricher.instance
            .tagsFor(c)
            .any((actual) => categoryTagMatches(actual, wanted)));
  }

  /// 真實話數：loadInfo → 章節表條目數；loadInfo 失敗退回文字解析
  Future<int> _realChapterCount(Comic c) async {
    try {
      final loader = ComicSource.find(c.sourceKey)?.loadComicInfo;
      if (loader != null) {
        final res = await loader(c.id);
        if (res.success) {
          final n = res.data.chapters?.allChapters.length;
          if (n != null && n > 0) return n;
        }
      }
    } catch (_) {}
    return _chapterCount(c);
  }

  /// 正規化名字：去首尾空白、去所有空格（含全形）、轉小寫
  String _normalize(String title) =>
      title.trim().toLowerCase().replaceAll(RegExp(r'[\s　]+'), '');

  /// 從副標題 / 簡介解析話數（更新至N话、第N話、N话），取最大值；沒有 = 0
  int _chapterCount(Comic c) {
    final text = '${c.subtitle ?? ''} ${c.description}';
    var maxN = 0;
    for (final m in RegExp(r'(\d+)\s*[话話]').allMatches(text)) {
      final n = int.tryParse(m.group(1)!) ?? 0;
      if (n > maxN) maxN = n;
    }
    return maxN;
  }

  /// 合併規則（2026-09-16 用戶定稿）：
  /// ① 先用搜索結果排序：輪詢交錯（每個源的第 1 名、第 2 名…），
  ///    把所有源當【同一個源】一樣混排
  /// ② 同名（重名）的全部保留，一本都不刪
  /// ③ 同名的收攏到一處（第一次出現的位置），組內按話數降序；
  ///    先按文字解析排，背景 loadInfo 校準真實話數後再重排
  List<Comic> _merge(List<List<Comic>> perSource) {
    // ① 輪詢交錯
    final flat = <Comic>[];
    var rank = 0;
    var any = true;
    while (any) {
      any = false;
      for (final comics in perSource) {
        if (rank < comics.length) {
          any = true;
          flat.add(comics[rank]);
        }
      }
      rank++;
    }
    // ②③ 同名組收攏（組內先按文字話數降序）
    final groups = <String, List<Comic>>{};
    for (final c in flat) {
      groups.putIfAbsent(_normalize(c.title), () => []).add(c);
    }
    final out = <Comic>[];
    final emitted = <String>{};
    for (final c in flat) {
      final nk = _normalize(c.title);
      final g = groups[nk]!;
      if (g.length == 1) {
        out.add(c);
        continue;
      }
      if (emitted.add(nk)) {
        g.sort((a, b) => _chapterCount(b).compareTo(_chapterCount(a)));
        out.addAll(g);
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(48),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (_merged.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Center(child: Text("No search results found".tl)),
        ),
      );
    }
    final visible = [for (final c in _merged) if (_matchesTags(c)) c];
    if (visible.isEmpty && widget.tagFilter.isNotEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: Text(
              "No result carries all the selected tags".tl,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    return SliverMainAxisGroup(
      slivers: [
        if (_failedSources > 0)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                '$_failedSources 個源搜索失敗',
                style: TextStyle(
                    fontSize: 12, color: context.colorScheme.outline),
              ),
            ),
          ),
        // 詳細模式直落列表（與單源搜索結果同一種卡片，含來源標示）；
        // 同名組的卡片額外顯示【真實話數】行
        SliverGridComics(
          comics: visible,
          forceDetailedMode: true,
          chapterCountBuilder: (c) {
            final n = _chapterCounts['${c.sourceKey}:${c.id}'];
            return n != null ? '$n' : null;
          },
        ),
      ],
    );
  }
}
