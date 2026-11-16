part of 'components.dart';

/// Collections whose cover warm-up has already been kicked off, so a list of
/// tiles rebuilding repeatedly fires one load per collection rather than one per
/// build. Not cleared: a successful warm-up writes a cover, and a failing one
/// would keep failing for the same reason.
final _warmingCollectionCovers = <String>{};

/// Marker colour for "already in a collection". Distinct from the favourite
/// (green), read-later (orange) and history (blue) badges so four states stay
/// tellable apart on one cover.
const _kCollectionStatusColor = Color(0xFF7E57C2);

/// Corner marker saying this comic already sits in at least one collection, so a
/// long list needn't be opened item by item to avoid filing something twice.
///
/// Watches the store instead of taking a flag captured at build time: filing a
/// comic from the very list showing it has to light up its marker with no
/// reload. Renders nothing when the comic is in no collection, so callers can
/// place it unconditionally.
class CollectionMemberMarker extends StatelessWidget {
  const CollectionMemberMarker({
    super.key,
    required this.sourceKey,
    required this.comicId,
    this.size = 13,
    this.padding = 3,
  });

  final String sourceKey;

  final String comicId;

  final double size;

  final double padding;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ComicCollectionStore.changes,
      builder: (context, _) {
        if (!ComicCollectionStore.isMember(sourceKey, comicId)) {
          return const SizedBox.shrink();
        }
        return Container(
          padding: EdgeInsets.all(padding),
          decoration: BoxDecoration(
            color: _kCollectionStatusColor.toOpacity(0.9),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            Icons.library_add_check_rounded,
            size: size,
            color: Colors.white,
          ),
        );
      },
    );
  }
}

/// Loads a collection's members once so their titles and covers land in the
/// store, then rebuilds the tiles that are waiting on it.
void _warmCollectionCover(String collectionId) {
  if (!_warmingCollectionCovers.add(collectionId)) return;
  Future.microtask(() async {
    final source = ComicSource.find(
      ComicCollectionStore.find(collectionId)?.sourceKey ?? '',
    );
    if (source?.loadComicInfo == null) return;
    try {
      // Going through the source rather than calling the loader directly keeps
      // this file free of a dependency on the collection source internals; the
      // load writes the member caches as a side effect, which is the point.
      await source!.loadComicInfo!(collectionId);
    } catch (e) {
      Log.error('ComicCollection', 'Cover warm-up failed: $e');
    }
    // cacheMemberInfo already pinged listeners if anything changed; nothing to
    // do here when the load found no new cover.
  });
}

/// Picks the loader for a comic's cover. Exposed for tests.
ImageProvider? findImageProvider(Comic comic) {
  ImageProvider image;
  // A collection's cover is resolved from the store, not from the passed-in
  // comic: a favourite or history row froze whatever the cover was when it was
  // recorded, which is empty when the collection was favourited before its
  // members had ever loaded. The store always holds the current one.
  if (ComicCollectionStore.isCollectionSourceKey(comic.sourceKey)) {
    final collection = ComicCollectionStore.find(comic.id);
    final cover = collection?.displayCover ?? comic.cover;
    if (cover.isEmpty) {
      // Nothing cached yet, which happens when a collection is favourited
      // before it has ever been opened. Warming it fills the member caches (and
      // so the cover) for the next build.
      if (collection != null && collection.members.isNotEmpty) {
        _warmCollectionCover(collection.id);
      }
      return null;
    }
    // The cover belongs to a member, so image loading has to go through the
    // collection's source to pick up that member's auth headers.
    return CachedImageProvider(
      cover,
      sourceKey: comic.sourceKey,
      cid: comic.id,
    );
  }
  if (comic is LocalComic) {
    // A queued download task merged into the grid has no directory on disk yet,
    // so its `cover` holds the remote url carried over from the list that
    // started it (see ImagesDownloadTask.toLocalComic) rather than a file name.
    if (comic.directory.isEmpty && comic.cover.isNotEmpty) {
      image = CachedImageProvider(
        comic.cover,
        sourceKey: comic.sourceKey,
        cid: comic.id,
      );
    } else {
      image = LocalComicImageProvider(comic);
    }
  } else if (comic is History) {
    image = HistoryImageProvider(comic);
  } else if (comic.sourceKey == 'local') {
    var localComic = LocalManager().find(comic.id, ComicType.local);
    if (localComic == null) {
      return null;
    }
    image = LocalComicImageProvider(localComic);
  } else {
    // Only this branch cannot recover from an empty cover: the downloader has
    // no url to fetch. Every branch above self-heals (local dir scan, history
    // re-fetch), so the check must not be hoisted out of here.
    final fallbackToLocalCover = comic is FavoriteItem;
    if (comic.cover.isEmpty && !fallbackToLocalCover) {
      return null;
    }
    image = CachedImageProvider(
      comic.cover,
      sourceKey: comic.sourceKey,
      cid: comic.id,
      fallbackToLocalCover: fallbackToLocalCover,
    );
  }
  return image;
}

class ComicTile extends StatelessWidget {
  const ComicTile({
    super.key,
    required this.comic,
    this.enableLongPressed = true,
    this.enableContextMenu = true,
    this.badge,
    this.menuOptions,
    this.onTap,
    this.onLongPressed,
    this.heroID,
  });

  final Comic comic;

  final bool enableLongPressed;

  final bool enableContextMenu;

  final String? badge;

  final List<MenuEntry>? menuOptions;

  final VoidCallback? onTap;

  final VoidCallback? onLongPressed;

  final int? heroID;

  static final _chapterProgressLoads =
      <String, Future<ComicChapterProgressInfo>>{};

  /// Badge text for the tile. A collection gets its own label instead of a
  /// source name (its members may come from several sources), so it is
  /// recognisable in a list without opening it. An explicit [badge] from the
  /// host still wins.
  String? get _effectiveBadge {
    if (badge != null) return badge;
    if (ComicCollectionStore.isCollectionSourceKey(comic.sourceKey)) {
      return 'Collection'.tl;
    }
    return null;
  }

  bool get _isCollection =>
      ComicCollectionStore.isCollectionSourceKey(comic.sourceKey);

  /// Whether this tile should say that the comic is already filed into a
  /// collection. Never for a collection itself — collections cannot nest, so
  /// the two markers share the same corner.
  bool get _showCollectionStatus =>
      !_isCollection && appdata.settings['showCollectionStatusOnTile'] == true;

  /// Whether the tile shows a page count. Never for a collection: its members
  /// each have their own count, so a single number there would be meaningless.
  bool get _showPageCount =>
      !_isCollection && appdata.settings['showPageCountOnTile'] == true;

  /// Corner marker drawn over the cover of a collection, in both display modes:
  /// the text badge only exists in detailed mode, and a cover marker is what
  /// makes a collection recognisable at a glance either way.
  Widget _buildCollectionMarker(BuildContext context, {double size = 13}) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.black.toOpacity(0.55),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(
        Icons.library_books_outlined,
        size: size,
        color: Colors.white,
      ),
    );
  }

  Widget _buildCollectionStatusMarker({double size = 13}) =>
      CollectionMemberMarker(
        sourceKey: comic.sourceKey,
        comicId: comic.id,
        size: size,
      );

  void _onTap() {
    if (onTap != null) {
      onTap!();
      return;
    }
    App.mainNavigatorKey?.currentContext?.to(
      () => ComicPage(
        id: comic.id,
        sourceKey: comic.sourceKey,
        cover: comic.cover,
        title: comic.title,
        heroID: heroID,
      ),
    );
  }

  void _onLongPressed(context) {
    if (onLongPressed != null) {
      onLongPressed!();
      return;
    }
    onLongPress(context);
  }

  void onLongPress(BuildContext context) {
    var renderBox = context.findRenderObject() as RenderBox;
    var size = renderBox.size;
    var location = renderBox.localToGlobal(
      Offset((size.width - 242) / 2, size.height / 2),
    );
    showMenu(location, context);
  }

  void onSecondaryTap(TapDownDetails details, BuildContext context) {
    showMenu(details.globalPosition, context);
  }

  void showMenu(Offset location, BuildContext context) {
    if (!enableContextMenu) return;
    final type = ComicType.fromKey(comic.sourceKey);
    final source = ComicSource.find(comic.sourceKey);
    final history = HistoryManager().find(comic.id, type);
    final isFavorite = LocalFavoritesManager().isExist(comic.id, type);
    final isReadLater = ReadLaterManager().isExist(comic.id, type);
    final progress = history == null
        ? null
        : 'Chapter @chapter · Page @page'.tlParams({
            'chapter': math.max(1, history.ep),
            'page': math.max(1, history.page),
          });
    final navigatorContext = App.mainNavigatorKey?.currentContext ?? context;
    final local = const ComicStateRepository()
        .load(comic.sourceKey, comic.id)
        .localComic;
    final downloaded = local != null;
    showMenuX(
      context,
      location,
      [
        if (source?.loadComicInfo != null || local != null || _isCollection)
          MenuEntry(
            action: MenuAction.read,
            role: MenuEntryRole.primary,
            icon: Icons.menu_book_outlined,
            text: history == null ? 'Read'.tl : 'Continue reading'.tl,
            subtitle: progress,
            onClick: () {
              if (local != null) {
                local.read();
              } else {
                navigatorContext.to(
                  () => ReaderWithLoading(
                    id: comic.id,
                    sourceKey: comic.sourceKey,
                  ),
                );
              }
            },
          ),
        MenuEntry(
          action: MenuAction.details,
          icon: Icons.chrome_reader_mode_outlined,
          text: 'Details'.tl,
          onClick: () {
            navigatorContext.to(
              () => ComicPage(
                id: comic.id,
                sourceKey: comic.sourceKey,
                cover: comic.cover,
                title: comic.title,
              ),
            );
          },
        ),
        MenuEntry(
          group: MenuGroup.more,
          icon: Icons.copy,
          text: 'Copy Title'.tl,
          onClick: () {
            Clipboard.setData(ClipboardData(text: comic.title));
            App.rootContext.showMessage(message: 'Title copied'.tl);
          },
        ),
        MenuEntry(
          action: MenuAction.favorite,
          group: MenuGroup.organize,
          role: MenuEntryRole.quick,
          isSelected: isFavorite,
          icon: isFavorite ? Icons.favorite : Icons.favorite_border,
          text: isFavorite ? 'Add to another folder'.tl : 'Add to favorites'.tl,
          compactText: isFavorite ? 'Favorited'.tl : 'Add to favorites'.tl,
          onClick: () {
            addFavorite([comic]);
          },
        ),
        // A collection cannot hold another collection, so the entry is hidden
        // rather than shown and refused.
        if (!ComicCollectionStore.isCollectionSourceKey(comic.sourceKey))
          MenuEntry(
            action: MenuAction.collection,
            group: MenuGroup.organize,
            icon: Icons.library_books_outlined,
            text: 'Add to collection'.tl,
            onClick: () => showAddToCollectionDialog(context, [comic]),
          ),
        MenuEntry(
          action: MenuAction.readLater,
          group: MenuGroup.organize,
          role: MenuEntryRole.quick,
          isSelected: isReadLater,
          icon: isReadLater
              ? Icons.bookmark_remove_outlined
              : Icons.watch_later_outlined,
          text: isReadLater ? 'Remove from read later'.tl : 'Read later'.tl,
          compactText: isReadLater ? 'In read later'.tl : 'Read later'.tl,
          onClick: () async {
            final added = await ReadLaterManager().toggle(comic);
            App.rootContext.showMessage(
              message: added
                  ? 'Added to read later'.tl
                  : 'Removed from read later'.tl,
            );
          },
        ),
        if (source != null && source.loadComicInfo != null)
          MenuEntry(
            action: MenuAction.download,
            role: MenuEntryRole.quick,
            icon: downloaded ? Icons.download_done : Icons.download_outlined,
            text: downloaded ? 'Downloaded'.tl : 'Download'.tl,
            isSelected: downloaded,
            onClick: () async {
              if (LocalManager().isDownloading(comic.id, type)) {
                App.rootContext.showMessage(
                  message: 'The comic is downloading'.tl,
                );
                return;
              }
              if (LocalManager().isDownloaded(comic.id, type)) {
                App.rootContext.showMessage(
                  message: 'The comic is downloaded'.tl,
                );
                return;
              }
              if (!await ensureDownloadStorageWritable()) return;
              LocalManager().addTask(
                ImagesDownloadTask(
                  source: source,
                  comicId: comic.id,
                  comicTitle: comic.title,
                  comicCover: comic.cover,
                ),
              );
              App.rootContext.showMessage(message: 'Download started'.tl);
            },
          ),
        // Cross-source linking and migration are meaningless for a collection: it
        // has no upstream source, and "migrating" it would search other sources
        // for its name and rebind it, silently discarding the grouping. Members
        // are still individually migratable from their own tiles.
        if (!_isCollection)
          MenuEntry(
            group: MenuGroup.source,
            icon: Icons.hub_outlined,
            text: 'Linked entries'.tl,
            onClick: () => showRelatedSourcesDialog(context, comic),
          ),
        if (!_isCollection)
          MenuEntry(
            action: MenuAction.migrate,
            group: MenuGroup.source,
            icon: Icons.move_up_outlined,
            text: 'Migrate Source'.tl,
            onClick: () => showSourceMigrationDialog(
              context,
              favoriteItemFromComic(comic),
            ),
          ),
        MenuEntry(
          group: MenuGroup.more,
          icon: Icons.block,
          text: 'Block'.tl,
          onClick: () => block(context),
        ),
        ...?menuOptions,
      ],
      title: comic.title,
      subtitle:
          source?.name ?? (comic.sourceKey == 'local' ? 'Local'.tl : null),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: ColoredBox(
          color: context.colorScheme.surfaceContainerHigh,
          child: buildImage(context),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    var type = appdata.settings['comicDisplayMode'];

    final comicType = ComicType.fromKey(comic.sourceKey);
    var isFavorite = appdata.settings['showFavoriteStatusOnTile']
        ? LocalFavoritesManager().isExist(comic.id, comicType)
        : false;
    var isReadLater = appdata.settings['showReadLaterStatusOnTile']
        ? ReadLaterManager().isExist(comic.id, comicType)
        : false;
    final showHistoryOnTile = appdata.settings['showHistoryStatusOnTile'];
    final history = showHistoryOnTile || type == 'detailed'
        ? HistoryManager().find(comic.id, comicType)
        : null;
    final tileHistory = showHistoryOnTile ? history : null;
    final chapterProgress = const ComicStateRepository().chapterProgressFor(
      comic,
      history,
    );
    if (tileHistory?.page == 0) {
      tileHistory!.page = 1;
    }

    Widget child = type == 'detailed'
        ? _buildDetailedMode(context, history, tileHistory, chapterProgress)
        : _buildBriefMode(context, tileHistory, chapterProgress);

    if (!isFavorite && !isReadLater && tileHistory == null) {
      return child;
    }

    return Stack(
      children: [
        Positioned.fill(child: child),
        Positioned(
          left: type == 'detailed' ? 16 : 6,
          top: 8,
          child: Container(
            height: 24,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(4)),
            clipBehavior: Clip.antiAlias,
            child: Row(
              children: [
                if (isFavorite)
                  Container(
                    height: 24,
                    width: 24,
                    color: Colors.green,
                    child: const Icon(
                      Icons.bookmark_rounded,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                if (isReadLater)
                  Container(
                    height: 24,
                    width: 24,
                    color: Colors.orange,
                    child: const Icon(
                      Icons.watch_later_rounded,
                      size: 15,
                      color: Colors.white,
                    ),
                  ),
                if (tileHistory != null)
                  Container(
                    height: 24,
                    color: Colors.blue.toOpacity(0.9),
                    constraints: const BoxConstraints(minWidth: 24),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: CustomPaint(
                      painter: _ReadingHistoryPainter(
                        tileHistory.page,
                        tileHistory.maxPage,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _menuButton(BuildContext context) {
    return IconButton(
      tooltip: 'Actions'.tl,
      icon: const Icon(Icons.more_horiz),
      iconSize: 20,
      onPressed: () => onLongPress(context),
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
    );
  }

  Widget _buildEpisodeBadge(
    BuildContext context,
    ComicChapterProgressInfo chapterProgress,
    double maxWidth,
    History? history,
  ) {
    final syncBadge = _buildEpisodeBadgeContent(
      context,
      chapterProgress,
      maxWidth,
    );
    if (history == null ||
        comic.sourceKey == 'local' ||
        (chapterProgress.currentTitle != null &&
            chapterProgress.latestTitle != null) ||
        ComicSource.find(comic.sourceKey)?.loadComicInfo == null) {
      return syncBadge;
    }
    return FutureBuilder(
      future: _loadChapterProgress(chapterProgress, history),
      builder: (context, snapshot) {
        final asyncProgress = snapshot.data;
        if (asyncProgress == null || !asyncProgress.hasAny) {
          return syncBadge;
        }
        return _buildEpisodeBadgeContent(context, asyncProgress, maxWidth);
      },
    );
  }

  Future<ComicChapterProgressInfo> _loadChapterProgress(
    ComicChapterProgressInfo initialProgress,
    History history,
  ) {
    final key = [
      comic.sourceKey,
      comic.id,
      history.group ?? 0,
      history.ep,
      history.time.millisecondsSinceEpoch,
    ].join('\u0001');
    final cached = _chapterProgressLoads[key];
    if (cached != null) {
      return cached;
    }
    final future = _fetchChapterProgress(initialProgress, history);
    _chapterProgressLoads[key] = future;
    if (_chapterProgressLoads.length > 96) {
      _chapterProgressLoads.remove(_chapterProgressLoads.keys.first);
    }
    return future;
  }

  Future<ComicChapterProgressInfo> _fetchChapterProgress(
    ComicChapterProgressInfo initialProgress,
    History history,
  ) async {
    final source = ComicSource.find(comic.sourceKey);
    final loadComicInfo = source?.loadComicInfo;
    if (loadComicInfo == null) {
      return initialProgress;
    }
    try {
      final res = await loadComicInfo(comic.id);
      final details = res.dataOrNull;
      if (details == null) {
        return initialProgress;
      }
      const repository = ComicStateRepository();
      repository.mirrorComicDetails(details);
      final progress = repository.chapterProgressFromDetails(details, history);
      return progress.hasAny ? progress : initialProgress;
    } catch (e, s) {
      Log.error('Comic tile chapter progress', e, s);
      return initialProgress;
    }
  }

  Widget _buildEpisodeBadgeContent(
    BuildContext context,
    ComicChapterProgressInfo chapterProgress,
    double maxWidth,
  ) {
    if (!chapterProgress.hasAny) {
      return const SizedBox();
    }
    final fontSize = maxWidth < 80
        ? 8.0
        : maxWidth < 150
        ? 10.0
        : 12.0;
    final lines = [
      if (chapterProgress.currentTitle != null)
        '${'Current'.tl}: ${chapterProgress.currentTitle}',
      if (chapterProgress.latestTitle != null)
        '${'Latest'.tl}: ${chapterProgress.latestTitle}',
    ];
    return Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      margin: const EdgeInsets.fromLTRB(2, 0, 2, 2),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.blue.toOpacity(0.72),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in lines)
            Text(
              line,
              style: TextStyle(
                color: Colors.white,
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }

  Widget buildImage(BuildContext context) {
    // A collection's cover comes from the store, which fills in asynchronously
    // the first time its members load. Listening here is what turns a blank
    // cover into the real one without the user leaving the page.
    if (_isCollection) {
      return ListenableBuilder(
        listenable: ComicCollectionStore.changes,
        builder: (context, _) => _buildImageNow(context),
      );
    }
    return _buildImageNow(context);
  }

  Widget _buildImageNow(BuildContext context) {
    var image = findImageProvider(comic);
    if (image == null) {
      return const SizedBox();
    }
    return AnimatedImage(
      image: image,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
    );
  }

  Widget _buildDetailedMode(
    BuildContext context,
    History? history,
    History? tileHistory,
    ComicChapterProgressInfo chapterProgress,
  ) {
    return LayoutBuilder(
      builder: (context, constrains) {
        final height = math.max(0.0, constrains.maxHeight - 28);
        final coverWidth = height * 0.68;
        final displayInfo = const ComicStateRepository().displayInfoFor(
          comic,
          badge: _effectiveBadge,
        );

        Widget image = Container(
          width: coverWidth,
          height: double.infinity,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: context.colorScheme.outlineVariant,
                blurRadius: 1,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Positioned.fill(child: buildImage(context)),
              Positioned(
                left: 2,
                bottom: 2,
                child: _buildEpisodeBadge(
                  context,
                  tileHistory == null
                      ? const ComicChapterProgressInfo()
                      : chapterProgress,
                  coverWidth - 4,
                  tileHistory,
                ),
              ),
              // Top-RIGHT: the tile's outer Stack overlays the favourite /
              // read-later / history badges at the top-left, which would cover
              // this marker on exactly the collections most likely to be
              // favourited.
              if (_isCollection)
                Positioned(
                  right: 3,
                  top: 3,
                  child: _buildCollectionMarker(context),
                )
              else if (_showCollectionStatus)
                Positioned(
                  right: 3,
                  top: 3,
                  child: _buildCollectionStatusMarker(),
                ),
            ],
          ),
        );

        if (heroID != null) {
          image = Hero(tag: "cover$heroID", child: image);
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: _onTap,
              onLongPress: enableLongPressed
                  ? () => _onLongPressed(context)
                  : null,
              onSecondaryTapDown: (detail) => onSecondaryTap(detail, context),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 14, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    image,
                    const SizedBox(width: 14),
                    Expanded(
                      child: ComicDescription(
                        title: displayInfo.title.replaceAll("\n", ""),
                        titleTrailing: App.isMobile && enableContextMenu
                            ? _menuButton(context)
                            : null,
                        subtitle: displayInfo.author ?? '',
                        description: displayInfo.description ?? '',
                        badge: displayInfo.sourceName ?? comic.language,
                        tags: displayInfo.tags,
                        maxLines: 2,
                        enableTranslate:
                            ComicSource.find(
                              comic.sourceKey,
                            )?.enableTagsTranslate ??
                            false,
                        rating: displayInfo.rating,
                        updateText: displayInfo.updateTime,
                        statusText: displayInfo.status,
                        progressText: chapterProgress.currentTitle,
                        pagesText: _showPageCount
                            ? displayInfo.pagesText
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBriefMode(
    BuildContext context,
    History? history,
    ComicChapterProgressInfo chapterProgress,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        Widget image = Container(
          decoration: BoxDecoration(
            color: context.colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.toOpacity(0.2),
                blurRadius: 2,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: buildImage(context),
        );

        if (heroID != null) {
          image = Hero(tag: "cover$heroID", child: image);
        }

        return InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: _onTap,
          onLongPress: enableLongPressed ? () => _onLongPressed(context) : null,
          onSecondaryTapDown: (detail) => onSecondaryTap(detail, context),
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(child: image),
                    // Top-right for the same reason as detailed mode: the outer
                    // Stack's status badges own the top-left corner.
                    if (_isCollection)
                      Positioned(
                        right: 4,
                        top: 4,
                        child: _buildCollectionMarker(
                          context,
                          size: constraints.maxWidth < 80 ? 10 : 13,
                        ),
                      )
                    else if (_showCollectionStatus)
                      Positioned(
                        right: 4,
                        top: 4,
                        child: _buildCollectionStatusMarker(
                          size: constraints.maxWidth < 80 ? 10 : 13,
                        ),
                      ),
                    Align(
                      alignment: Alignment.bottomRight,
                      child: (() {
                        final subtitle = comic.subtitle
                            ?.replaceAll('\n', '')
                            .trim();
                        final text = comic.description.isNotEmpty
                            ? comic.description.split('|').join('\n')
                            : (subtitle?.isNotEmpty == true ? subtitle : null);
                        final fortSize = constraints.maxWidth < 80
                            ? 8.0
                            : constraints.maxWidth < 150
                            ? 10.0
                            : 12.0;

                        var lines = text == null
                            ? <String>[]
                            : text.split('\n');
                        lines.removeWhere((e) => e.trim().isEmpty);
                        if (lines.length > 3) {
                          lines = lines.sublist(0, 3);
                        }
                        final pageCount = _showPageCount
                            ? const ComicStateRepository().quickPageCountFor(
                                comic,
                              )
                            : null;
                        // Prepended after the description was already trimmed to
                        // its 3 lines, so the count adds a line instead of
                        // costing one. Sources that already spell the count into
                        // the description would otherwise say it twice.
                        if (pageCount != null &&
                            !lines.any((e) => e.containsNumber(pageCount))) {
                          lines.insert(0, '${pageCount}P');
                        }

                        if (lines.isEmpty) {
                          return const SizedBox();
                        }

                        var children = <Widget>[];
                        for (var line in lines) {
                          children.add(
                            Container(
                              margin: const EdgeInsets.fromLTRB(2, 0, 2, 2),
                              padding: constraints.maxWidth < 80
                                  ? const EdgeInsets.fromLTRB(3, 1, 3, 1)
                                  : constraints.maxWidth < 150
                                  ? const EdgeInsets.fromLTRB(4, 2, 4, 2)
                                  : const EdgeInsets.fromLTRB(5, 2, 5, 2),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                color: Colors.black.toOpacity(0.5),
                              ),
                              constraints: BoxConstraints(
                                maxWidth: constraints.maxWidth,
                              ),
                              child: Text(
                                line,
                                style: TextStyle(
                                  fontWeight: FontWeight.w500,
                                  fontSize: fortSize,
                                  color: Colors.white,
                                ),
                                textAlign: TextAlign.right,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          );
                        }
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: children,
                        );
                      })(),
                    ),
                    Positioned(
                      left: 2,
                      bottom: 2,
                      child: _buildEpisodeBadge(
                        context,
                        history == null
                            ? const ComicChapterProgressInfo()
                            : chapterProgress,
                        constraints.maxWidth * 0.72,
                        history,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                child: Text(
                  comic.title.replaceAll('\n', ''),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ).paddingHorizontal(6).paddingVertical(8),
        );
      },
    );
  }

  void block(BuildContext comicTileContext) {
    // A list item usually carries only a title and a cover — most sources fill
    // in tags on the detail request. Pull whatever tags the app already knows
    // (favorites / local library / mirrored details) so the picker isn't
    // limited to title fragments; without this, blocking by tag was impossible
    // from a search result.
    var knownTags = const ComicStateRepository().displayInfoFor(comic).tags;
    showBlockDialog(
      title: comic.title,
      subtitle: comic.subtitle,
      tags: knownTags.isEmpty ? (comic.tags ?? const []) : knownTags,
      onBlocked: () {
        comicTileContext
            .findAncestorStateOfType<_SliverGridComicsState>()
            ?.update();
      },
    );
  }
}

/// Splits a comic title into the fragments offered as keyword choices, cutting
/// on commas and bracketed groups.
List<String> _splitText(String text) {
  var words = <String>[];
  var buffer = StringBuffer();
  var inBracket = false;
  String? prevBracket;
  for (var i = 0; i < text.length; i++) {
    var c = text[i];
    if (c == '[' || c == '(') {
      if (inBracket) {
        buffer.write(c);
      } else {
        if (buffer.isNotEmpty) {
          words.add(buffer.toString().trim());
          buffer.clear();
        }
        inBracket = true;
        prevBracket = c;
      }
    } else if (c == ']' || c == ')') {
      if (prevBracket == '[' && c == ']' || prevBracket == '(' && c == ')') {
        if (buffer.isNotEmpty) {
          words.add(buffer.toString().trim());
          buffer.clear();
        }
        inBracket = false;
      } else {
        buffer.write(c);
      }
    } else if (c == ',') {
      if (inBracket) {
        buffer.write(c);
      } else {
        words.add(buffer.toString().trim());
        buffer.clear();
      }
    } else {
      buffer.write(c);
    }
  }
  if (buffer.isNotEmpty) {
    words.add(buffer.toString().trim());
  }
  words.removeWhere((element) => element == "");
  return words.toSet().toList();
}

/// Lets the user turn a comic's own words and tags into blocklist entries.
///
/// Title fragments go to the keyword list (substring-matched against
/// title/subtitle/description) and tags go to the tag list, so a tag pick can
/// never accidentally hide comics whose *title* happens to contain that word.
/// Shared by the list long-press menu and the comic detail page, where the full
/// tag set is always available.
void showBlockDialog({
  required String title,
  String? subtitle,
  required List<String> tags,
  VoidCallback? onBlocked,
}) {
  var words = [
    ..._splitText(title),
    if (subtitle != null && subtitle.isNotEmpty) subtitle,
  ];
  var selectedWords = <String>[];
  var selectedTags = <String>[];
  showDialog(
    context: App.rootContext,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          Widget section(
            String title,
            List<String> items,
            List<String> picked, {
            bool translate = false,
          }) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: ts.s12.bold),
                const SizedBox(height: 8),
                Wrap(
                  runSpacing: 8,
                  spacing: 8,
                  children: [
                    for (var item in items)
                      OptionChip(
                        // Only tags have translations; a title fragment must be
                        // shown as-is. Picking a tag stores its value half (the
                        // part after the namespace), so the entry also matches
                        // comics that carry the tag without a namespace.
                        text: translate
                            ? item
                                .split(':')
                                .last
                                .translateTagIfNeed
                            : item,
                        isSelected: picked.contains(item),
                        onTap: () {
                          setState(() {
                            if (!picked.remove(item)) {
                              picked.add(item);
                            }
                          });
                        },
                      ),
                  ],
                ),
              ],
            );
          }

          return ContentDialog(
            title: 'Block'.tl,
            content: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: math.min(400, context.height - 136),
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (words.isNotEmpty)
                      section('Keyword'.tl, words, selectedWords),
                    if (words.isNotEmpty && tags.isNotEmpty)
                      const SizedBox(height: 16),
                    if (tags.isNotEmpty)
                      section('Tags'.tl, tags, selectedTags, translate: true),
                    if (words.isEmpty && tags.isEmpty)
                      Text('No tags available'.tl),
                  ],
                ),
              ).paddingHorizontal(16),
            ),
            actions: [
              Button.filled(
                onPressed: () {
                  context.pop();
                  if (selectedWords.isEmpty && selectedTags.isEmpty) {
                    return;
                  }
                  for (var word in selectedWords) {
                    if (!appdata.settings['blockedWords'].contains(word)) {
                      appdata.settings['blockedWords'].add(word);
                    }
                  }
                  for (var tag in selectedTags) {
                    // Store the value half: detail pages hand over
                    // `namespace:value` tags, but list items often carry the
                    // bare value, and the entry has to match both.
                    var entry = tag.contains(':')
                        ? tag.split(':').sublist(1).join(':')
                        : tag;
                    if (entry.isEmpty) continue;
                    if (!appdata.settings['blockedTags'].contains(entry)) {
                      appdata.settings['blockedTags'].add(entry);
                    }
                  }
                  appdata.saveData();
                  App.rootContext.showMessage(message: 'Blocked'.tl);
                  onBlocked?.call();
                },
                child: Text('Block'.tl),
              ),
            ],
          );
        },
      );
    },
  );
}

class ComicDescription extends StatelessWidget {
  const ComicDescription({
    super.key,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.enableTranslate,
    this.badge,
    this.maxLines = 2,
    this.tags,
    this.rating,
    this.updateText,
    this.statusText,
    this.progressText,
    this.pagesText,
    this.chaptersText,
    this.lastReadTimeText,
    this.showTitle = true,
    this.showDescription = true,
    this.onTapAuthor,
    this.onTapTag,
    this.enableLongPressCopy = false,
  });

  final String title;
  final String subtitle;
  final String description;
  final String? badge;
  final List<String>? tags;
  final int maxLines;
  final bool enableTranslate;
  final double? rating;
  final String? updateText;
  final String? statusText;
  final String? progressText;
  final String? pagesText;
  final String? chaptersText;
  final String? lastReadTimeText;
  final bool showTitle;
  final bool showDescription;
  final void Function(String author, String? namespace)? onTapAuthor;
  final void Function(String tag, String namespace)? onTapTag;

  /// Whether long-pressing an info/tag value copies it to the clipboard.
  /// Enabled on the comic detail page; disabled on list tiles so a long press
  /// over the tag area triggers the tile's own context menu instead (issue #79).
  final bool enableLongPressCopy;

  @override
  Widget build(BuildContext context) {
    final descriptionParts = _descriptionParts();
    final source = _clean(badge) ?? _derivedSource(descriptionParts);
    final update = _clean(updateText) ?? _updateTextFromTags();
    final progress = _clean(progressText);
    final authorItems = _authorItems();
    final authors = authorItems.isEmpty
        ? null
        : authorItems.map((e) => e.label).join(", ");
    final tagItems = _tagItems();
    final tagText = _tagText(tagItems);
    final status = _clean(statusText) ?? _statusText();
    final pages = _clean(pagesText) ?? _pagesText();
    final fallbackDescription = _fallbackDescription(
      update,
      progress,
      source,
      descriptionParts,
    );
    final rows = <Widget>[
      if (authors != null && onTapAuthor != null)
        _actionRow(
          context,
          "Authors".tl,
          authorItems
              .map(
                (item) => _InfoAction(
                  text: item.label,
                  onTap: () => onTapAuthor!(item.value, item.namespace),
                ),
              )
              .toList(),
          Colors.lightBlue,
        )
      else if (authors != null)
        _infoRow(context, "Authors".tl, authors, Colors.lightBlue),
      // 頁數排在更新/來源前：高度預算只留前幾行，頁數是讀者最常篩的
      if (pages != null) _infoRow(context, "Pages".tl, pages, Colors.teal),
      if (update != null) _infoRow(context, "Update".tl, update, Colors.cyan),
      if (chaptersText != null)
        _infoRow(context, '話數', chaptersText!, Colors.amber),
      if (lastReadTimeText != null)
        _infoRow(context, '上次閱讀', lastReadTimeText!, Colors.deepPurple),
      if (source != null) _infoRow(context, "Source".tl, source, Colors.cyan),
      if (tagItems.isNotEmpty && onTapTag != null)
        _actionRow(
          context,
          "Tags".tl,
          tagItems
              .map(
                (item) => _InfoAction(
                  text: item.label,
                  onTap: () => onTapTag!(item.value, item.namespace ?? ''),
                ),
              )
              .toList(),
          Colors.pinkAccent,
        )
      else if (tagText != null)
        _infoRow(context, "Tags".tl, tagText, Colors.pinkAccent),
      if (status != null) _infoRow(context, "Status".tl, status, Colors.purple),
      if (progress != null)
        _infoRow(context, "Progress".tl, progress, Colors.green),
      if (showDescription && fallbackDescription != null)
        _infoRow(context, "Description".tl, fallbackDescription, Colors.orange),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final visibleRows = _visibleRowCount(
          constraints.maxHeight,
          rating != null,
        );
        return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.start,
          children: [
            if (showTitle) ...[
              Text(
                title.trim(),
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
                maxLines: rows.isEmpty ? maxLines : 1,
                overflow: TextOverflow.ellipsis,
                softWrap: true,
              ),
              const SizedBox(height: 4),
            ],
            if (rating != null) ...[
              StarRating(value: rating!, size: 15),
              const SizedBox(height: 2),
            ],
            if (rows.isNotEmpty)
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: rows.take(visibleRows).toList(),
              ),
          ],
        );
      },
    );
  }

  int _visibleRowCount(double maxHeight, bool hasRating) {
    if (maxHeight.isInfinite) {
      return hasRating ? 4 : 5;
    }
    final reservedHeight = (showTitle ? 24 : 0) + (hasRating ? 20 : 0);
    final count = ((maxHeight - reservedHeight) / 21).floor();
    return math.max(1, math.min(5, count));
  }

  void _copy(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    context.showMessage(message: "Copied".tl);
  }

  Widget _infoRow(
    BuildContext context,
    String label,
    String value,
    Color color,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            height: 18,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: color.toOpacity(0.18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: context.colorScheme.onSurface,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: () {
              final valueText = Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: context.colorScheme.onSurfaceVariant,
                ),
              );
              if (!enableLongPressCopy) {
                return valueText;
              }
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onLongPress: () => _copy(context, value),
                child: valueText,
              );
            }(),
          ),
        ],
      ),
    );
  }

  Widget _actionRow(
    BuildContext context,
    String label,
    List<_InfoAction> actions,
    Color color,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 18,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: color.toOpacity(0.18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: context.colorScheme.onSurface,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Wrap(
              spacing: 0,
              runSpacing: 2,
              children: [
                for (var i = 0; i < actions.length; i++) ...[
                  InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: actions[i].onTap,
                    onLongPress: enableLongPressCopy
                        ? () => _copy(context, actions[i].text)
                        : null,
                    child: Text(
                      actions[i].text,
                      style: TextStyle(
                        fontSize: 12,
                        color: context.colorScheme.primary,
                      ),
                    ).paddingHorizontal(2),
                  ),
                  if (i != actions.length - 1)
                    Text(
                      " / ",
                      style: TextStyle(
                        fontSize: 12,
                        color: context.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String? _clean(String? value) {
    final result = value?.replaceAll("\n", " ").trim();
    return result == null ||
            result.isEmpty ||
            result == "Unknown" ||
            result.startsWith("Unknown:")
        ? null
        : result;
  }

  String? _tagText(List<_DescriptionTag> rawTags) {
    if (rawTags.isEmpty) {
      return null;
    }
    return rawTags.map((tag) => tag.label).join(" / ");
  }

  List<_DescriptionTag> _tagItems() {
    final rawTags = tags
        ?.map((e) => e.replaceAll("\n", " ").trim())
        .where(
          (e) =>
              e.removeAllBlank != "" &&
              !_isMetadataTag(e) &&
              _clean(e.split(':').last) != null,
        )
        .toList();
    if (rawTags == null || rawTags.isEmpty) {
      return const [];
    }
    final enableTranslate =
        App.locale.languageCode == 'zh' && this.enableTranslate;
    return rawTags.map((tag) {
      final index = tag.indexOf(':');
      final namespace = index == -1 ? null : tag.substring(0, index);
      final value = index == -1 ? tag : tag.substring(index + 1);
      return _DescriptionTag(
        namespace: namespace,
        value: value,
        label: enableTranslate
            ? TagsTranslation.translateTag(tag)
            : tag.split(':').last,
      );
    }).toList();
  }

  List<_DescriptionTag> _authorItems() {
    // Only structured author metadata identifies an author. A subtitle can be
    // a status, language or arbitrary description, and commas can be in names.
    return _tagItemsWithNamespace(_authorNamespaces);
  }

  String? _statusText() {
    return _tagsWithNamespace(_statusNamespaces).firstOrNull;
  }

  /// 來自 `pages:` 風格標籤的頁數（有些源不用 Comic.maxPage 回報）
  String? _pagesText() {
    return _tagsWithNamespace(_pagesNamespaces).firstOrNull;
  }

  String? _updateTextFromTags() {
    return _tagsWithNamespace(
      _updateNamespaces,
    ).where(_looksLikeDate).firstOrNull;
  }

  List<String> _tagsWithNamespace(Set<String> namespaces) {
    return _tagItemsWithNamespace(namespaces).map((e) => e.label).toList();
  }

  List<_DescriptionTag> _tagItemsWithNamespace(Set<String> namespaces) {
    return tags
            ?.where((e) => e.contains(':'))
            .map((e) {
              final index = e.indexOf(':');
              final namespace = _normalizeNamespace(e.substring(0, index));
              final rawValue = e.substring(index + 1);
              final value = _authorNamespaces.contains(namespace)
                  ? (rawValue.trim().isEmpty ? null : rawValue)
                  : _clean(rawValue);
              if (value == null || !namespaces.contains(namespace)) {
                return null;
              }
              return _DescriptionTag(
                namespace: e.substring(0, index),
                value: value,
                label: enableTranslate && App.locale.languageCode == 'zh'
                    ? TagsTranslation.translateTag(e)
                    : value,
              );
            })
            .whereType<_DescriptionTag>()
            .toList() ??
        const [];
  }

  bool _isMetadataTag(String tag) {
    if (!tag.contains(':')) {
      final value = _clean(tag);
      return value == null || _looksLikeDate(value) || _looksLikeStatus(value);
    }
    final index = tag.indexOf(':');
    final namespace = _normalizeNamespace(tag.substring(0, index));
    final value = _clean(tag.substring(index + 1));
    return _metadataNamespaces.contains(namespace) ||
        value == null ||
        _looksLikeDate(value) ||
        _looksLikeStatus(value);
  }

  String _normalizeNamespace(String value) {
    return value.trim().toLowerCase().replaceAll(' ', '');
  }

  static const _authorNamespaces = {
    'author',
    'artist',
    'authors',
    'artists',
    'creator',
    '原作',
    '作者',
    '作家',
    '作画',
    '作畫',
    '漫畫',
    '漫画',
    '著者',
    '绘师',
    '繪師',
  };

  static const _statusNamespaces = {
    'status',
    'state',
    'serialization',
    '連載',
    '连载',
    '狀態',
    '状态',
  };

  static const _updateNamespaces = {
    'date',
    'lastupdate',
    'time',
    'update',
    'updated',
    '更新',
    '最後更新',
    '最后更新',
    '時間',
    '时间',
    '日期',
  };

  static const _pagesNamespaces = {'page', 'pages', '頁數', '页数'};

  static const _metadataNamespaces = {
    ..._authorNamespaces,
    ..._statusNamespaces,
    ..._updateNamespaces,
    ..._pagesNamespaces,
    'source',
    'uploader',
    '來源',
    '来源',
    '上傳者',
    '上传者',
  };

  String? _derivedSource(List<String> parts) {
    if (parts.length != 2 || !_looksLikeDate(parts.first)) {
      return null;
    }
    return _clean(parts.last);
  }

  String? _fallbackDescription(
    String? update,
    String? progress,
    String? source,
    List<String> parts,
  ) {
    final value = _clean(description);
    if (value == null || value == update || value == progress) {
      return null;
    }
    if (_isMetadataDescription(parts, source)) {
      return null;
    }
    return value.replaceAll("|", " / ");
  }

  List<String> _descriptionParts() {
    return description
        .split("|")
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  bool _looksLikeDate(String value) {
    return RegExp(r"^\d{4}[-/]\d{1,2}[-/]\d{1,2}").hasMatch(value) ||
        RegExp(r"^\d{4}").hasMatch(value);
  }

  bool _looksLikeStatus(String value) {
    final normalized = value.trim().toLowerCase();
    return const {
      'completed',
      'complete',
      'ongoing',
      'serializing',
      '連載',
      '連載中',
      '连载',
      '连载中',
      '完結',
      '完结',
      '已完結',
      '已完结',
      '休載',
      '休载',
    }.contains(normalized);
  }

  bool _isMetadataDescription(List<String> parts, String? source) {
    if (parts.length != 2 || !_looksLikeDate(parts.first)) {
      return false;
    }
    final descriptionSource = _clean(parts.last);
    return source == null ||
        descriptionSource == null ||
        descriptionSource == source;
  }
}

class _DescriptionTag {
  const _DescriptionTag({
    required this.value,
    required this.label,
    this.namespace,
  });

  final String? namespace;
  final String value;
  final String label;
}

class _InfoAction {
  const _InfoAction({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;
}

class _ReadingHistoryPainter extends CustomPainter {
  final int page;
  final int? maxPage;

  const _ReadingHistoryPainter(this.page, this.maxPage);

  @override
  void paint(Canvas canvas, Size size) {
    if (maxPage == null) {
      // 在中央绘制page
      final textPainter = TextPainter(
        text: TextSpan(
          text: "$page",
          style: TextStyle(fontSize: size.width * 0.8, color: Colors.white),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(
          (size.width - textPainter.width) / 2,
          (size.height - textPainter.height) / 2,
        ),
      );
    } else if (page == maxPage) {
      // 在中央绘制勾
      final paint = Paint()
        ..color = Colors.white
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      canvas.drawLine(
        Offset(size.width * 0.2, size.height * 0.5),
        Offset(size.width * 0.45, size.height * 0.75),
        paint,
      );
      canvas.drawLine(
        Offset(size.width * 0.45, size.height * 0.75),
        Offset(size.width * 0.85, size.height * 0.3),
        paint,
      );
    } else {
      // 在左上角绘制page, 在右下角绘制maxPage
      final textPainter = TextPainter(
        text: TextSpan(
          text: "$page",
          style: TextStyle(fontSize: size.width * 0.8, color: Colors.white),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, const Offset(0, 0));
      final textPainter2 = TextPainter(
        text: TextSpan(
          text: "/$maxPage",
          style: TextStyle(fontSize: size.width * 0.5, color: Colors.white),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter2.layout();
      textPainter2.paint(
        canvas,
        Offset(
          size.width - textPainter2.width,
          size.height - textPainter2.height,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return oldDelegate is! _ReadingHistoryPainter ||
        oldDelegate.page != page ||
        oldDelegate.maxPage != maxPage;
  }
}
