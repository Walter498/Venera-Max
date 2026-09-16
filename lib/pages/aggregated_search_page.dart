import "package:flutter/material.dart";
import "package:venera/components/components.dart";
import "package:venera/foundation/app.dart";
import "package:venera/foundation/appdata.dart";
import "package:venera/foundation/comic_source/comic_source.dart";
import "package:venera/utils/translations.dart";

class AggregatedSearchPage extends StatefulWidget {
  const AggregatedSearchPage({super.key, required this.keyword});

  final String keyword;

  @override
  State<AggregatedSearchPage> createState() => _AggregatedSearchPageState();
}

class _AggregatedSearchPageState extends State<AggregatedSearchPage> {
  late final List<ComicSource> sources;

  late final SearchBarController controller;

  var _keyword = "";

  @override
  void initState() {
    var all = ComicSource.all()
        .where((e) => e.searchPageData != null)
        .map((e) => e.key)
        .toList();
    var settings = appdata.settings['searchSources'] as List;
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
        SliverSearchBar(controller: controller),
        // 2026-09-16 改版：所有源結果合併成單一直落列表（不再按源分行橫滑）
        _MergedSearchResults(
          key: ValueKey(_keyword),
          sources: sources,
          keyword: _keyword,
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
  });

  final List<ComicSource> sources;
  final String keyword;

  @override
  State<_MergedSearchResults> createState() => _MergedSearchResultsState();
}

class _MergedSearchResultsState extends State<_MergedSearchResults> {
  bool _loading = true;
  List<Comic> _merged = const [];
  int _failedSources = 0;

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
        // 詳細模式直落列表（與單源搜索結果同一種卡片，含來源標示）
        SliverGridComics(comics: _merged, forceDetailedMode: true),
      ],
    );
  }
}
