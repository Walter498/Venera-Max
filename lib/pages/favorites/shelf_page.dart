import 'package:flutter/material.dart';
import 'package:venera/components/components.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/comic_collection_store.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/favorites.dart';
import 'package:venera/foundation/history.dart';
import 'package:venera/foundation/image_provider/cached_image.dart';
import 'package:venera/pages/comic_details_page/comic_page.dart';
import 'package:venera/pages/downloading_page.dart';
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
      length: 3,
      child: Material(
        child: SafeArea(
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
                          Tab(text: '書單'),
                          Tab(text: '足跡'),
                        ],
                      ),
                    ),
                    // 緩存中心 → 下載管理頁
                    InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () =>
                          context.to(() => const DownloadingPage()),
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
                    _ShelfCollectionsTab(),
                    _ShelfHistoryTab(),
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
  String? _folder; // null = 全部
  bool _sortByUpdate = true; // true=更新時間 false=收藏時間
  bool _editMode = false;
  final Set<String> _selected = {};

  void _onChanged() {
    if (mounted) setState(() {});
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
    final out = List<FavoriteItem>.from(list);
    out.sort((a, b) {
      final ka = _sortByUpdate ? (a.lastUpdateTime ?? a.time) : a.time;
      final kb = _sortByUpdate ? (b.lastUpdateTime ?? b.time) : b.time;
      return kb.compareTo(ka); // 新的在前
    });
    return out;
  }

  /// 閱讀進度 map：'sourceKey:id' -> History
  Map<String, History> _historyMap() {
    final m = <String, History>{};
    for (final h in HistoryManager().getAll()) {
      m['${h.sourceKey}:${h.id}'] = h;
    }
    return m;
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
    final history = _historyMap();
    return Column(
      children: [
        SizedBox(
          height: 44,
          child: Row(
            children: [
              const SizedBox(width: 16),
              // 資料夾選擇（保留原收藏夾功能）
              PopupMenuButton<String?>(
                onSelected: (v) => setState(() => _folder = v),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: null, child: Text('全部漫畫')),
                  for (final f in folders)
                    PopupMenuItem(value: f, child: Text(f)),
                ],
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
              // 排序切換（真排序：更新時間/收藏時間）
              PopupMenuButton<bool>(
                onSelected: (v) => setState(() => _sortByUpdate = v),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: true, child: Text('更新排序')),
                  const PopupMenuItem(value: false, child: Text('收藏排序')),
                ],
                child: Row(children: [
                  Text(_sortByUpdate ? '更新排序' : '收藏排序',
                      style: TextStyle(
                          fontSize: 13, color: context.colorScheme.primary)),
                  Icon(Icons.expand_more,
                      size: 18, color: context.colorScheme.primary),
                ]),
              ),
              const SizedBox(width: 12),
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
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Text('還沒有收藏，去首頁逛逛吧',
                      style:
                          TextStyle(color: context.colorScheme.outline)))
              : GridView.builder(
                  padding: const EdgeInsets.all(10),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.52,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final c = items[i];
                    final key = '${c.sourceKey}:${c.id}';
                    final h = history[key];
                    final selected = _selected.contains(key);
                    return _favCard(context, c, h, selected);
                  },
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
                          _selected.length == all.length
                              ? _selected.clear()
                              : _selected
                              ..clear()
                              ..addAll(all);
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

  Widget _favCard(
      BuildContext context, FavoriteItem c, History? h, bool selected) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        if (_editMode) {
          setState(() {
            final key = '${c.sourceKey}:${c.id}';
            _selected.contains(key)
                ? _selected.remove(key)
                : _selected.add(key);
          });
        } else {
          context.to(() => ComicPage(
              id: c.id,
              sourceKey: c.sourceKey,
              cover: c.cover,
              title: c.title));
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: selected
                          ? context.colorScheme.primary
                          : context.colorScheme.outlineVariant,
                      width: selected ? 2.5 : 1,
                    ),
                  ),
                  child: _shelfCover(
                      context, c.cover, c.sourceKey, c.id, 400, 600),
                ),
                if ((_shelfTimeBadge(c.lastUpdateTime)).isNotEmpty)
                  Positioned(
                    left: 0,
                    top: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: context.colorScheme.primary,
                        borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(8),
                            bottomRight: Radius.circular(8)),
                      ),
                      child: Text(_shelfTimeBadge(c.lastUpdateTime),
                          style: TextStyle(
                              fontSize: 10,
                              color: context.colorScheme.onPrimary)),
                    ),
                  ),
                if (selected)
                  Positioned(
                    right: 4,
                    top: 4,
                    child: Icon(Icons.check_circle,
                        size: 20, color: context.colorScheme.primary),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(c.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600)),
          Text(
            h != null ? '閱至第${h.ep}話' : '未開始閱讀',
            maxLines: 1,
            style: TextStyle(
                fontSize: 11, color: context.colorScheme.outline),
          ),
        ],
      ),
    );
  }
}

/// ==================== Tab 2: 書單（真數據：ComicCollectionStore） ====================
class _ShelfCollectionsTab extends StatefulWidget {
  const _ShelfCollectionsTab();

  @override
  State<_ShelfCollectionsTab> createState() => _ShelfCollectionsTabState();
}

class _ShelfCollectionsTabState extends State<_ShelfCollectionsTab> {
  Future<void> _createCollection() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('創建書單'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '書單名稱'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: Text('取消'.tl)),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: Text('創建'.tl)),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      ComicCollectionStore.create(name: name.trim());
      if (mounted) setState(() {});
    }
  }

  Future<void> _removeCollection(ComicCollection c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('移除書單「${c.displayName}」？'),
        content: const Text('書單內的漫畫不會被刪除，只是解散這個書單。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('取消'.tl)),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('移除'.tl)),
        ],
      ),
    );
    if (ok == true) {
      ComicCollectionStore.remove(c.id);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final collections = ComicCollectionStore.all();
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
              InkWell(
                onTap: _createCollection,
                child: Text('+創建書單',
                    style: TextStyle(
                        fontSize: 13, color: context.colorScheme.primary)),
              ),
              const SizedBox(width: 16),
            ],
          ),
        ),
        Expanded(
          child: collections.isEmpty
              ? Center(
                  child: Text('還沒有書單，點右上角「+創建書單」',
                      style:
                          TextStyle(color: context.colorScheme.outline)))
              : ListView.builder(
                  padding: const EdgeInsets.all(10),
                  itemCount: collections.length,
                  itemBuilder: (context, i) {
                    final c = collections[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        // 進書單詳情（沿用現有合集頁面機制）
                        onTap: () => context.to(() => ComicPage(
                            id: c.id,
                            sourceKey: c.sourceKey,
                            cover: c.displayCover,
                            title: c.displayName)),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              _shelfCover(context, c.displayCover,
                                  c.sourceKey, c.id, 56, 76),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(c.displayName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight:
                                                FontWeight.w600)),
                                    const SizedBox(height: 4),
                                    Text('共${c.members.length}本',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: context
                                                .colorScheme.outline)),
                                    Text(
                                      '創建於 ${c.createdAt.year}-${c.createdAt.month.toString().padLeft(2, '0')}-${c.createdAt.day.toString().padLeft(2, '0')}',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color:
                                              context.colorScheme.outline),
                                    ),
                                  ],
                                ),
                              ),
                              OutlinedButton(
                                onPressed: () => _removeCollection(c),
                                child: const Text('移除書單'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
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
    await HistoryManager().remove(h.id, ComicType.fromKey(h.sourceKey));
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
                                  onPressed: () => _open(h),
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
}
