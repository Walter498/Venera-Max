import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:venera/components/components.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/history.dart';
import 'package:venera/foundation/image_provider/cached_image.dart';
import 'package:venera/network/app_dio.dart';
import 'package:venera/pages/comic_details_page/comic_page.dart';
import 'package:venera/pages/reader/reader.dart';

/// 排行 + 更新 頁（2026-09-17 v2，仿青漫圖九/圖十）。
/// 排行：直接調栗子 /app/api/rank/list（日漫/国漫/韩漫 分組 Tab，
///       前三名大封面，其餘直列帶「更新至N話」）。
/// 更新：最近觀看（HistoryManager，封面帶「上次閱讀」時間徽章）+
///       最新更新（/app/api/category/list，封面帶「更新於多久前」徽章）。
/// 全部真數據。

const _kApi = 'http://ai.qsmm.fun';
const _kImg = 'https://cdn.lzimg.xyz';

Future<Map<String, dynamic>> _getJson(String path) async {
  final dio = AppDio(
      BaseOptions(responseType: ResponseType.json), const Duration(seconds: 15));
  final res = await dio.get('$_kApi$path');
  var raw = res.data;
  if (raw is String) raw = raw.isEmpty ? {} : raw;
  final map = Map<String, dynamic>.from(raw is Map ? raw : {});
  final data = map['data'];
  return data is Map ? Map<String, dynamic>.from(data) : {};
}

/// API 漫畫 → Comic（話數 nums、最新話 sub、更新時間 updatedAt 都保留進 description）
Comic _comicFromApi(Map<String, dynamic> m) {
  var cover = (m['picY'] ?? m['picX'] ?? '').toString();
  if (cover.isNotEmpty && !cover.startsWith('http')) cover = _kImg + cover;
  final nums = (m['nums'] as num?)?.toInt() ?? 0;
  final sub = m['sub']?.toString() ?? '';
  final upd = (m['updatedAt'] as num?)?.toInt() ?? 0;
  return Comic(
    m['name']?.toString() ?? '',
    cover,
    (m['id'] as num?)?.toInt().toString() ?? '',
    m['author']?.toString() ?? '',
    (m['tags']?.toString() ?? '').split(',').where((e) => e.isNotEmpty).toList(),
    // description 帶機讀欄位：upd@秒|nums@話數|sub@最新話
    'upd@$upd|nums@$nums|sub@$sub\n${m['content']?.toString() ?? ''}',
    'lizimh',
    null,
    null,
  );
}

int _apiUpd(Comic c) {
  final m = RegExp(r'upd@(\d+)').firstMatch(c.description);
  return m != null ? int.tryParse(m.group(1)!) ?? 0 : 0;
}

int _apiNums(Comic c) {
  final m = RegExp(r'nums@(\d+)').firstMatch(c.description);
  return m != null ? int.tryParse(m.group(1)!) ?? 0 : 0;
}

String _apiSub(Comic c) {
  final m = RegExp(r'sub@([^\n]*)').firstMatch(c.description);
  return m?.group(1) ?? '';
}

/// 「多久前」徽章文字（10分钟前/1小时前/2天前/日期）
String _agoText(int epochSec) {
  if (epochSec <= 0) return '';
  final t = DateTime.fromMillisecondsSinceEpoch(epochSec * 1000);
  final diff = DateTime.now().difference(t);
  if (diff.inMinutes < 1) return '剛剛';
  if (diff.inHours < 1) return '${diff.inMinutes}分鐘前';
  if (diff.inDays < 1) return '${diff.inHours}小時前';
  if (diff.inDays < 30) return '${diff.inDays}天前';
  return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
}

Widget _coverWithBadge(BuildContext context, Comic c, String badge,
    {double? w, double? h}) {
  return ClipRRect(
    borderRadius: BorderRadius.circular(8),
    child: Stack(
      fit: StackFit.expand,
      children: [
        Image(
          image: CachedImageProvider(c.cover, sourceKey: c.sourceKey, cid: c.id),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            color: context.colorScheme.surfaceContainerHighest,
            child: const Icon(Icons.book_outlined),
          ),
        ),
        if (badge.isNotEmpty)
          Positioned(
            left: 0,
            top: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: context.colorScheme.primary,
                borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(8),
                    bottomRight: Radius.circular(8)),
              ),
              child: Text(badge,
                  style: TextStyle(
                      fontSize: 10, color: context.colorScheme.onPrimary)),
            ),
          ),
      ],
    ),
  );
}

/// ==================== 排行（仿圖九：地區 Tab + 前三甲大封面 + 直列） ====================
class ShelfRankPage extends StatefulWidget {
  const ShelfRankPage({super.key});

  @override
  State<ShelfRankPage> createState() => _ShelfRankPageState();
}

class _ShelfRankPageState extends State<ShelfRankPage> {
  List<(String, List<Comic>)>? _groups;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await _getJson('/app/api/rank/list');
      final groups = <(String, List<Comic>)>[];
      for (final g in (data['rank_list'] as List? ?? const [])) {
        final gm = Map<String, dynamic>.from(g as Map);
        final comics = [
          for (final c in (gm['comic_list'] as List? ?? const []))
            _comicFromApi(Map<String, dynamic>.from(c as Map))
        ];
        if (comics.isNotEmpty) {
          groups.add((gm['name']?.toString() ?? '榜單', comics));
        }
      }
      if (!mounted) return;
      if (groups.isEmpty) {
        setState(() => _error = '榜單為空');
      } else {
        setState(() => _groups = groups);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        appBar: Appbar(title: const Text('排行榜')),
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('載入失敗：$_error'),
            const SizedBox(height: 12),
            FilledButton(
                onPressed: () {
                  setState(() => _error = null);
                  _load();
                },
                child: const Text('重試')),
          ]),
        ),
      );
    }
    final groups = _groups;
    if (groups == null) {
      return Scaffold(
        appBar: Appbar(title: const Text('排行榜')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return DefaultTabController(
      length: groups.length,
      child: Scaffold(
        appBar: Appbar(title: const Text('排行榜')),
        body: Column(children: [
          TabBar(tabs: [for (final g in groups) Tab(text: g.$1)]),
          Expanded(
            child: TabBarView(children: [
              for (final g in groups) _RegionRankList(comics: g.$2),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _RegionRankList extends StatelessWidget {
  const _RegionRankList({required this.comics});
  final List<Comic> comics;

  @override
  Widget build(BuildContext context) {
    final top3 = comics.take(3).toList();
    final rest = comics.skip(3).toList();
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // 前三甲：大封面橫排（仿圖九）
        SizedBox(
          height: 190,
          child: Row(children: [
            for (var i = 0; i < top3.length; i++) ...[
              Expanded(child: _topCard(context, i + 1, top3[i])),  // 名次從 1 開始
              if (i < top3.length - 1) const SizedBox(width: 8),
            ],
          ]),
        ),
        const SizedBox(height: 12),
        // 其餘直列
        for (var i = 0; i < rest.length; i++) _row(context, i + 4, rest[i]),
      ],
    );
  }

  Widget _topCard(BuildContext context, int rank, Comic c) {
    const colors = [
      Color(0xFFFFB300),
      Color(0xFF90A4AE),
      Color(0xFFCD7F32),
    ];
    final badgeColor = (rank >= 1 && rank <= colors.length)
        ? colors[rank - 1]
        : colors.last;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => context.to(() => ComicPage(
          id: c.id, sourceKey: c.sourceKey, cover: c.cover, title: c.title)),
      child: Column(children: [
        Expanded(
          child: Stack(fit: StackFit.expand, children: [
            _coverWithBadge(context, c, ''),
            Positioned(
              left: 0, top: 0,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
          ]),
        ),
        const SizedBox(height: 4),
        Text(c.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style:
                const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _row(BuildContext context, int rank, Comic c) {
    final nums = _apiNums(c);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.to(() => ComicPage(
            id: c.id, sourceKey: c.sourceKey, cover: c.cover, title: c.title)),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(children: [
            SizedBox(
              width: 28,
              child: Text('$rank',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: context.colorScheme.outline)),
            ),
            SizedBox(
                width: 56,
                height: 76,
                child: _coverWithBadge(context, c, '')),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    if (c.subtitle?.isNotEmpty == true)
                      Text(c.subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12,
                              color: context.colorScheme.outline)),
                    if (nums > 0)
                      Text('更新至$nums話',
                          style: TextStyle(
                              fontSize: 12,
                              color: context.colorScheme.primary)),
                  ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// ==================== 更新（仿圖十：最近觀看 + 最新更新，封面帶時間徽章） ====================
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
    try {
      final data = await _getJson('/app/api/category/list?page=1');
      if (!mounted) return;
      setState(() {
        _latest = [
          for (final c in (data['category_list'] as List? ?? const []))
            _comicFromApi(Map<String, dynamic>.from(c as Map))
        ];
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
      body: ListView(padding: const EdgeInsets.all(12), children: [
        _sectionTitle(context, '最近觀看'),
        if (recentTop.isEmpty)
          _emptyBox(context, '還沒有閱讀記錄')
        else
          _coverGrid(
            context,
            recentTop.length,
            (i) {
              final h = recentTop[i];
              final c = Comic(h.title, h.cover, h.id, null, null, '',
                  h.sourceKey, null, null);
              return (c, _agoText(h.time.millisecondsSinceEpoch ~/ 1000),
                  () => _continueReading(context, h));
            },
          ),
        const SizedBox(height: 16),
        _sectionTitle(context, '最新更新'),
        if (_latest == null)
          _latestError != null
              ? _emptyBox(context, '載入失敗：$_latestError')
              : const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                )
        else
          _coverGrid(
            context,
            _latest!.length,
            (i) {
              final c = _latest![i];
              return (c, _agoText(_apiUpd(c)), () {
                context.to(() => ComicPage(
                    id: c.id,
                    sourceKey: c.sourceKey,
                    cover: c.cover,
                    title: c.title));
              });
            },
            subOf: (i) {
              final s = _apiSub(_latest![i]);
              return s.isNotEmpty ? s : null;
            },
          ),
      ]),
    );
  }

  Widget _emptyBox(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
          child: Text(text,
              style: TextStyle(color: context.colorScheme.outline))),
    );
  }

  /// 封面網格（帶時間徽章）：item 回傳 (comic, 徽章文字, onTap)
  Widget _coverGrid(BuildContext context, int count,
      (Comic, String, VoidCallback) Function(int) item,
      {String? Function(int)? subOf}) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.52,
      ),
      itemCount: count,
      itemBuilder: (context, i) {
        final (c, badge, onTap) = item(i);
        final sub = subOf?.call(i);
        return InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _coverWithBadge(context, c, badge)),
              const SizedBox(height: 4),
              Text(c.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600)),
              if (sub != null)
                Text(sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11, color: context.colorScheme.outline)),
            ],
          ),
        );
      },
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
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      ]),
    );
  }

  Future<void> _continueReading(BuildContext context, History h) async {
    final nav = context;
    final source = ComicSource.find(h.sourceKey);
    final loader = source?.loadComicInfo;
    if (loader == null) {
      nav.to(() => ComicPage(
          id: h.id, sourceKey: h.sourceKey, cover: h.cover, title: h.title));
      return;
    }
    // 取章節表期間顯示進度
    showDialog(
      context: nav,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final res = await loader(h.id);
      if (nav.mounted) Navigator.of(nav).pop(); // 關進度
      if (res.success && res.data.chapters != null) {
        nav.to(() => Reader(
              type: ComicType.fromKey(h.sourceKey),
              cid: h.id,
              name: h.title,
              chapters: res.data.chapters,
              history: h,
              initialChapter: h.ep,
              initialPage: h.page,
              author: h.subtitle,
              tags: const [],
            ));
      } else {
        nav.to(() => ComicPage(
            id: h.id,
            sourceKey: h.sourceKey,
            cover: h.cover,
            title: h.title));
      }
    } catch (_) {
      if (nav.mounted) Navigator.of(nav).pop();
      nav.to(() => ComicPage(
          id: h.id, sourceKey: h.sourceKey, cover: h.cover, title: h.title));
    }
  }

}
