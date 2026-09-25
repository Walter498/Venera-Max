part of 'comic_page.dart';

/// 從章節標題解析話號（「第123话」「第123話」…），解析不到回傳 -1。
int _chapterNumberOf(String? title) {
  if (title == null) return -1;
  final m = RegExp(r'第\s*(\d+)\s*[话話]').firstMatch(title);
  if (m == null) return -1;
  return int.tryParse(m.group(1)!) ?? -1;
}

/// 「按話號排序」開啟時重排顯示清單。
///
/// 用途：來源給的順序不可靠時的保險。最典型的情況是源用「章節 id」當 key ——
/// JS 物件對整數字串 key 一律按【數值升序】列舉，補更/重傳的章節 id 較大，
/// 就會被搬到後面（實測「魔皇大管家」73/83/86~88/90 話跑到 91 話之後）。
/// 只重排顯示用的 index 清單，章節索引不被改寫，閱讀、下載、歷史不受影響。
/// 解析不到話號的章節排最後，並保持原本相對順序。
List<int> _sortByChapterNumber(List<int> visible, List<String> titles) {
  if (appdata.settings['chapterSortByNumber'] != true) return visible;
  final nums = <int, int>{};
  final pos = <int, int>{};
  for (var p = 0; p < visible.length; p++) {
    final i = visible[p];
    final n = _chapterNumberOf(i < titles.length ? titles[i] : null);
    nums[i] = n <= 0 ? 1 << 30 : n;
    pos[i] = p;
  }
  final out = List<int>.from(visible);
  out.sort((a, b) {
    final d = nums[a]! - nums[b]!;
    return d != 0 ? d : pos[a]! - pos[b]!;
  });
  return out;
}

class _ComicChapters extends StatelessWidget {
  const _ComicChapters({this.history, required this.groupedMode});

  final History? history;

  final bool groupedMode;

  @override
  Widget build(BuildContext context) {
    return groupedMode
        ? _GroupedComicChapters(history)
        : _NormalComicChapters(history);
  }
}

/// Shared multi-select state & actions for the chapters list.
///
/// Selection keys use the SAME string format the reader writes into
/// [History.readEpisode]: plain chapter index ("3") for normal comics, and
/// "group-chapter" ("2-5") for grouped comics. Keeping the format identical is
/// what makes a manual mark actually toggle the "visited" style.
mixin _ChapterSelectionMixin<T extends StatefulWidget> on State<T> {
  bool selectMode = false;

  /// Selected chapter keys (in reader format).
  final Set<String> selected = {};

  _ComicPageState get pageState;

  History? get history;

  set history(History? value);

  /// All selectable chapter keys in the current context.
  /// Normal: every chapter. Grouped: only the current group's chapters.
  Set<String> get selectableKeys;

  void enterSelectMode() {
    setState(() {
      selectMode = true;
      selected.clear();
    });
  }

  void exitSelectMode() {
    setState(() {
      selectMode = false;
      selected.clear();
    });
  }

  void toggleSelect(String key) {
    setState(() {
      if (!selected.remove(key)) {
        selected.add(key);
      }
    });
  }

  void selectAll() {
    setState(() {
      selected.addAll(selectableKeys);
    });
  }

  void invertSelection() {
    setState(() {
      final keys = selectableKeys;
      final next = keys.where((k) => !selected.contains(k)).toSet();
      selected
        ..removeAll(keys)
        ..addAll(next);
    });
  }

  /// Apply read/unread to the current selection, persist, and refresh.
  void _applyMark(bool read) {
    if (selected.isEmpty) {
      exitSelectMode();
      return;
    }
    final current = Set<String>.from(history?.readEpisode ?? const <String>{});
    if (read) {
      current.addAll(selected);
    } else {
      current.removeAll(selected);
    }
    final updated = HistoryManager().updateReadEpisodes(
      pageState.comic,
      current,
    );
    pageState.history = updated;
    setState(() {
      history = updated;
      selectMode = false;
      selected.clear();
    });
  }

  /// The toolbar shown in place of the title row while selecting.
  Widget buildSelectionBar(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;
        return Row(
          children: [
            Tooltip(
              message: "Cancel".tl,
              child: IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: exitSelectMode,
              ),
            ),
            Expanded(
              child: Text(
                "Selected @count".tlParams({"count": selected.length}),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (compact)
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded),
                onSelected: (value) {
                  switch (value) {
                    case 'all':
                      selectAll();
                      break;
                    case 'invert':
                      invertSelection();
                      break;
                    case 'read':
                      _applyMark(true);
                      break;
                    case 'unread':
                      _applyMark(false);
                      break;
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(value: 'all', child: Text("Select All".tl)),
                  PopupMenuItem(
                    value: 'invert',
                    child: Text("Invert Selection".tl),
                  ),
                  PopupMenuItem(
                    value: 'read',
                    enabled: selected.isNotEmpty,
                    child: Text("Mark as read".tl),
                  ),
                  PopupMenuItem(
                    value: 'unread',
                    enabled: selected.isNotEmpty,
                    child: Text("Mark as unread".tl),
                  ),
                ],
              )
            else ...[
              Tooltip(
                message: "Select All".tl,
                child: IconButton(
                  icon: const Icon(Icons.select_all_rounded),
                  onPressed: selectAll,
                ),
              ),
              Tooltip(
                message: "Invert Selection".tl,
                child: IconButton(
                  icon: const Icon(Icons.flip_rounded),
                  onPressed: invertSelection,
                ),
              ),
              Tooltip(
                message: "Mark as read".tl,
                child: IconButton(
                  icon: const Icon(Icons.done_all_rounded),
                  onPressed: selected.isEmpty ? null : () => _applyMark(true),
                ),
              ),
              Tooltip(
                message: "Mark as unread".tl,
                child: IconButton(
                  icon: const Icon(Icons.remove_done_rounded),
                  onPressed: selected.isEmpty ? null : () => _applyMark(false),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  /// The trailing controls of the title row when NOT selecting.
  /// 預覽封面（切換封面網格） + 顯示全部/收起（箭頭）
  Widget buildNormalTitle(
    BuildContext context, {
    required bool reverse,
    required VoidCallback onToggleOrder,
    required bool showAll,
    required VoidCallback onToggleShowAll,
  }) {
    final gridMode = appdata.settings['chapterCoverGrid'] == true;
    final sortByNumber = appdata.settings['chapterSortByNumber'] == true;
    return _ComicSectionHeader(
      icon: Icons.view_list_rounded,
      title: "Chapters".tl,
      horizontalPadding: 0,
      titleBadge: pageState.isDetailsLoading
          ? const _ChaptersUpdatingIndicator()
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: "Preview covers".tl,
            child: IconButton(
              icon: Icon(
                gridMode ? Icons.view_list_rounded : Icons.grid_view_rounded,
              ),
              onPressed: () {
                setState(() {
                  appdata.settings['chapterCoverGrid'] = !gridMode;
                });
                appdata.saveData();
              },
            ),
          ),
          // 按話號排序：來源順序不可靠時的保險（例如源用章節 id 當 key，
          // 被 JS 按數值重排 → 補更的章節跑到後面）。預設關閉 = 用來源順序。
          Tooltip(
            message: sortByNumber
                ? "Use source order".tl
                : "Sort by chapter number".tl,
            child: IconButton(
              icon: Icon(
                sortByNumber
                    ? Icons.format_list_numbered_rounded
                    : Icons.sort_rounded,
              ),
              onPressed: () {
                setState(() {
                  appdata.settings['chapterSortByNumber'] = !sortByNumber;
                });
                appdata.saveData();
              },
            ),
          ),
          // 倒序：按一下從第一話開始顯示，再按一下從最後一話開始顯示
          Tooltip(
            message: (reverse ? "Oldest first" : "Newest first").tl,
            child: IconButton(
              icon: Icon(
                reverse
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
              ),
              onPressed: () {
                onToggleOrder();
                appdata.settings["reverseChapterOrder"] = !reverse;
                appdata.saveData();
              },
            ),
          ),
          Tooltip(
            message: (showAll ? "Collapse" : "Expand").tl,
            child: IconButton(
              icon: Icon(
                showAll
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
              ),
              onPressed: onToggleShowAll,
            ),
          ),
        ],
      ),
    );
  }
}

class _NormalComicChapters extends StatefulWidget {
  const _NormalComicChapters(this.history);

  final History? history;

  @override
  State<_NormalComicChapters> createState() => _NormalComicChaptersState();
}

class _NormalComicChaptersState extends State<_NormalComicChapters>
    with _ChapterSelectionMixin {
  late _ComicPageState state;

  late bool reverse;

  bool showAll = false;

  History? _history;

  late ComicChapters chapters;

  @override
  _ComicPageState get pageState => state;

  @override
  History? get history => _history;

  @override
  set history(History? value) => _history = value;

  /// Original flat indices actually rendered, in list order. Hiding duplicates
  /// only removes entries here — the indices themselves keep their original
  /// values, because [_ComicPageActions.read] and the download picker address
  /// chapters by flat index.
  late List<int> visible;

  @override
  Set<String> get selectableKeys =>
      visible.map((i) => (i + 1).toString()).toSet();

  void _computeVisible() {
    final hidden = state.hideDuplicateChapters
        ? state.duplicateChapterIndices
        : const <int>{};
    visible = [
      for (var i = 0; i < chapters.length; i++)
        if (!hidden.contains(i)) i,
    ];
    visible = _sortByChapterNumber(visible, chapters.titles.toList());
  }

  @override
  void initState() {
    super.initState();
    reverse = appdata.settings["reverseChapterOrder"] ?? false;
    _history = widget.history;
  }

  @override
  void didChangeDependencies() {
    state = context.findAncestorStateOfType<_ComicPageState>()!;
    chapters = state.comic.chapters!;
    _computeVisible();
    super.didChangeDependencies();
  }

  @override
  void didUpdateWidget(covariant _NormalComicChapters oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A background details refresh can replace the chapter map while this
    // widget stays mounted (cache-first load). Freeze it during multi-select:
    // selection keys are chapter indices, so a list that grows or reorders
    // mid-selection would shift them under the user. Re-read once selection
    // ends; picked up on the next rebuild.
    if (!selectMode) {
      setState(() {
        chapters = state.comic.chapters!;
        _computeVisible();
        _history = widget.history;
      });
    }
  }

  /// 章節封面網格（詳情頁「封面預覽」模式）
  ///
  /// 收起時改用 Wrap + 固定格子尺寸（SliverToBoxAdapter 包住）：
  /// 高度【物理上】就是 limit 格的 3 行，絕對不可能出現
  /// 「格子隱藏但佔位」的那種大片空白。展開時才用 SliverGrid。
  Widget buildChapterCoverGrid(BuildContext context, ComicDetails details,
      {int limit = 0}) {
    final collapsed = limit > 0 && visible.length > limit;
    final total = collapsed ? limit : visible.length;

    /// 顯示槽位 → visible 下標：倒序時從最新一話往回數
    int mapSlot(int slot) => reverse ? visible.length - 1 - slot : slot;

    Widget cell(int slot) {
      final i = mapSlot(slot);
      final key = chapters.ids.elementAt(i);
      final value = chapters[key]!;
      final epKey = (i + 1).toString();
      final visited = (_history?.readEpisode ?? const {}).contains(epKey);
      final covers = details.chapterCovers ?? const <String, String>{};
      final thumbs = details.thumbnails ?? const <String>[];
      // 封面優先級：chapterCovers → thumbnails → 惰性向源要該話第一頁
      String? coverUrl =
          (covers[key]?.isNotEmpty == true) ? covers[key] : null;
      if ((coverUrl == null || coverUrl.isEmpty) &&
          i < thumbs.length &&
          thumbs[i].isNotEmpty) {
        coverUrl = thumbs[i];
      }
      return KeyedSubtree(
        key: ValueKey('chapter-cover-$key'),
        child: InkWell(
          onTap: () => selectMode ? toggleSelect(epKey) : state.read(i + 1),
          borderRadius: BorderRadius.circular(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      // 必須走 App 的圖片載入器：它會套用源的 onImageLoad
                      // headers（帶 UA），Image.network 會被圖床 403。
                      child: _LazyChapterCover(
                        coverUrl: coverUrl,
                        placeholderIndex: i + 1,
                        sourceKey: details.sourceKey,
                        comicId: details.id,
                        epId: key,
                      ),
                    ),
                    if (visited)
                      Positioned(
                        left: 0,
                        top: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: context.colorScheme.primary,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(10),
                              bottomRight: Radius.circular(10),
                            ),
                          ),
                          child: Text(
                            "Last read".tl,
                            style: TextStyle(
                              fontSize: 10,
                              color: context.colorScheme.onPrimary,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11),
              ),
            ],
          ),
        ),
      );
    }

    if (collapsed) {
      return SliverToBoxAdapter(
        child: LayoutBuilder(
          builder: (context, c) {
            const cross = 5;
            const spacing = 10.0;
            final cellW = (c.maxWidth - spacing * (cross - 1)) / cross;
            final cellH = cellW / 0.58 + 20;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (var slot = 0; slot < total; slot++)
                  SizedBox(width: cellW, height: cellH, child: cell(slot)),
              ],
            );
          },
        ),
      );
    }

    return SliverGrid(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.58,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, slot) => cell(slot),
        childCount: total,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // The duplicate switch is toggled from the page menu, which only calls
    // update() on the page state — recompute here so the change lands without
    // waiting for a details refresh.
    _computeVisible();
    return SliverLayoutBuilder(
      builder: (context, constrains) {
        final gridMode = appdata.settings['chapterCoverGrid'] == true;
        // 封面模式收起時固定 3 行 × 5 欄 = 15 格；文字模式收起時 8 行。
        const coverLimit = 3 * 5;
        int length = visible.length;
        bool canShowAll = showAll || selectMode;
        if (!canShowAll) {
          if (gridMode) {
            if (visible.length <= coverLimit) {
              canShowAll = true;
            }
          } else {
            var width = constrains.crossAxisExtent - 16;
            var crossItems = width ~/ 200;
            if (width % 200 != 0) {
              crossItems += 1;
            }
            length = math.min(length, crossItems * 8);
            if (length == visible.length) {
              canShowAll = true;
            }
          }
        }
        return SliverMainAxisGroup(
          slivers: [
            SliverToBoxAdapter(
              child: selectMode
                  ? buildSelectionBar(context).paddingHorizontal(8)
                  : buildNormalTitle(
                      context,
                      reverse: reverse,
                      onToggleOrder: () => setState(() => reverse = !reverse),
                      showAll: showAll,
                      onToggleShowAll: () => setState(() => showAll = !showAll),
                    ),
            ),
            if (gridMode)
              buildChapterCoverGrid(
                context,
                pageState.comic,
                limit: canShowAll ? 0 : coverLimit,
              ),
            if (gridMode)
              const SliverPadding(padding: EdgeInsets.only(bottom: 12)),
            if (!gridMode)
              SliverGrid(
              delegate: SliverChildBuilderDelegate(childCount: length, (
                context,
                slot,
              ) {
                if (reverse) {
                  slot = visible.length - slot - 1;
                }
                // Display slot -> original flat index. Every consumer downstream
                // (read(), history keys, download) addresses chapters by that
                // index, so hiding must never renumber them.
                var i = visible[slot];
                var key = chapters.ids.elementAt(i);
                var value = chapters[key]!;
                var epKey = (i + 1).toString();
                bool visited = (_history?.readEpisode ?? const {}).contains(
                  epKey,
                );
                bool isSelected = selected.contains(epKey);
                return Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
                  child: Material(
                    color: isSelected
                        ? context.colorScheme.primaryContainer
                        : context.colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      onTap: () =>
                          selectMode ? toggleSelect(epKey) : state.read(i + 1),
                      onLongPress: selectMode
                          ? null
                          : () {
                              enterSelectMode();
                              toggleSelect(epKey);
                            },
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Center(
                          child: Text(
                            value,
                            maxLines: 1,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isSelected
                                  ? context.colorScheme.onPrimaryContainer
                                  : visited
                                  ? context.colorScheme.outline
                                  : null,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
              gridDelegate: const SliverGridDelegateWithFixedHeight(
                maxCrossAxisExtent: 220,
                itemHeight: 44,
              ),
            ).sliverPadding(EdgeInsets.zero),
            // 「顯示全部」按鈕：文字模式與封面模式都要出現
            //（原本只有 !gridMode 才渲染 → 封面模式永遠沒有按鈕）
            if (!canShowAll)
              SliverToBoxAdapter(
                child: Align(
                  alignment: Alignment.center,
                  child: TextButton.icon(
                    icon: const Icon(Icons.arrow_drop_down),
                    onPressed: () {
                      setState(() {
                        showAll = true;
                      });
                    },
                    label: Text("${"Show all".tl} (${visible.length})"),
                  ).paddingTop(12),
                ),
              ),
            const SliverPadding(padding: EdgeInsets.only(bottom: 12)),
          ],
        );
      },
    );
  }
}

class _GroupedComicChapters extends StatefulWidget {
  const _GroupedComicChapters(this.history);

  final History? history;

  @override
  State<_GroupedComicChapters> createState() => _GroupedComicChaptersState();
}

class _GroupedComicChaptersState extends State<_GroupedComicChapters>
    with SingleTickerProviderStateMixin, _ChapterSelectionMixin {
  late _ComicPageState state;

  late bool reverse;

  bool showAll = false;

  History? _history;

  late ComicChapters chapters;

  late TabController tabController;

  bool _hasTabController = false;

  late int index;

  @override
  _ComicPageState get pageState => state;

  @override
  History? get history => _history;

  @override
  set history(History? value) => _history = value;

  /// The collection this comic is, or null for an ordinary grouped comic. When
  /// set, each tab corresponds to one member, so tabs become editable.
  String? get _collectionId =>
      ComicCollectionStore.isCollectionSourceKey(state.comic.sourceKey)
      ? state.comic.id
      : null;

  /// Long-press / right-click actions for a collection's tab: rename the member
  /// or move it, since tab order is chapter order.
  void _showTabActions(int tabIndex) {
    final id = _collectionId;
    if (id == null) return;
    final collection = ComicCollectionStore.find(id);
    final member = collection?.members.elementAtOrNull(tabIndex);
    if (collection == null || member == null) return;
    final count = collection.members.length;

    showMenuX(context, Offset(context.width / 2, context.padding.top + 120), [
      MenuEntry(
        icon: Icons.label_outline,
        text: "Display name".tl,
        onClick: () {
          showInputDialog(
            context: App.rootContext,
            title: "Display name".tl,
            initialValue: member.displayName,
            hintText: "Leave empty to use the comic's title".tl,
            onConfirm: (value) {
              member.displayName = value;
              ComicCollectionStore.update(id, members: collection.members);
              _applyCollectionEdit();
              return null;
            },
          );
        },
      ),
      if (tabIndex > 0)
        MenuEntry(
          icon: Icons.arrow_back,
          text: "Move left".tl,
          onClick: () {
            ComicCollectionStore.reorderMember(id, tabIndex, tabIndex - 1);
            _applyCollectionEdit();
          },
        ),
      if (tabIndex < count - 1)
        MenuEntry(
          icon: Icons.arrow_forward,
          text: "Move right".tl,
          onClick: () {
            ComicCollectionStore.reorderMember(id, tabIndex, tabIndex + 1);
            _applyCollectionEdit();
          },
        ),
      MenuEntry(
        icon: Icons.remove_circle_outline,
        text: "Remove from collection".tl,
        color: context.colorScheme.error,
        onClick: () {
          ComicCollectionStore.removeMember(
            id,
            member.sourceKey,
            member.comicId,
          );
          _applyCollectionEdit();
        },
      ),
    ]);
  }

  /// Rebuilds the collection's source and reloads the detail, so the new tab
  /// name or order shows immediately. The source captures the chapter layout,
  /// so skipping the refresh would keep serving the old one.
  void _applyCollectionEdit() {
    ComicSourceManager().refreshCollectionSources();
    state.reloadDetails();
  }

  /// 0-based flat index of the first chapter in the current group.
  int get _groupOffset {
    var offset = 0;
    for (var j = 0; j < index; j++) {
      offset += chapters.getGroupByIndex(j).length;
    }
    return offset;
  }

  /// Indices WITHIN the current group that are actually rendered, in list order.
  /// Hiding duplicates only removes entries; the values keep their original
  /// within-group position, which is what the reader/history keys are built from.
  late List<int> visible;

  /// Within-group indices to hide for the current tab. Duplicates are detected
  /// per group, so a title repeated across tabs ("英文版"/"西班牙语" both having
  /// "第一话") is never touched.
  void _computeVisible() {
    if (chapters.groupCount == 0) {
      visible = const [];
      return;
    }
    final group = chapters.getGroupByIndex(index);
    final hidden = state.hideDuplicateChapters
        ? state.duplicateChapterIndices
        : const <int>{};
    final offset = _groupOffset;
    visible = [
      for (var i = 0; i < group.length; i++)
        if (!hidden.contains(offset + i)) i,
    ];
    visible = _sortByChapterNumber(visible, group.values.toList());
  }

  /// Selectable keys = ONLY the current group's visible chapters, in reader
  /// format "group-chapter" (both 1-based).
  @override
  Set<String> get selectableKeys =>
      visible.map((i) => "${index + 1}-${i + 1}").toSet();

  @override
  void initState() {
    super.initState();
    reverse = appdata.settings["reverseChapterOrder"] ?? false;
    _history = widget.history;
    if (_history?.group != null) {
      index = _history!.group! - 1;
    } else {
      index = 0;
    }
  }

  @override
  void didChangeDependencies() {
    state = context.findAncestorStateOfType<_ComicPageState>()!;
    chapters = state.comic.chapters!;
    _syncTabController();
    _computeVisible();
    super.didChangeDependencies();
  }

  void _syncTabController() {
    final length = chapters.groupCount;
    if (length == 0) {
      return;
    }
    index = math.min(math.max(index, 0), length - 1);
    if (_hasTabController && tabController.length == length) {
      return;
    }
    if (_hasTabController) {
      tabController.removeListener(onTabChange);
      tabController.dispose();
    }
    tabController = TabController(
      initialIndex: index,
      length: length,
      vsync: this,
    );
    tabController.addListener(onTabChange);
    _hasTabController = true;
  }

  void onTabChange() {
    if (index != tabController.index) {
      setState(() {
        index = tabController.index;
        showAll = false;
        // Duplicates are scoped per group, so the visible set is per tab.
        _computeVisible();
        // Selection is scoped to a group; leaving the group clears it.
        selected.clear();
      });
    }
  }

  @override
  void didUpdateWidget(covariant _GroupedComicChapters oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The chapter map is re-read on every rebuild, not just captured on first
    // mount: renaming/reordering a collection's members, or a background
    // details refresh adding chapters/tabs, reloads the detail in place, and a
    // captured map would keep showing the previous tabs until the page was left
    // and re-entered. Frozen during multi-select: selection keys are
    // group-chapter indices, so a list that grows or reorders mid-selection
    // would shift them under the user.
    if (!selectMode) {
      chapters = state.comic.chapters!;
      _syncTabController();
      _computeVisible();
      setState(() {
        _history = widget.history;
      });
    }
  }

  @override
  void dispose() {
    if (_hasTabController) {
      tabController.removeListener(onTabChange);
      tabController.dispose();
    }
    super.dispose();
  }

  /// In grouped mode the reader historically may have stored a chapter either
  /// as "group-chapter" (current format) or as a flat "rawIndex" (legacy /
  /// [chapters.dart] visited check tolerates both). When marking read we add
  /// the canonical "group-chapter" key; when marking unread we must also strip
  /// the matching flat key so the chapter doesn't stay greyed out.
  @override
  void _applyMark(bool read) {
    if (selected.isEmpty) {
      exitSelectMode();
      return;
    }
    final current = Set<String>.from(history?.readEpisode ?? const <String>{});
    final offset = _groupOffset;
    for (final groupedKey in selected) {
      // groupedKey == "${index+1}-${i+1}"; derive the flat 1-based index.
      final dashAt = groupedKey.indexOf('-');
      final within = int.tryParse(groupedKey.substring(dashAt + 1)) ?? 0;
      final rawKey = (offset + within).toString();
      if (read) {
        current.add(groupedKey);
      } else {
        current
          ..remove(groupedKey)
          ..remove(rawKey);
      }
    }
    final updated = HistoryManager().updateReadEpisodes(
      pageState.comic,
      current,
    );
    pageState.history = updated;
    setState(() {
      history = updated;
      selectMode = false;
      selected.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (chapters.groupCount == 0 || !_hasTabController) {
      return const SliverPadding(padding: EdgeInsets.zero);
    }
    // The duplicate switch is toggled from the page menu, which only calls
    // update() on the page state — recompute here so the change lands without
    // waiting for a details refresh.
    _computeVisible();
    return SliverLayoutBuilder(
      builder: (context, constrains) {
        var group = chapters.getGroupByIndex(index);
        int length = visible.length;
        bool canShowAll = showAll || selectMode;
        if (!canShowAll) {
          var width = constrains.crossAxisExtent - 16;
          var crossItems = width ~/ 200;
          if (width % 200 != 0) {
            crossItems += 1;
          }
          length = math.min(length, crossItems * 8);
          if (length == visible.length) {
            canShowAll = true;
          }
        }

        return SliverMainAxisGroup(
          slivers: [
            SliverToBoxAdapter(
              child: selectMode
                  ? buildSelectionBar(context).paddingHorizontal(8)
                  : buildNormalTitle(
                      context,
                      reverse: reverse,
                      onToggleOrder: () => setState(() => reverse = !reverse),
                      showAll: true,
                      onToggleShowAll: () {},
                    ),
            ),
            SliverToBoxAdapter(
              child: AppTabBar(
                withUnderLine: false,
                controller: tabController,
                tabs: [
                  for (var i = 0; i < chapters.groups.length; i++)
                    Tab(
                      child: _collectionId == null
                          ? Text(chapters.groups.elementAt(i))
                          // For a collection each tab IS a member comic, so the
                          // tab is where renaming and reordering it belongs.
                          : GestureDetector(
                              onLongPress: () => _showTabActions(i),
                              onSecondaryTapDown: (_) => _showTabActions(i),
                              child: Text(chapters.groups.elementAt(i)),
                            ),
                    ),
                ],
              ),
            ),
            SliverPadding(padding: const EdgeInsets.only(top: 8)),
            SliverGrid(
              delegate: SliverChildBuilderDelegate(childCount: length, (
                context,
                slot,
              ) {
                if (reverse) {
                  slot = visible.length - slot - 1;
                }
                // Display slot -> original within-group index. The reader and
                // the history keys are built from that index, so hiding must
                // never renumber it.
                var i = visible[slot];
                var key = group.keys.elementAt(i);
                var value = group[key]!;
                var chapterIndex = _groupOffset + i;
                String rawIndex = (chapterIndex + 1).toString();
                String groupedIndex = "${index + 1}-${i + 1}";
                bool visited = false;
                if (_history != null) {
                  visited =
                      _history!.readEpisode.contains(groupedIndex) ||
                      _history!.readEpisode.contains(rawIndex);
                }
                bool isSelected = selected.contains(groupedIndex);
                return Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
                  child: Material(
                    color: isSelected
                        ? context.colorScheme.primaryContainer
                        : context.colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      onTap: () => selectMode
                          ? toggleSelect(groupedIndex)
                          : state.read(chapterIndex + 1),
                      onLongPress: selectMode
                          ? null
                          : () {
                              enterSelectMode();
                              toggleSelect(groupedIndex);
                            },
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Center(
                          child: Text(
                            value,
                            maxLines: 1,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isSelected
                                  ? context.colorScheme.onPrimaryContainer
                                  : visited
                                  ? context.colorScheme.outline
                                  : null,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
              gridDelegate: const SliverGridDelegateWithFixedHeight(
                maxCrossAxisExtent: 220,
                itemHeight: 44,
              ),
            ).sliverPadding(EdgeInsets.zero),
            if (!canShowAll)
              SliverToBoxAdapter(
                child: Align(
                  alignment: Alignment.center,
                  child: TextButton.icon(
                    icon: const Icon(Icons.arrow_drop_down),
                    onPressed: () {
                      setState(() {
                        showAll = true;
                      });
                    },
                    label: Text("${"Show all".tl} (${visible.length})"),
                  ).paddingTop(12),
                ),
              ),
            const SliverPadding(padding: EdgeInsets.only(bottom: 12)),
          ],
        );
      },
    );
  }
}

/// "Updating" text + spinner next to the "Chapters" title while the background
/// details fetch refreshes a chapter list that is already on screen.
class _ChaptersUpdatingIndicator extends StatelessWidget {
  const _ChaptersUpdatingIndicator();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(
            strokeWidth: 1.6,
            color: context.colorScheme.outline,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          "Updating".tl,
          style: ts.s12.withColor(context.colorScheme.outline),
        ),
      ],
    );
  }
}

/// 章節封面圖：優先用源提供的封面 / 縮圖；都沒有就惰性地向源要
/// 該話的第一頁當封面（解決非栗子源沒有 chapterCovers 時整片灰格）。
/// 只有格子可見時才會觸發（SliverGrid 惰性構建），結果在記憶體快取，
/// 同一話不重複請求；失敗則維持序號佔位。
class _LazyChapterCover extends StatefulWidget {
  const _LazyChapterCover({
    required this.coverUrl,
    required this.placeholderIndex,
    required this.sourceKey,
    required this.comicId,
    required this.epId,
  });

  final String? coverUrl;
  final int placeholderIndex;
  final String sourceKey;
  final String comicId;
  final String epId;

  @override
  State<_LazyChapterCover> createState() => _LazyChapterCoverState();
}

class _LazyChapterCoverState extends State<_LazyChapterCover> {
  /// 'sourceKey:comicId:epId' -> 第一頁圖片 URL（null = 已試過但沒有）
  static final Map<String, String?> _lazyCache = {};

  String? _url;

  @override
  void initState() {
    super.initState();
    _url =
        (widget.coverUrl != null && widget.coverUrl!.isNotEmpty)
            ? widget.coverUrl
            : null;
    if (_url == null) _lazyLoad();
  }

  Future<void> _lazyLoad() async {
    final cacheKey = '${widget.sourceKey}:${widget.comicId}:${widget.epId}';
    if (_lazyCache.containsKey(cacheKey)) {
      final v = _lazyCache[cacheKey];
      if (v != null && mounted) setState(() => _url = v);
      return;
    }
    try {
      final source = ComicSource.find(widget.sourceKey);
      final loader = source?.loadComicPages;
      if (loader == null) {
        _lazyCache[cacheKey] = null;
        return;
      }
      final res = await loader(widget.comicId, widget.epId);
      final first =
          (res.success && res.data.isNotEmpty) ? res.data.first : null;
      _lazyCache[cacheKey] = first;
      if (first != null && mounted) setState(() => _url = first);
    } catch (_) {
      _lazyCache[cacheKey] = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = _url;
    if (url == null || url.isEmpty) {
      return Container(
        color: context.colorScheme.surfaceContainerHighest,
        child: Center(
          child: Text(
            "${widget.placeholderIndex}",
            style: TextStyle(color: context.colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }
    return Image(
      image: CachedImageProvider(
        url,
        sourceKey: widget.sourceKey,
        cid: widget.comicId,
      ),
      fit: BoxFit.cover,
      errorBuilder: (c, e, st) => Container(
        color: context.colorScheme.surfaceContainerHighest,
        child: Icon(
          Icons.broken_image_outlined,
          color: context.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
