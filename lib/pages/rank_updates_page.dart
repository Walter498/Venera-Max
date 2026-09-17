import 'package:flutter/material.dart';
import 'package:venera/components/components.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/history.dart';
import 'package:venera/foundation/home_layout.dart';
import 'package:venera/foundation/image_provider/cached_image.dart';
import 'package:venera/pages/comic_details_page/comic_page.dart';
import 'package:venera/pages/reader/reader.dart';

/// 首頁頂欄的兩個入口頁（2026-09-17）：排行 + 更新。
/// 排行：真實調源的「熱門排行」分類載入器（栗子源 param=rank → rank/list）。
/// 更新：最近觀看（HistoryManager 真數據）+ 最新更新（源分類總列表）。
/// 全部真數據，無空殼。

/// 取第一個支援分類載入的首頁顯示源（栗子）
ComicSource? _rankSource() {
  for (final key in effectiveHomeDisplaySourceKeys()) {
    final s = ComicSource.find(key);
    if (s != null && s.categoryComicsData != null) return s;
  }
  for (final s in ComicSource.all()) {
    if (s.categoryComicsData != null) return s;
  }
  return null;
}

/// 直達閱讀器上次位置（與書架足跡同一邏輯）
void _continueReading(BuildContext context, History h) {
  context.to(() => Reader(
        type: ComicType.fromKey(h.sourceKey),
        cid: h.id,
        name: h.title,
        chapters: null,
        history: h,
        initialChapter: h.ep,
        initialPage: h.page,
        author: '',
        tags: const [],
      ));
}

/// ==================== 排行 ====================
class ShelfRankPage extends StatefulWidget {
  const ShelfRankPage({super.key});

  @override
  State<ShelfRankPage> createState() => _ShelfRankPageState();
}

class _ShelfRankPageState extends State<ShelfRankPage> {
  List<Comic>? _comics;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final source = _rankSource();
    final loader = source?.categoryComicsData?.load;
    if (loader == null) {
      setState(() => _error = '當前源不支持排行');
      return;
    }
    try {
      // 栗子源：category「热门排行」param=rank → /app/api/rank/list
      final res = await loader('热门排行', 'rank', const <String>[], 1);
      if (!mounted) return;
      setState(() {
        if (res.success) {
          _comics = res.data;
        } else {
          _error = res.errorMessage ?? '載入失敗';
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: Appbar(title: const Text('排行')),
      body: _comics == null
          ? Center(
              child: _error != null
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!),
                        const SizedBox(height: 12),
                        FilledButton(
                            onPressed: () {
                              setState(() => _error = null);
                              _load();
                            },
                            child: const Text('重試')),
                      ],
                    )
                  : const CircularProgressIndicator(),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _comics!.length,
              itemBuilder: (context, i) => _rankRow(context, i, _comics![i]),
            ),
    );
  }

  Widget _rankRow(BuildContext context, int index, Comic c) {
    final rank = index + 1;
    // 前三名特殊色
    final badgeColor = switch (rank) {
      1 => const Color(0xFFFFB300),
      2 => const Color(0xFF90A4AE),
      3 => const Color(0xFFCD7F32),
      _ => context.colorScheme.primary,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.to(() => ComicPage(
            id: c.id, sourceKey: c.sourceKey, cover: c.cover, title: c.title)),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image(
                      image: CachedImageProvider(c.cover,
                          sourceKey: c.sourceKey, cid: c.id),
                      width: 72,
                      height: 96,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 72,
                        height: 96,
                        color: context.colorScheme.surfaceContainerHighest,
                        child: const Icon(Icons.book_outlined),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    top: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: badgeColor,
                        borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(8),
                            bottomRight: Radius.circular(8)),
                      ),
                      child: Text('TOP·$rank',
                          style: const TextStyle(
                              fontSize: 11,
                              color: Colors.white,
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    if (c.subtitle?.isNotEmpty == true)
                      Text(c.subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12,
                              color: context.colorScheme.outline)),
                    const SizedBox(height: 4),
                    Text(c.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12,
                            color: context.colorScheme.outline)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ==================== 更新 ====================
class ShelfUpdatesPage extends StatefulWidget {
  const ShelfUpdatesPage({super.key});

  @override
  State<ShelfUpdatesPage> createState() => _ShelfUpdatesPageState();
}

class _ShelfUpdatesPageState extends State<ShelfUpdatesPage> {
  List<Comic>? _latest;
  String? _latestError;

  @override
  void initState() {
    super.initState();
    HistoryManager().addListener(_onHistory);
    _loadLatest();
  }

  @override
  void dispose() {
    HistoryManager().removeListener(_onHistory);
    super.dispose();
  }

  void _onHistory() {
    if (mounted) setState(() {});
  }

  Future<void> _loadLatest() async {
    final source = _rankSource();
    final loader = source?.categoryComicsData?.load;
    if (loader == null) {
      setState(() => _latestError = '當前源不支持');
      return;
    }
    try {
      // 無篩選的分類總列表（伺服器按更新時間排，最新在前）
      final res = await loader('', null, const <String>[], 1);
      if (!mounted) return;
      setState(() {
        if (res.success) {
          _latest = res.data;
        } else {
          _latestError = res.errorMessage ?? '載入失敗';
        }
      });
    } catch (e) {
      if (mounted) setState(() => _latestError = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final recent = List<History>.from(HistoryManager().getAll())
      ..sort((a, b) => b.time.compareTo(a.time));
    final recentTop = recent.take(6).toList();
    return Scaffold(
      appBar: Appbar(title: const Text('更新')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _sectionTitle(context, '最近觀看'),
          if (recentTop.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text('還沒有閱讀記錄',
                    style: TextStyle(color: context.colorScheme.outline)),
              ),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.55,
              ),
              itemCount: recentTop.length,
              itemBuilder: (context, i) {
                final h = recentTop[i];
                return InkWell(
                  borderRadius: BorderRadius.circular(8),
                  // 點了直達上次閱讀位置
                  onTap: () => _continueReading(context, h),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image(
                            image: CachedImageProvider(h.cover,
                                sourceKey: h.sourceKey, cid: h.id),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color:
                                  context.colorScheme.surfaceContainerHighest,
                              child: const Icon(Icons.book_outlined),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(h.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600)),
                      Text('閱至第${h.ep}話',
                          maxLines: 1,
                          style: TextStyle(
                              fontSize: 11,
                              color: context.colorScheme.outline)),
                    ],
                  ),
                );
              },
            ),
          const SizedBox(height: 16),
          _sectionTitle(context, '最新更新'),
          if (_latest == null)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: _latestError != null
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_latestError!),
                          const SizedBox(height: 12),
                          FilledButton(
                              onPressed: () {
                                setState(() => _latestError = null);
                                _loadLatest();
                              },
                              child: const Text('重試')),
                        ],
                      )
                    : const CircularProgressIndicator(),
              ),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.52,
              ),
              itemCount: _latest!.length,
              itemBuilder: (context, i) {
                final c = _latest![i];
                return InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => context.to(() => ComicPage(
                      id: c.id,
                      sourceKey: c.sourceKey,
                      cover: c.cover,
                      title: c.title)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image(
                            image: CachedImageProvider(c.cover,
                                sourceKey: c.sourceKey, cid: c.id),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color:
                                  context.colorScheme.surfaceContainerHighest,
                              child: const Icon(Icons.book_outlined),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(c.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600)),
                      if (c.subtitle?.isNotEmpty == true)
                        Text(c.subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11,
                                color: context.colorScheme.outline)),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            color: context.colorScheme.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(title,
            style:
                const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}
