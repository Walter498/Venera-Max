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
/// 去重規則：多個源出現【完全相同名字】（忽略空白、大小寫）的漫畫時
/// 只保留一個 —— 話數多的勝出（越多話排得越前），話數從副標題/簡介
/// 裡的「更新至N话 / 第N話 / N话」解析。
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

  /// 合併：按各源結果原順序排列；同名（正規化後相同）只留一個，
  /// 話數多的取代話數少的（排得越前）。
  List<Comic> _merge(List<List<Comic>> perSource) {
    final out = <Comic>[];
    final pos = <String, int>{};
    for (final comics in perSource) {
      for (final c in comics) {
        final nk = _normalize(c.title);
        final i = pos[nk];
        if (i == null) {
          pos[nk] = out.length;
          out.add(c);
        } else if (_chapterCount(c) > _chapterCount(out[i])) {
          out[i] = c;
        }
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
