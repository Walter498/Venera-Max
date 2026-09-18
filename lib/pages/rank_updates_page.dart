import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:venera/components/components.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/history.dart';
import 'package:venera/foundation/home_layout.dart';
import 'package:venera/foundation/image_provider/cached_image.dart';
import 'package:venera/network/app_dio.dart';
import 'package:venera/pages/comic_details_page/comic_page.dart';
import 'package:venera/pages/home_source_feed.dart';

/// 首頁「更新」「排行」兩個頁籤的內聯視圖（2026-09-18）。
/// 不跳頁：直接嵌在首頁，跟首頁一樣是第一層級。
/// 適配所有源：跟著首頁當前選中的源（HomeSourceScope.currentKey）；
/// 栗子源額外用官方 API 拿「更新時間」做徽章、排行榜分地區。
/// 其他源走源的通用分類接口（有榜單分類就用，沒有就提示）。

const _kLiziApi = 'http://ai.qsmm.fun';
const _kLiziImg = 'https://cdn.lzimg.xyz';

/// 當前首頁選中的源（找不到就退回第一個首頁顯示源）
ComicSource? _currentSource() {
  final key = HomeSourceScope.currentKey;
  if (key != null) {
    final s = ComicSource.find(key);
    if (s != null) return s;
  }
  for (final k in effectiveHomeDisplaySourceKeys()) {
    final s = ComicSource.find(k);
    if (s != null) return s;
  }
  return ComicSource.all().isEmpty ? null : ComicSource.all().first;
}

bool _isLizi(ComicSource? s) => s?.key == 'lizimh';

Future<Map<String, dynamic>> _getJson(String path) async {
  final dio = AppDio(
      BaseOptions(responseType: ResponseType.json), const Duration(seconds: 15));
  final res = await dio.get('$_kLiziApi$path');
  final raw = res.data;
  final map = Map<String, dynamic>.from(raw is Map ? raw : {});
  final data = map['data'];
  return data is Map ? Map<String, dynamic>.from(data) : {};
}

/// 栗子 API 漫畫 → Comic（機讀欄位塞進 description）
Comic _comicFromApi(Map<String, dynamic> m) {
  var cover = (m['picY'] ?? m['picX'] ?? '').toString();
  if (cover.isNotEmpty && !cover.startsWith('http')) cover = _kLiziImg + cover;
  final nums = (m['nums'] as num?)?.toInt() ?? 0;
  final sub = m['sub']?.toString() ?? '';
  final upd = (m['updatedAt'] as num?)?.toInt() ?? 0;
  return Comic(
    m['name']?.toString() ?? '',
    cover,
    (m['id'] as num?)?.toInt().toString() ?? '',
    m['author']?.toString() ?? '',
    (m['tags']?.toString() ?? '').split(',').where((e) => e.isNotEmpty).toList(),
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

/// 「多久前」
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

Widget _coverBadge(BuildContext context, Comic c, String badge) {
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

Widget _hint(BuildContext context, String text) {
  return Padding(
    padding: const EdgeInsets.all(24),
    child: Center(
      child: Text(text,
          textAlign: TextAlign.center,
          style: TextStyle(color: context.colorScheme.outline)),
    ),
  );
}

/// 封面網格（3 欄，帶徽章）
Widget _coverGrid(
    BuildContext context, int count, (Comic, String, VoidCallback) Function(int) item,
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
            Expanded(child: _coverBadge(context, c, badge)),
            const SizedBox(height: 4),
            Text(c.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            if (sub != null && sub.isNotEmpty)
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

void _openComic(BuildContext context, String id, String sourceKey, String cover,
    String title) {
  context.to(() => ComicPage(
      id: id, sourceKey: sourceKey, cover: cover, title: title));
}

/// ==================== 更新（首頁頁籤，內聯） ====================
class HomeUpdatesView extends StatefulWidget {
  const HomeUpdatesView({super.key});

  @override
  State<HomeUpdatesView> createState() => _HomeUpdatesViewState();
}

class _HomeUpdatesViewState extends State<HomeUpdatesView> {
  List<Comic>? _latest;
  String? _error;

  @override
  void initState() {
    super.initState();
    HistoryManager().addListener(_onChange);
    _load();
  }

  @override
  void dispose() {
    HistoryManager().removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final source = _currentSource();
    if (source == null) {
      setState(() => _error = '沒有可用的源');
      return;
    }
    // 栗子：直調官方 API（帶更新時間，可做「N分鐘前」徽章）
    if (_isLizi(source)) {
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
        if (mounted) setState(() => _error = e.toString());
      }
      return;
    }
    // 其他源：走源的通用分類接口（無篩選 = 站的默認/最新列表）
    final loader = source.categoryComicsData?.load;
    if (loader == null) {
      setState(() => _error = '此源不支持更新列表');
      return;
    }
    try {
      final res = await loader('', null, const <String>[], 1);
      if (!mounted) return;
      setState(() {
        if (res.success) {
          _latest = res.data;
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
    final recent = List<History>.from(HistoryManager().getAll())
      ..sort((a, b) => b.time.compareTo(a.time));
    final recentTop = recent.take(6).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(context, '最近觀看'),
        if (recentTop.isEmpty)
          _hint(context, '還沒有閱讀記錄')
        else
          _coverGrid(context, recentTop.length, (i) {
            final h = recentTop[i];
            return (
              Comic(h.title, h.cover, h.id, null, null, '', h.sourceKey, null,
                  null),
              _agoText(h.time.millisecondsSinceEpoch ~/ 1000),
              () => _openComic(context, h.id, h.sourceKey, h.cover, h.title),
            );
          }),
        const SizedBox(height: 16),
        _sectionTitle(context, '最新更新'),
        if (_latest == null)
          _error != null
              ? _hint(context, _error!)
              : const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
        else
          _coverGrid(context, _latest!.length, (i) {
            final c = _latest![i];
            final nums = _apiNums(c);
            return (
              c,
              _agoText(_apiUpd(c)),
              () => _openComic(context, c.id, c.sourceKey, c.cover, c.title),
            );
          }, subOf: (i) {
            final c = _latest![i];
            final sub = _apiSub(c);
            if (sub.isNotEmpty) return sub;
            final nums = _apiNums(c);
            return nums > 0 ? '更新至$nums話' : (c.subtitle ?? '');
          }),
      ],
    );
  }
}

/// ==================== 排行（首頁頁籤，內聯） ====================
/// 栗子：官方 API（日漫/国漫/韩漫 分組）；其他源：找源的榜單分類，
/// 沒有就提示（不假造數據）。
class HomeRankView extends StatefulWidget {
  const HomeRankView({super.key});

  @override
  State<HomeRankView> createState() => _HomeRankViewState();
}

class _HomeRankViewState extends State<HomeRankView> {
  List<(String, List<Comic>)>? _groups; // (分組名, 漫畫)
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// 在源的分類設定裡找榜單類分類（param == rank 或名稱含 榜/排行）
  List<(String, String?)> _rankCategories(ComicSource source) {
    final out = <(String, String?)>[];
    for (final part in source.categoryData?.categories ?? const []) {
      for (final item in part.categories) {
        final param = item.target.attributes?['param']?.toString();
        if (param == 'rank' ||
            item.label.contains('榜') ||
            item.label.contains('排行')) {
          out.add((item.label, param));
        }
      }
    }
    return out;
  }

  Future<void> _load() async {
    final source = _currentSource();
    if (source == null) {
      setState(() => _error = '沒有可用的源');
      return;
    }
    // 栗子：官方 API，帶地區分組
    if (_isLizi(source)) {
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
        setState(() {
          if (groups.isEmpty) {
            _error = '榜單為空';
          } else {
            _groups = groups;
          }
        });
      } catch (e) {
        if (mounted) setState(() => _error = e.toString());
      }
      return;
    }
    // 其他源：用源自己的榜單分類
    final loader = source.categoryComicsData?.load;
    final cats = _rankCategories(source);
    if (loader == null || cats.isEmpty) {
      setState(() => _error = '此源沒有排行榜\n（可切回栗子漫畫查看）');
      return;
    }
    try {
      final groups = <(String, List<Comic>)>[];
      for (final (label, param) in cats) {
        final res = await loader(label, param, const <String>[], 1);
        if (res.success && res.data.isNotEmpty) {
          groups.add((label, res.data));
        }
      }
      if (!mounted) return;
      setState(() {
        if (groups.isEmpty) {
          _error = '榜單為空';
        } else {
          _groups = groups;
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return _hint(context, _error!);
    final groups = _groups;
    if (groups == null) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DefaultTabController(
          length: groups.length,
          child: Column(children: [
            TabBar(
              isScrollable: groups.length > 3,
              tabs: [for (final g in groups) Tab(text: g.$1)],
            ),
            SizedBox(
              height: 620,
              child: TabBarView(
                children: [
                  for (final g in groups) _RegionRankList(comics: g.$2),
                ],
              ),
            ),
          ]),
        ),
      ],
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
        SizedBox(
          height: 190,
          child: Row(children: [
            for (var i = 0; i < top3.length; i++) ...[
              Expanded(child: _topCard(context, i + 1, top3[i])),
              if (i < top3.length - 1) const SizedBox(width: 8),
            ],
          ]),
        ),
        const SizedBox(height: 12),
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
      onTap: () => _openComic(context, c.id, c.sourceKey, c.cover, c.title),
      child: Column(children: [
        Expanded(
          child: Stack(fit: StackFit.expand, children: [
            _coverBadge(context, c, ''),
            Positioned(
              left: 0,
              top: 0,
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
        onTap: () => _openComic(context, c.id, c.sourceKey, c.cover, c.title),
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
                width: 56, height: 76, child: _coverBadge(context, c, '')),
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
