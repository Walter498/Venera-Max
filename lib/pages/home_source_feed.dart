import 'dart:math';

import 'package:flutter/material.dart';
import 'package:venera/components/components.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/home_layout.dart';
import 'package:venera/pages/rank_updates_page.dart';
import 'package:venera/pages/search_page.dart';
import 'package:venera/utils/ext.dart';
import 'package:venera/utils/translations.dart';

/// ⑩ 首頁「源內容」區塊：把「首頁顯示源」的推薦內容直接鋪在首頁。
///
/// 對應設計圖（圖七）：頂部源分頁 → 分區標題 → 三列網格 → 「换一换 / 更多」。
/// 內容來自每個源自己的探索頁資料（multiPart 探索頁的每個 part 就是一個分區）。
class HomeSourceFeed extends StatefulWidget {
  const HomeSourceFeed({super.key});

  @override
  State<HomeSourceFeed> createState() => _HomeSourceFeedState();
}

/// 每個分區最多顯示幾部漫畫（4 列 x 2 排）。
const int kHomeFeedMaxPerSection = 8;

/// 周期更新：4 列 x 2 排。
const int kHomeWeekdayMaxPerSection = 8;

/// 首頁分區固定 4 列。
const int kHomeFeedColumns = 4;

class _HomeSourceFeedState extends State<HomeSourceFeed> {
  int _selected = 0;
  bool _loading = false;
  String? _error;
  List<ExplorePagePart> _parts = const [];

  static const _weekdayNames = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"];

  /// 首頁快取：整個源的探索結果（推薦 + 周一~周日）一次存一次讀，
  /// 「全有全無」，不會只緩一半。⟳ 按鈕會清掉它並重抓。
  static final Map<String, ({DateTime time, List<ExplorePagePart> parts})>
  _cache = {};

  static const _cacheTtl = Duration(minutes: 10);

  /// 「换一换」用：換個種子 = 換一批推薦（立即有變化，不依賴網路）。
  /// 每個分區【獨立種子】：點推荐的换一换不會連動刷新周期更新。
  final Map<String, int> _seeds = {};
  int _seedFor(String partTitle) => _seeds[partTitle] ?? 0;

  /// 周期更新目前選中的星期（0 = 周一）。
  int _weekday = 0;

  /// 標題是不是星期幾（支援周/週、星期一）。回傳 0..6（周一=0）。
  int? _weekdayOf(String title) {
    final t = title.replaceAll("週", "周").replaceAll(" ", "").trim();
    if (t == "周天") return 6;
    for (var i = 0; i < _weekdayNames.length; i++) {
      final n = _weekdayNames[i].substring(1);
      if (t == "周$n" || t == "星期$n") return i;
    }
    return null;
  }

  /// 推薦分區（非星期分區）。
  List<ExplorePagePart> get _recommendParts =>
      [for (final p in _parts) if (_weekdayOf(p.title) == null) p];

  /// 星期分區，按周一..周日排好（缺的就跳過）。
  List<(int, ExplorePagePart)> get _weekdayParts => [
    for (final p in _parts)
      if (_weekdayOf(p.title) != null) (_weekdayOf(p.title)!, p),
  ]..sort((a, b) => a.$1.compareTo(b.$1));

  /// 其他「首頁顯示源」中要併進推薦池的分區標題（例如騰訊動漫的
  /// 「条漫」「独家」）。找不到這些標題時，退回該源的第一個分區。
  static const _mergePartTitles = ["条漫", "條漫", "独家", "獨家"];

  /// 收集「其他源」的推薦內容，併進首頁推薦池，讓 ⟳ 换一换 能輪到
  /// 不同來源的作品（栗子 + 騰訊動漫 …）。
  /// 提速：所有源的請求【並行發射】，耗時 ≈ 最慢的一個源，而不是相加。
  Future<List<Comic>> _collectCrossSourceComics(String currentKey) async {
    final merged = <Comic>[];
    final seen = <String>{};
    await Future.wait([
      for (final key in effectiveHomeDisplaySourceKeys())
        if (key != currentKey) _collectFromSource(key, seen, merged),
    ]);
    return merged;
  }

  /// 收集單個源的「条漫 / 独家」作品。永不拋錯（一個源掛了不拖累其他）。
  Future<void> _collectFromSource(
      String key, Set<String> seen, List<Comic> merged) async {
    final source = ComicSource.find(key);
    if (source == null) return;
    final futures = <Future<List<Comic>>>[];
    // ① 最精準：用源自己的分類（条漫/独家）與參數直接請求
    final loader = source.categoryComicsData?.load;
    if (loader != null) {
      for (final entry in _preciseCategories(source)) {
        futures.add(() async {
          try {
            final res = await loader(entry.$1, entry.$2, const <String>[], 1);
            return res.success ? res.data : <Comic>[];
          } catch (_) {
            return <Comic>[];
          }
        }());
      }
    }
    // ② 探索分區標題匹配（嚴格模式：標題沒命中就不收，
    //    寧可少收，也不要混進跟条漫/独家無關的作品）
    futures.add(() async {
      if (source.explorePages.isEmpty) return <Comic>[];
      final page = _pickPage(source);
      if (page == null) return <Comic>[];
      List<ExplorePagePart> parts = const [];
      try {
        if (page.loadMultiPart != null) {
          final res = await page.loadMultiPart!();
          if (res.success) parts = res.data;
        } else if (page.loadPage != null) {
          final res = await page.loadPage!(1);
          if (res.success) parts = [ExplorePagePart(page.title, res.data, null)];
        }
      } catch (_) {
        return <Comic>[];
      }
      return [
        for (final part in parts)
          if (_mergePartTitles.any((t) => part.title.contains(t)))
            ...part.comics,
      ];
    }());
    final results = await Future.wait(futures);
    for (final comics in results) {
      for (final comic in comics) {
        if (seen.add('${comic.sourceKey}:${comic.id}')) {
          merged.add(comic);
        }
      }
    }
  }

  /// 從某個源的分類設定裡，找出「条漫 / 独家」這類分類，回傳 (分類名, param)。
  /// 這是唯一 100% 精準的路：分類與參數由源自己定義
  /// （例如騰訊：条漫 = tm|upt、独家 = dj|upt），用它去請求就是
  /// 伺服器端已篩選好的結果，不靠標題猜。
  List<(String, String?)> _preciseCategories(ComicSource source) {
    final out = <(String, String?)>[];
    final parts = source.categoryData?.categories ?? const [];
    for (final part in parts) {
      for (final item in part.categories) {
        if (!_mergePartTitles.any((t) => item.label.contains(t))) continue;
        final map = item.target.attributes;
        out.add((
          map?["category"]?.toString() ?? item.label,
          map?["param"]?.toString(),
        ));
      }
    }
    return out;
  }

  /// 從某個分區裡挑 [count] 部；帶入 [_seed] 讓「换一换」選到不同的一批。
  List<Comic> _pick(ExplorePagePart part, int count) {
    final list = List<Comic>.from(part.comics);
    if (list.length <= count || count <= 0) return list;
    list.shuffle(Random(_seedFor(part.title) * 31 + part.title.hashCode));
    return list.take(count).toList();
  }

  List<ComicSource> get _sources => [
    for (final key in effectiveHomeDisplaySourceKeys())
      if (ComicSource.find(key)?.explorePages.isNotEmpty ?? false)
        ComicSource.find(key)!,
  ];

  ComicSource? get _source {
    final list = _sources;
    if (list.isEmpty) return null;
    return list[_selected.clamp(0, list.length - 1)];
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// 優先挑「多分區」探索頁（能一次拿到多個分區標題），
  /// 其次單頁列表，最後退回第一個探索頁。
  ExplorePageData? _pickPage(ComicSource source) {
    for (final page in source.explorePages) {
      if (page.loadMultiPart != null) return page;
    }
    for (final page in source.explorePages) {
      if (page.loadPage != null) return page;
    }
    return source.explorePages.isEmpty ? null : source.explorePages.first;
  }

  Future<void> _load() async {
    final source = _source;
    if (source == null) {
      if (mounted) setState(() => _parts = const []);
      return;
    }
    final page = _pickPage(source);
    if (page == null) {
      if (mounted) setState(() => _parts = const []);
      return;
    }
    final cacheKey = source.key;
    final cached = _cache[cacheKey];
    if (cached != null && _parts.isEmpty) {
      // 先进先出：立刻显示上次的完整结果（推荐 + 周期更新一起）
      setState(() {
        _parts = cached.parts;
        _loading = false;
        _error = null;
      });
      if (DateTime.now().difference(cached.time) < _cacheTtl) {
        return;
      }
    }
    if (_parts.isEmpty) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      // 提速：主源探索並行發射；只有主源失敗才顯示錯誤。
      // （跨源合池已按用戶要求移除：推荐池只留主源）
      final mainFuture = () async {
        if (page.loadMultiPart != null) {
          final res = await page.loadMultiPart!();
          if (!res.success) throw res.errorMessage ?? '探索頁載入失敗';
          return res.data;
        } else if (page.loadPage != null) {
          final res = await page.loadPage!(1);
          if (!res.success) throw res.errorMessage ?? '探索頁載入失敗';
          return [ExplorePagePart(page.title, res.data, null)];
        }
        return <ExplorePagePart>[];
      }();
      // 2026-09-17 用戶要求：首頁推荐【只顯示主源】，不再併入騰訊等其他源
      var result = await mainFuture;

      // 只有拿到兩個以上分區（推薦 + 周期更新）才寫，避免緩一半
      if (result.length >= 2) {
        _cache[cacheKey] = (time: DateTime.now(), parts: result);
      }
      if (!mounted) return;
      setState(() {
        _parts = result;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _select(int index) {
    if (index == _selected) return;
    setState(() {
      _selected = index;
      _parts = const [];
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final sources = _sources;
    if (sources.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    final slivers = <Widget>[SliverToBoxAdapter(child: _buildTabs(sources))];
    if (_loading) {
      slivers.add(
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
      );
    } else if (_error != null) {
      slivers.add(
        SliverToBoxAdapter(
          child: NetworkError(
            message: _error!,
            retry: _load,
            withAppbar: false,
          ),
        ),
      );
    } else if (_parts.isEmpty) {
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Text(
                "No items".tl,
                style: ts.s14.copyWith(color: context.colorScheme.outline),
              ),
            ),
          ),
        ),
      );
    } else {
      // ① 首頁推薦（栗子漫畫精選國漫）+ 换一换 / 更多
      final recommends = _recommendParts;
      if (recommends.isNotEmpty) {
        final first = recommends.first;
        slivers.add(SliverToBoxAdapter(child: _buildSectionTitle(first)));
        // 4 列 x 2 排 = 8 本，固定簡潔網格（不受「漫畫顯示模式」影響）
        slivers.add(
          SliverGridComics(
            comics: _pick(first, kHomeFeedMaxPerSection),
            forceBriefMode: true,
            forceColumns: kHomeFeedColumns,
          ),
        );
        slivers.add(SliverToBoxAdapter(child: _buildActions(first)));
        for (final part in recommends.skip(1)) {
          slivers.add(SliverToBoxAdapter(child: _buildSectionTitle(part)));
          slivers.add(
            SliverGridComics(
              comics: part.comics.take(kHomeFeedMaxPerSection).toList(),
              forceBriefMode: true,
              forceColumns: kHomeFeedColumns,
            ),
          );
        }
      }

      // ② 周期更新：周一~周日 分頁，資料由源按 updatedAt 事先分好桶
      final weeks = _weekdayParts;
      if (weeks.isNotEmpty) {
        slivers.add(
          SliverToBoxAdapter(
            child: _buildSectionTitle(
              ExplorePagePart("周期更新", const [], null),
            ),
          ),
        );
        slivers.add(
          SliverToBoxAdapter(child: _buildWeekdayChips(weeks)),
        );
        final current = weeks.firstWhere(
          (e) => e.$1 == _weekday,
          orElse: () => weeks.first,
        );
        // 4 列 x 2 排 = 8 本
        slivers.add(
          SliverGridComics(
            comics: _pick(current.$2, kHomeWeekdayMaxPerSection),
            forceBriefMode: true,
            forceColumns: kHomeFeedColumns,
          ),
        );
        slivers.add(SliverToBoxAdapter(child: _buildActions(current.$2)));
      }
    }
    return SliverMainAxisGroup(slivers: slivers);
  }

  Widget _buildTabs(List<ComicSource> sources) {
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: sources.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final selected = i == _selected;
                return GestureDetector(
                  onTap: () => _select(i),
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: selected
                          ? context.colorScheme.primaryContainer
                          : null,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: selected
                            ? Colors.transparent
                            : context.colorScheme.outlineVariant,
                        width: 0.6,
                      ),
                    ),
                    child: Text(
                      sources[i].name,
                      style: ts.s14.copyWith(
                        fontWeight: selected ? FontWeight.w600 : null,
                        color: selected
                            ? context.colorScheme.onPrimaryContainer
                            : null,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          // 排行 / 更新 入口（從頂欄搬下來，解決圖標擁擠）
          IconButton(
            icon: const Icon(Icons.leaderboard_outlined),
            tooltip: '排行',
            onPressed: () =>
                context.to(() => const ShelfRankPage()),
          ),
          IconButton(
            icon: const Icon(Icons.new_releases_outlined),
            tooltip: '更新',
            onPressed: () =>
                context.to(() => const ShelfUpdatesPage()),
          ),
          IconButton(
            // 刷新首頁：清掉快取並重新抓這個源的推薦 + 周期更新
            icon: const Icon(Icons.refresh),
            tooltip: "Refresh".tl,
            onPressed: () {
              final source = _source;
              if (source != null) {
                _cache.remove(source.key);
              }
              setState(() {
                _parts = const [];
                _loading = true;
              });
              _load();
            },
          ),
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: "Search".tl,
            onPressed: () => context.to(() => const SearchPage()),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(ExplorePagePart part) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 18,
            decoration: BoxDecoration(
              color: context.colorScheme.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              part.title.isEmpty ? "Recommended".tl : part.title,
              style: ts.s18.copyWith(fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// 周期更新的星期分頁。
  Widget _buildWeekdayChips(List<(int, ExplorePagePart)> weeks) {
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: weeks.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final entry = weeks[i];
          final selected = entry.$1 == _weekday;
          return GestureDetector(
            onTap: () => setState(() => _weekday = entry.$1),
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: selected ? context.colorScheme.primaryContainer : null,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: selected
                      ? Colors.transparent
                      : context.colorScheme.outlineVariant,
                  width: 0.6,
                ),
              ),
              child: Text(
                _weekdayNames[entry.$1],
                style: ts.s14.copyWith(
                  fontWeight: selected ? FontWeight.w600 : null,
                  color: selected
                      ? context.colorScheme.onPrimaryContainer
                      : null,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildActions(ExplorePagePart part) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              // 换一换：只換【這個分區】的一批（各分區種子獨立，互不連動）
              onPressed: () => setState(() =>
                  _seeds[part.title] = (_seeds[part.title] ?? 0) + 1),
              icon: const Icon(Icons.refresh, size: 18),
              label: Text("Shuffle".tl),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              // 查看更多：用 App 的漫畫列表樣式直直列出（最多 10 本）
              onPressed: () => context.to(
                () => HomeSectionListPage(
                  title: part.title,
                  comics: part.comics,
                ),
              ),
              icon: const Icon(Icons.chevron_right, size: 18),
              label: Text("View more".tl),
            ),
          ),
        ],
      ),
    );
  }
}

/// 「更多」的完整分區列表頁：把某個源的所有探索分區完整列出來。
class SourcePartsPage extends StatefulWidget {
  const SourcePartsPage({required this.source, super.key});

  final ComicSource source;

  @override
  State<SourcePartsPage> createState() => _SourcePartsPageState();
}

class _SourcePartsPageState extends State<SourcePartsPage> {
  bool _loading = true;
  String? _error;
  List<ExplorePagePart> _parts = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var result = <ExplorePagePart>[];
      for (final page in widget.source.explorePages) {
        if (page.loadMultiPart != null) {
          final res = await page.loadMultiPart!();
          if (res.success) result = res.data;
          if (!res.success) {
            if (mounted) {
              setState(() {
                _error = res.errorMessage;
                _loading = false;
              });
            }
            return;
          }
          break;
        }
        if (page.loadPage != null) {
          final res = await page.loadPage!(1);
          if (!res.success) {
            if (mounted) {
              setState(() {
                _error = res.errorMessage;
                _loading = false;
              });
            }
            return;
          }
          result = [ExplorePagePart(page.title, res.data, null)];
          break;
        }
      }
      if (!mounted) return;
      setState(() {
        _parts = result;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: Appbar(title: Text(widget.source.name)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? NetworkError(message: _error!, retry: _load, withAppbar: false)
          : SmoothCustomScrollView(
              slivers: [
                for (final part in _parts) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Text(
                        part.title,
                        style: ts.s18.copyWith(fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  SliverGridComics(comics: part.comics),
                ],
              ],
            ),
    );
  }
}

/// 「查看更多」頁：用 App 預設的漫畫列表樣式（詳細／簡潔跟隨設定）
/// 直直列出該分區的漫畫 —— 不限量，源給多少顯示多少。
class HomeSectionListPage extends StatelessWidget {
  const HomeSectionListPage({
    required this.title,
    required this.comics,
    super.key,
  });

  final String title;

  final List<Comic> comics;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: Appbar(title: Text(title)),
      body: SmoothCustomScrollView(
        slivers: [SliverGridComics(comics: comics)],
      ),
    );
  }
}
