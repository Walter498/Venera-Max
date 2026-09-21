import 'package:flutter/material.dart';
import 'package:venera/components/components.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/foundation/comic_collection_store.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/favorites.dart';
import 'package:venera/foundation/history.dart';
import 'package:venera/foundation/local.dart';
import 'package:venera/foundation/image_provider/cached_image.dart';
import 'package:venera/pages/comic_details_page/comic_page.dart';
import 'package:venera/pages/local_comics_page.dart';
import 'package:venera/pages/reader/reader.dart';
import 'package:venera/pages/search_page.dart';
import 'package:venera/utils/translations.dart';

/// 書架頁（2026-09-17 改版，仿青漫書架佈局）：
/// 收藏 | 書單 | 足跡 三個 Tab + 右上角「緩存中心」。
/// 所有部分都接真實數據源：LocalFavoritesManager / ComicCollectionStore /
/// HistoryManager，無空殼。
class ShelfPage extends StatefulWidget {
  const ShelfPage({super.key});

  @override
  State<ShelfPage> createState() => _ShelfPageState();
}

class _ShelfPageState extends State<ShelfPage> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Material(
        child: Column(
          children: [
            SizedBox(
              height: 48,
                child: Row(
                  children: [
                    const Expanded(
                      child: TabBar(
                        tabs: [
                          Tab(text: '收藏'),
                          Tab(text: '足跡'),
                        ],
                      ),
                    ),
                    // 緩存中心 → 下載管理頁
                    InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () =>
                          context.to(() => const LocalComicsPage()),
                      child: Container(
                        margin: const EdgeInsets.only(right: 12),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: context.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.download_outlined,
                                size: 16,
                                color: context.colorScheme.primary),
                            const SizedBox(width: 4),
                            Text('緩存中心',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: context.colorScheme.primary)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Expanded(
                child: TabBarView(
                  children: [
                    _ShelfFavTab(),
                    _ShelfHistoryTab(),
                  ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 相對時間徽章（2天前 / 日期）
String _shelfTimeBadge(String? raw) {
  if (raw == null || raw.isEmpty) return '';
  DateTime? t;
  try {
    t = DateTime.parse(raw).toLocal();
  } catch (_) {
    return raw.length > 10 ? raw.substring(0, 10) : raw;
  }
  final diff = DateTime.now().difference(t);
  if (diff.inDays < 1) return '今天';
  if (diff.inDays < 30) return '${diff.inDays}天前';
  return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
}

/// 封面（帶 UA 走 App 圖片載入器）
Widget _shelfCover(BuildContext context, String cover, String sourceKey,
    String cid, double w, double h) {
  return ClipRRect(
    borderRadius: BorderRadius.circular(6),
    child: cover.isEmpty
        ? Container(
            width: w,
            height: h,
            color: context.colorScheme.surfaceContainerHighest,
            child: const Icon(Icons.book_outlined),
          )
        : Image(
            image: CachedImageProvider(cover, sourceKey: sourceKey, cid: cid),
            width: w,
            height: h,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              width: w,
              height: h,
              color: context.colorScheme.surfaceContainerHighest,
              child: const Icon(Icons.broken_image_outlined),
            ),
          ),
  );
}

/// ==================== Tab 1: 收藏（真數據：LocalFavoritesManager） ====================
class _ShelfFavTab extends StatefulWidget {
  const _ShelfFavTab();

  @override
  State<_ShelfFavTab> createState() => _ShelfFavTabState();
}

class _ShelfFavTabState extends State<_ShelfFavTab> {
  // 資料夾選擇持久化：離開/退出 App 都保留（用戶要求 2026-09-17）
  /// 歷史記錄 map：'sourceKey:id' → History（給卡片顯示最後閱讀時間）
  Map<String, History> get _histMap => {
        for (final h in HistoryManager().getAll())
          '${h.sourceKey}:${h.id}': h,
      };

  String? get _folder {
    final v = appdata.settings['shelf_folder'];
    return (v is String && v.isNotEmpty) ? v : null;
  }

  set _folder(String? v) {
    // Settings 類沒有 remove 方法：空字串 = 全部
    appdata.settings['shelf_folder'] = v ?? '';
    appdata.saveData();
  }

  bool _editMode = false;
  final Set<String> _selected = {};

  /// 收藏排序（原版功能：LocalSortType，7 種），持久化在 implicitData
  LocalSortType get _sortType {
    final v = appdata.implicitData['local_favorites_sort']?.toString();
    for (final t in LocalSortType.values) {
      if (t.value == v) return t;
    }
    return LocalSortType.defaultSort;
  }

  set _sortType(LocalSortType t) {
    appdata.implicitData['local_favorites_sort'] = t.value;
    appdata.writeImplicitData();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _pickFolder(List<String> folders) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: const Text('全部漫畫'),
              trailing: _folder == null ? const Icon(Icons.check) : null,
              onTap: () {
                setState(() => _folder = null);
                Navigator.pop(sheetContext);
              },
            ),
            for (final f in folders)
              ListTile(
                title: Text(f),
                trailing: _folder == f ? const Icon(Icons.check) : null,
                onTap: () {
                  setState(() => _folder = f);
                  Navigator.pop(sheetContext);
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    LocalFavoritesManager().addListener(_onChanged);
  }

  @override
  void dispose() {
    LocalFavoritesManager().removeListener(_onChanged);
    super.dispose();
  }

  List<FavoriteItem> _comics() {
    final fav = LocalFavoritesManager();
    final list =
        _folder == null ? fav.getAllComics() : fav.getFolderComics(_folder!);
    final sortType = _sortType;
    if (sortType == LocalSortType.defaultSort) return list;
    final out = List<FavoriteItem>.from(list);
    final history = {
      for (final h in HistoryManager().getAll()) '${h.sourceKey}:${h.id}': h,
    };
    out.sort((a, b) {
      switch (sortType) {
        case LocalSortType.name:
          return a.name.compareTo(b.name);
        case LocalSortType.nameDesc:
          return b.name.compareTo(a.name);
        case LocalSortType.timeDesc:
          return (b.lastUpdateTime ?? b.time)
              .compareTo(a.lastUpdateTime ?? a.time);
        case LocalSortType.timeAsc:
          return (a.lastUpdateTime ?? a.time)
              .compareTo(b.lastUpdateTime ?? b.time);
        case LocalSortType.author:
          return a.author.compareTo(b.author);
        case LocalSortType.lastRead:
          final ta = history['${a.sourceKey}:${a.id}']?.time ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final tb = history['${b.sourceKey}:${b.id}']?.time ??
              DateTime.fromMillisecondsSinceEpoch(0);
          return tb.compareTo(ta);
        case LocalSortType.defaultSort:
          return 0;
      }
    });
    return out;
  }

  /// 排序面板（原版功能還原）：7 個選項 + 確認
  void showSortDialog() {
    // 注意：選中的臨時值必須放在 builder【外面】——
    // 放在 StatefulBuilder 內每次重建都會被重置回原值，導致點不動
    var current = _sortType;
    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('排序'),
            content: RadioGroup<LocalSortType>(
              groupValue: current,
              onChanged: (v) => setDialogState(() {
                if (v != null) current = v;
              }),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  RadioListTile<LocalSortType>(
                    title: Text('預設'), value: LocalSortType.defaultSort),
                  RadioListTile<LocalSortType>(
                    title: Text('名稱升序'), value: LocalSortType.name),
                  RadioListTile<LocalSortType>(
                    title: Text('名稱降序'), value: LocalSortType.nameDesc),
                  RadioListTile<LocalSortType>(
                    title: Text('最新優先'), value: LocalSortType.timeDesc),
                  RadioListTile<LocalSortType>(
                    title: Text('最早優先'), value: LocalSortType.timeAsc),
                  RadioListTile<LocalSortType>(
                    title: Text('作者'), value: LocalSortType.author),
                  RadioListTile<LocalSortType>(
                    title: Text('最近閱讀'), value: LocalSortType.lastRead),
                ],
              ),
            ),
            actions: [
              FilledButton(
                onPressed: () {
                  setState(() => _sortType = current);
                  Navigator.pop(dialogContext);
                },
                child: const Text('確認'),
              ),
            ],
          );
        });
      },
    );
  }

  Future<void> _deleteSelected() async {
    final fav = LocalFavoritesManager();
    final items = _comics();
    for (final c in items) {
      if (!_selected.contains('${c.sourceKey}:${c.id}')) continue;
      final type = ComicType.fromKey(c.sourceKey);
      for (final folder in fav.find(c.id, type)) {
        fav.deleteComicWithId(folder, c.id, type);
      }
    }
    setState(() {
      _editMode = false;
      _selected.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final fav = LocalFavoritesManager();
    final folders = fav.folderNames;
    final items = _comics();
    return Column(
      children: [
        SizedBox(
          height: 44,
          child: Row(
            children: [
              const SizedBox(width: 16),
              // 資料夾選擇（保留原收藏夾功能）——
              // PopupMenu 在這個頁面層級點不動，改用底部彈層
              InkWell(
                onTap: () => _pickFolder(folders),
                child: Row(
                  children: [
                    Text(_folder ?? '漫畫',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
                    const Icon(Icons.arrow_drop_down, size: 20),
                  ],
                ),
              ),
              const Spacer(),
              // 排序（原版功能）：有非預設排序時高亮
              InkWell(
                onTap: showSortDialog,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(
                    Icons.sort,
                    size: 22,
                    color: _sortType != LocalSortType.defaultSort
                        ? context.colorScheme.primary
                        : context.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              InkWell(
                onTap: () => setState(() {
                  _editMode = !_editMode;
                  _selected.clear();
                }),
                child: Text(_editMode ? '完成' : '編輯',
                    style: TextStyle(
                        fontSize: 13, color: context.colorScheme.primary)),
              ),
              const SizedBox(width: 16),
            ],
          ),
        ),
        // 直列詳情卡（一列一個）：用 SliverGridComics 的詳細模式，
        // 它自帶正確高度（ListView 裡 ComicTile 會因無限高度而不可見）
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Text('還沒有收藏，去首頁逛逛吧',
                      style:
                          TextStyle(color: context.colorScheme.outline)))
              : CustomScrollView(
                  slivers: [
                    SliverGridComics(
                      comics: items,
                      forceDetailedMode: true,
                      // 加高卡片：讓「上次閱讀」那行進得了可視範圍
                      detailedItemHeight: 200,
                      // 最後閱讀時間（用戶要求：收藏卡片也顯示）
                      lastReadTimeBuilder: (c) {
                        final h = _histMap['${c.sourceKey}:${c.id}'];
                        if (h == null) return null;
                        final t = h.time;
                        return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} '
                            '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
                      },
                      selections: _editMode
                          ? {
                              for (final c in items)
                                c: _selected
                                    .contains('${c.sourceKey}:${c.id}')
                            }
                          : null,
                      onTapWithIndex: _editMode
                          ? (c, heroID, i) => setState(() {
                                final key = '${c.sourceKey}:${c.id}';
                                _selected.contains(key)
                                    ? _selected.remove(key)
                                    : _selected.add(key);
                              })
                          : null,
                    ),
                  ],
                ),
        ),
        if (_editMode)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        setState(() {
                          final all = {
                            for (final c in _comics())
                              '${c.sourceKey}:${c.id}'
                          };
                          if (_selected.length == all.length) {
                            _selected.clear();
                          } else {
                            _selected
                              ..clear()
                              ..addAll(all);
                          }
                        });
                      },
                      child: Text(_selected.length == _comics().length
                          ? '全不選'
                          : '全選'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed:
                          _selected.isEmpty ? null : _deleteSelected,
                      child: Text('取消收藏（${_selected.length}）'),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// ==================== Tab 3: 足跡（真數據：HistoryManager） ====================
class _ShelfHistoryTab extends StatefulWidget {
  const _ShelfHistoryTab();

  @override
  State<_ShelfHistoryTab> createState() => _ShelfHistoryTabState();
}

class _ShelfHistoryTabState extends State<_ShelfHistoryTab> {
  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    HistoryManager().addListener(_onChanged);
  }

  @override
  void dispose() {
    HistoryManager().removeListener(_onChanged);
    super.dispose();
  }

  Future<void> _clearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除足跡？'),
        content: const Text('會刪除所有閱讀記錄（收藏不受影響），此操作不可復原。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('取消'.tl)),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('清除'.tl)),
        ],
      ),
    );
    if (ok == true) HistoryManager().clearHistory();
  }

  Future<void> _removeOne(History h) async {
    // remove 是 void async（不回傳 Future），直接調用即可
    HistoryManager().remove(h.id, ComicType.fromKey(h.sourceKey));
  }

  @override
  Widget build(BuildContext context) {
    final list = List<History>.from(HistoryManager().getAll())
      ..sort((a, b) => b.time.compareTo(a.time)); // 最近讀的在前
    return Column(
      children: [
        SizedBox(
          height: 44,
          child: Row(
            children: [
              const SizedBox(width: 16),
              const Text('漫畫',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const Spacer(),
              if (list.isNotEmpty)
                InkWell(
                  onTap: _clearAll,
                  child: Text('清除足跡',
                      style: TextStyle(
                          fontSize: 13,
                          color: context.colorScheme.primary)),
                ),
              const SizedBox(width: 16),
            ],
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? Center(
                  child: Text('還沒有閱讀足跡',
                      style:
                          TextStyle(color: context.colorScheme.outline)))
              : ListView.builder(
                  padding: const EdgeInsets.all(10),
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final h = list[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Row(
                          children: [
                            InkWell(
                              onTap: () => _open(h),
                              child: _shelfCover(context, h.cover,
                                  h.sourceKey, h.id, 64, 86),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: InkWell(
                                onTap: () => _open(h),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(h.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight:
                                                FontWeight.w600)),
                                    const SizedBox(height: 6),
                                    Text('閱讀至第${h.ep}話 · 第${h.page}頁',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: context
                                                .colorScheme.outline)),
                                    Text(
                                      '${h.time.year}-${h.time.month.toString().padLeft(2, '0')}-${h.time.day.toString().padLeft(2, '0')} ${h.time.hour.toString().padLeft(2, '0')}:${h.time.minute.toString().padLeft(2, '0')}',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color:
                                              context.colorScheme.outline),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Column(
                              children: [
                                OutlinedButton(
                                  onPressed: () => _continue(h),
                                  child: const Text('繼續觀看'),
                                ),
                                const SizedBox(height: 6),
                                OutlinedButton(
                                  onPressed: () => _removeOne(h),
                                  child: const Text('刪除記錄'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _open(History h) {
    context.to(() => ComicPage(
        id: h.id, sourceKey: h.sourceKey, cover: h.cover, title: h.title));
  }

  /// 繼續觀看：先向源取章節表（閱讀器需要章節 ID 才能要圖），
  /// 成功才直達上次位置；失敗退回詳情頁。
  Future<void> _continue(History h) async {
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
