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
import 'package:venera/foundation/res.dart';
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

class _ShelfPageState extends State<ShelfPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  NaviPaneState? _naviPane;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  void _onMainNavigationTap(int index) {
    if (index != 1 || !mounted) return;
    // Returning to Favorites always starts from the local collection tab.
    _tabs.animateTo(0);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final pane = NaviPane.of(context);
    if (identical(_naviPane, pane)) return;
    _naviPane?.removeNaviItemTapListener(_onMainNavigationTap);
    _naviPane = pane;
    _naviPane!.addNaviItemTapListener(_onMainNavigationTap);
  }

  @override
  void dispose() {
    _naviPane?.removeNaviItemTapListener(_onMainNavigationTap);
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final largeType = MediaQuery.textScalerOf(context).scale(14) > 19;
              final stackActions = largeType && constraints.maxWidth < 520;
              final cacheAction = TextButton.icon(
                onPressed: () => context.to(() => const LocalComicsPage()),
                icon: const Icon(Icons.download_outlined, size: 18),
                label: const Text('緩存中心'),
                style: TextButton.styleFrom(
                  minimumSize: const Size(44, 44),
                  foregroundColor: context.colorScheme.onSurfaceVariant,
                  textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TabBar(
                          controller: _tabs,
                          isScrollable: true,
                          tabAlignment: TabAlignment.start,
                          dividerColor: Colors.transparent,
                          labelStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                          unselectedLabelColor: context.colorScheme.onSurfaceVariant,
                          labelPadding: const EdgeInsets.symmetric(horizontal: 12),
                          tabs: const [
                            Tab(text: '收藏'),
                            Tab(text: '網絡收藏'),
                            Tab(text: '足跡'),
                          ],
                        ),
                      ),
                      if (!stackActions) cacheAction,
                      const SizedBox(width: 8),
                    ],
                  ),
                  if (stackActions)
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: cacheAction,
                      ),
                    ),
                  Divider(height: 1, thickness: .5, color: VeneraDesignTokens.of(context).separator),
                ],
              );
            },
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: const [
                _ShelfFavTab(),
                _ShelfNetworkFavTab(),
                _ShelfHistoryTab(),
              ],
            ),
          ),
        ],
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

  /// 收藏排序：当前文件夹可覆盖全局默认排序；未设置时继承全局。
  LocalSortType get _sortType {
    final overrides = appdata.implicitData['local_favorites_folder_sort'];
    final folderKey = _folder ?? '';
    final value = overrides is Map
        ? overrides[folderKey]?.toString()
        : null;
    final v = value ?? appdata.implicitData['local_favorites_sort']?.toString();
    for (final t in LocalSortType.values) {
      if (t.value == v) return t;
    }
    return LocalSortType.defaultSort;
  }

  set _sortType(LocalSortType t) {
    final folderKey = _folder ?? '';
    final raw = appdata.implicitData['local_favorites_folder_sort'];
    final overrides = raw is Map
        ? Map<String, dynamic>.from(raw)
        : <String, dynamic>{};
    if (folderKey.isEmpty) {
      appdata.implicitData['local_favorites_sort'] = t.value;
    } else if (t == LocalSortType.defaultSort) {
      overrides.remove(folderKey);
    } else {
      overrides[folderKey] = t.value;
    }
    if (overrides.isEmpty) {
      appdata.implicitData.remove('local_favorites_folder_sort');
    } else {
      appdata.implicitData['local_favorites_folder_sort'] = overrides;
    }
    appdata.writeImplicitData();
  }

  void _applySortToAllFolders(LocalSortType t) {
    appdata.implicitData['local_favorites_sort'] = t.value;
    appdata.implicitData.remove('local_favorites_folder_sort');
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
    HistoryManager().addListener(_onChanged);
  }

  @override
  void dispose() {
    LocalFavoritesManager().removeListener(_onChanged);
    HistoryManager().removeListener(_onChanged);
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
        case LocalSortType.sizeAsc:
        case LocalSortType.sizeDesc:
          // Size sorting is implemented by the 3.0 local favorites page;
          // preserve the legacy shelf option without breaking its data view.
          return 0;
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
              if (_folder != null)
                TextButton(
                  onPressed: () {
                    setState(() => _applySortToAllFolders(current));
                    Navigator.pop(dialogContext);
                  },
                  child: const Text('应用到全部文件夹'),
                ),
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
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          child: Row(
            children: [
              // Keep long folder names flexible; sorting and editing remain
              // reachable even at narrow widths and accessibility text sizes.
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => _pickFolder(folders),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 44),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                _folder ?? '全部漫畫',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(Icons.keyboard_arrow_down, size: 20, color: context.colorScheme.onSurfaceVariant),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: '排序',
                onPressed: showSortDialog,
                icon: Icon(
                  Icons.sort,
                  size: 22,
                  color: _sortType != LocalSortType.defaultSort
                      ? context.colorScheme.primary
                      : context.colorScheme.onSurfaceVariant,
                ),
              ),
              TextButton(
                onPressed: () => setState(() {
                  _editMode = !_editMode;
                  _selected.clear();
                }),
                style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                child: Text(_editMode ? '完成' : '編輯'),
              ),
            ],
          ),
        ),
        // 直列詳情卡（一列一個）：用 SliverGridComics 的詳細模式，
        // 它自帶正確高度（ListView 裡 ComicTile 會因無限高度而不可見）
        Expanded(
          child: items.isEmpty
              ? const _ShelfEmptyState(
                  icon: Icons.bookmarks_outlined,
                  message: '還沒有收藏，去首頁逛逛吧',
                )
              : CustomScrollView(
                  slivers: [
                    SliverGridComics(
                      comics: items,
                      // Display mode, tile scale, and resulting layout all come
                      // from the native browsing settings. Keep the favorite
                      // metadata supplied by ComicTile; it is resolved from
                      // local stores and does not issue one request per tile.
                      hideBlocked: false,
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

/// ==================== Tab 2: 網絡收藏（來源原生 FavoriteData） ====================
class _ShelfNetworkFavTab extends StatefulWidget {
  const _ShelfNetworkFavTab();

  @override
  State<_ShelfNetworkFavTab> createState() => _ShelfNetworkFavTabState();
}

class _ShelfNetworkFavTabState extends State<_ShelfNetworkFavTab> {
  late final List<ComicSource> _sources;
  ComicSource? _source;
  Map<String, String> _folders = const {};
  String? _folder;
  String? _error;
  int _generation = 0;
  bool _foldersReady = false;
  bool _foldersLoading = false;

  @override
  void initState() {
    super.initState();
    _sources = [
      for (final source in ComicSource.all())
        if (source.favoriteData?.loadComic != null) source,
    ];
    _source = _sources.isEmpty ? null : _sources.first;
    _loadFolders();
  }

  Future<void> _loadFolders() async {
    final source = _source;
    final load = source?.favoriteData?.loadFolders;
    final generation = ++_generation;
    if (source == null) {
      if (mounted) setState(() {
        _folders = const {};
        _folder = null;
        _foldersReady = false;
        _foldersLoading = false;
      });
      return;
    }
    if (load == null) {
      if (mounted) setState(() {
        _folders = const {};
        _folder = null;
        _foldersReady = true;
        _foldersLoading = false;
      });
      return;
    }
    setState(() {
      _error = null;
      _foldersReady = false;
      _foldersLoading = true;
    });
    try {
      final result = await load();
      if (!mounted || generation != _generation) return;
      if (!result.success) throw StateError(result.errorMessage ?? '收藏夾載入失敗');
      final folders = Map<String, String>.from(result.data);
      // The mobile favorite endpoint accepts folder_id=0 as the all-favorites
      // view, but some source adapters omit that synthetic folder from their
      // folder map. Always expose it in the host so the first view cannot land
      // on an arbitrary empty real folder such as 韓國.
      folders.putIfAbsent('0', () => '漫畫');
      final allId = source.favoriteData?.allFavoritesId;
      final selected = allId != null && folders.containsKey(allId)
          ? allId
          : '0';
      setState(() {
        _folders = folders;
        _folder = selected;
        _foldersReady = true;
        _foldersLoading = false;
      });
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(() {
          _error = e.toString();
          _foldersReady = false;
          _foldersLoading = false;
        });
      }
    }
  }

  void _selectSource(ComicSource source) {
    if (_source?.key == source.key) return;
    setState(() {
      _source = source;
      _folders = const {};
      _folder = null;
      _foldersReady = false;
      _foldersLoading = false;
    });
    _loadFolders();
  }

  Widget _controls(BuildContext context) {
    final source = _source;
    if (source == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text('沒有可用的網絡收藏來源'),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _sources.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, index) {
                final item = _sources[index];
                return ChoiceChip(
                  label: Text(item.name),
                  selected: item.key == source.key,
                  onSelected: (_) => _selectSource(item),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          if (_folders.isNotEmpty)
            SizedBox(
              height: 38,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _folders.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, index) {
                  final id = _folders.keys.elementAt(index);
                  return ChoiceChip(
                    label: Text(_folders[id] ?? id),
                    selected: id == _folder,
                    onSelected: (_) => setState(() => _folder = id),
                  );
                },
              ),
            ),
          if (_foldersLoading)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: TextStyle(color: context.colorScheme.error)),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final source = _source;
    final favorite = source?.favoriteData;
    final load = favorite?.loadComic;
    if (source == null || load == null || !_foldersReady) {
      return _controls(context);
    }
    return ComicList(
      key: ValueKey('${source.key}:$_folder'),
      enableSelection: true,
      emptyText: _folder == '0' || _folder == null
          ? '網絡收藏是空的'
          : '此收藏夾沒有漫畫',
      leadingSliver: _controls(context).toSliver(),
      scrollbarTopPadding: context.padding.top + 48,
      loadPage: (page) => load(page, _folder),
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
              child: Text('Cancel'.tl)),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Clear'.tl)),
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
              ? const _ShelfEmptyState(
                  icon: Icons.history_rounded,
                  message: '還沒有閱讀足跡',
                )
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

  /// 立即進入閱讀器；章節表和圖片由 ReaderWithLoading 在閱讀器頁內載入。
  /// 收藏頁不再先彈阻塞式 loading dialog，也不等待一次完整詳情請求。
  void _continue(History h) {
    context.to(() => ReaderWithLoading(
          id: h.id,
          sourceKey: h.sourceKey,
          initialEp: h.ep,
          initialPage: h.page,
          initialGroup: h.group,
        ));
  }

}

/// Stable empty-state geometry shared by the local shelf and reading history.
class _ShelfEmptyState extends StatelessWidget {
  const _ShelfEmptyState({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32, color: context.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: context.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
