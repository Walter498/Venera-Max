part of 'reader.dart';

bool _shouldBlockComment(Comment comment) {
  var blockedWords = appdata.settings["blockedCommentWords"] as List;
  if (blockedWords.isEmpty) return false;

  var content = comment.content.toLowerCase();
  for (var word in blockedWords) {
    if (content.contains(word.toString().toLowerCase())) {
      return true;
    }
  }
  return false;
}

class ChapterCommentsPage extends StatefulWidget {
  const ChapterCommentsPage({
    super.key,
    required this.comicId,
    required this.epId,
    required this.source,
    required this.comicTitle,
    required this.chapterTitle,
    this.replyComment,
  });

  final String comicId;
  final String epId;
  final ComicSource source;
  final String comicTitle;
  final String chapterTitle;
  final Comment? replyComment;

  @override
  State<ChapterCommentsPage> createState() => _ChapterCommentsPageState();
}

class _ChapterCommentsPageState extends State<ChapterCommentsPage> {
  late CommentsController feed;
  final controller = TextEditingController();
  bool sending = false;
  late String _scopeRevision;
  void _createFeed() {
    _scopeRevision = widget.source.commentScopeRevision;
    feed = CommentsController(loader: (page, sort) async {
      final revision = _scopeRevision;
      final result = await widget.source.loadCommentPage(widget.comicId, widget.epId, page, widget.replyComment?.id, chapter: true, sort: sort);
      if (revision != widget.source.commentScopeRevision) return const Res.error("Source settings changed; refresh comments");
      return result;
    },
      sort: widget.source.preferredCommentSort(chapter: true),
      block: _shouldBlockComment);
    if (widget.replyComment == null || !_replyScopeExpired) feed.refresh();
  }
  bool _replyScopeExpired = false;
  @override
  void initState() { super.initState(); _createFeed(); ComicSource.settingsChanges.addListener(_settingsChanged); }
  void _settingsChanged() {
    if (_scopeRevision == widget.source.commentScopeRevision) return;
    feed.invalidate();
    _replyScopeExpired = widget.replyComment != null;
    scheduleMicrotask(() {
      if (!mounted) return;
      setState(() { feed.dispose(); _createFeed(); });
    });
  }
  @override
  void didUpdateWidget(covariant ChapterCommentsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_scopeRevision != widget.source.commentScopeRevision || oldWidget.source != widget.source || oldWidget.replyComment?.id != widget.replyComment?.id ||
        oldWidget.comicId != widget.comicId || oldWidget.epId != widget.epId) {
      feed.dispose(); _createFeed();
    }
  }
  @override
  void dispose() { ComicSource.settingsChanges.removeListener(_settingsChanged); feed.dispose(); controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: Appbar(
        title: Text(widget.replyComment == null ? 'Chapter Comments'.tl : '评论详情'),
        actions: [CommentProviderSelector(source: widget.source)],
        style: AppbarStyle.shadow,
      ),
      body: AnimatedBuilder(animation: feed, builder: (context, _) =>
        feed.unavailable || _replyScopeExpired ? const SizedBox.shrink() : buildBody(context)),
    );
  }

  Widget buildBody(BuildContext context) {
    if (!widget.source.hasChapterComments) return const SizedBox.shrink();
    Widget tile(Comment comment, {bool actions = true}) => _ChapterCommentTile(
      key: ValueKey('${feed.sort}:${comment.id}:${comment.content}'),
      comment: comment, source: widget.source, comicId: widget.comicId, epId: widget.epId,
      showAvatar: true, showActions: actions);
    return Column(children: [
      if (widget.chapterTitle.isNotEmpty) Align(alignment: Alignment.centerLeft,
        child: Padding(padding: const EdgeInsets.symmetric(horizontal:16,vertical:8),
          child: Text(widget.chapterTitle,style: ts.s12))),
      CommentContextStats(context: feed.commentContext),
      Expanded(child: CommentsFeed(
      controller: feed,
      onSortSelected: (sort) async {
        try { await widget.source.setPreferredCommentSort(sort, chapter: true); }
        catch (_) { if (mounted) context.showMessage(message: '评论排序保存失败'); }
      },
      sorts: widget.source.availableCommentSorts(chapter: true),
      totalLabel: widget.replyComment == null ? '评论' : '回复',
      parent: widget.replyComment == null ? null : Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          tile(widget.replyComment!, actions: false),
          const Divider(height: 1),
          const Padding(padding: EdgeInsets.all(16), child: Text('回复列表')),
        ]),
      itemBuilder: (comment) => tile(comment))), buildBottom(context)]);
  }

  Widget buildBottom(BuildContext context) {
    if (widget.source.sendChapterCommentFunc == null ||
        (widget.source.commentProviderSetting != null && widget.source.chapterCommentCapabilities?.canLoadReplies == false)) {
      return const SizedBox(height: 0);
    }
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: context.colorScheme.outlineVariant,
            width: 0.6,
          ),
        ),
      ),
      child: Material(
        color: context.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(24),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  isCollapsed: true,
                  hintText: "Comment".tl,
                ),
                minLines: 1,
                maxLines: 5,
              ),
            ),
            if (sending)
              const Padding(
                padding: EdgeInsets.all(8),
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              IconButton(
                onPressed: () async {
                  if (controller.text.isEmpty) {
                    return;
                  }
                  setState(() {
                    sending = true;
                  });
                  var b = await widget.source.sendChapterCommentFunc!(
                    widget.comicId,
                    widget.epId,
                    controller.text,
                    widget.replyComment?.id,
                  );
                  if (!mounted) return;
                  if (!b.error) {
                    controller.text = "";
                    setState(() {
                      sending = false;
                      feed.refresh();
                    });
                  } else {
                    context.showMessage(message: b.errorMessage ?? "Error");
                    setState(() {
                      sending = false;
                    });
                  }
                },
                icon: Icon(
                  Icons.send,
                  color: Theme.of(context).colorScheme.secondary,
                ),
              ),
          ],
        ).paddingLeft(16).paddingRight(4),
      ),
    );
  }
}

class _ChapterCommentTile extends StatefulWidget {
  const _ChapterCommentTile({
    super.key,
    required this.comment,
    required this.source,
    required this.comicId,
    required this.epId,
    required this.showAvatar,
    this.showActions = true,
  });

  final Comment comment;
  final ComicSource source;
  final String comicId;
  final String epId;
  final bool showAvatar;
  final bool showActions;

  @override
  State<_ChapterCommentTile> createState() => _ChapterCommentTileState();
}

class _ChapterCommentTileState extends State<_ChapterCommentTile> {
  @override
  void initState() {
    likes = widget.comment.score ?? 0;
    isLiked = widget.comment.isLiked ?? false;
    voteStatus = widget.comment.voteStatus;
    super.initState();
  }

  @override
  void didUpdateWidget(covariant _ChapterCommentTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.comment != widget.comment) {
      likes = widget.comment.score ?? 0;
      isLiked = widget.comment.isLiked ?? false;
      voteStatus = widget.comment.voteStatus;
    }
  }
  void openReply() {
    if (!widget.source.canReadReplies(widget.comment, chapter: true)) return;
    final parent = context.findAncestorStateOfType<_ChapterCommentsPageState>();
    showSideBar(context, ChapterCommentsPage(comicId: widget.comicId, epId: widget.epId,
      source: widget.source, comicTitle: parent?.widget.comicTitle ?? '',
      chapterTitle: parent?.widget.chapterTitle ?? '', replyComment: widget.comment), showBarrier: false);
  }
  @override
  Widget build(BuildContext context) => CommentPresentation(
    comment: widget.comment, sourceKey: widget.source.key, fontSize: commentsFontSize,
    actions: widget.showActions ? buildActions() : CommentReadOnlyStats(comment: widget.comment),
    onReply: widget.showActions && widget.source.canReadReplies(widget.comment, chapter: true) ? openReply : null);

  Widget buildActions() {
    if (!widget.showActions) return const SizedBox.shrink();
    final hasId = widget.comment.id != null;
    final canReply = widget.source.canReadReplies(widget.comment, chapter: true);
    return Padding(padding: const EdgeInsets.only(top: 8), child: Wrap(
      spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
      if (widget.comment.score != null)
        if (hasId && widget.source.voteCommentFunc != null && (widget.source.commentProviderSetting == null || widget.source.chapterCommentCapabilities?.canLoadReplies != false)) buildVote()
        else if (hasId && widget.source.likeCommentFunc != null && (widget.source.commentProviderSetting == null || widget.source.chapterCommentCapabilities?.canLoadReplies != false)) buildLike()
        else CommentReadOnlyStats(comment: Comment.fromJson({'score': widget.comment.score})),
      if (widget.comment.replyCount != null)
        if (canReply) buildReply()
        else CommentReadOnlyStats(comment: Comment.fromJson({'replyCount': widget.comment.replyCount})),
    ]));
  }

  Widget buildReply() {
    return Container(
      margin: const EdgeInsets.only(left: 8),
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
          width: 0.6,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: openReply,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.insert_comment_outlined, size: 16),
            const SizedBox(width: 8),
            Text(widget.comment.replyCount.toString()),
          ],
        ).padding(const EdgeInsets.symmetric(horizontal: 12, vertical: 4)),
      ),
    );
  }

  bool isLiking = false;
  bool isLiked = false;
  var likes = 0;

  Widget buildLike() {
    return Container(
      margin: const EdgeInsets.only(left: 8),
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
          width: 0.6,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          if (isLiking) return;
          setState(() {
            isLiking = true;
          });
          var res = await widget.source.likeCommentFunc!(
            widget.comicId,
            widget.epId,
            widget.comment.id!,
            !isLiked,
          );
          if (!mounted) return;
    if (res.success) {
            isLiked = !isLiked;
            likes += isLiked ? 1 : -1;
          } else {
            context.showMessage(message: res.errorMessage ?? "Error");
          }
          setState(() {
            isLiking = false;
          });
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLiking)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(),
              )
            else if (isLiked)
              Icon(
                Icons.favorite,
                size: 16,
                color: context.useTextColor(Colors.red),
              )
            else
              const Icon(Icons.favorite_border, size: 16),
            const SizedBox(width: 8),
            Text(likes.toString()),
          ],
        ).padding(const EdgeInsets.symmetric(horizontal: 12, vertical: 4)),
      ),
    );
  }

  int? voteStatus;
  bool isVotingUp = false;
  bool isVotingDown = false;

  void vote(bool isUp) async {
    if (isVotingUp || isVotingDown) return;
    setState(() {
      if (isUp) {
        isVotingUp = true;
      } else {
        isVotingDown = true;
      }
    });
    var isCancel = (isUp && voteStatus == 1) || (!isUp && voteStatus == -1);
    var res = await widget.source.voteCommentFunc!(
      widget.comicId,
      widget.epId,
      widget.comment.id!,
      isUp,
      isCancel,
    );
    if (!mounted) return;
    if (res.success) {
      if (isCancel) {
        voteStatus = 0;
      } else {
        if (isUp) {
          voteStatus = 1;
        } else {
          voteStatus = -1;
        }
      }
      widget.comment.voteStatus = voteStatus;
      widget.comment.score = res.data ?? widget.comment.score;
    } else {
      context.showMessage(message: res.errorMessage ?? "Error");
    }
    setState(() {
      isVotingUp = false;
      isVotingDown = false;
    });
  }

  Widget buildVote() {
    var upColor = context.colorScheme.outline;
    if (voteStatus == 1) {
      upColor = context.useTextColor(Colors.red);
    }
    var downColor = context.colorScheme.outline;
    if (voteStatus == -1) {
      downColor = context.useTextColor(Colors.blue);
    }

    return Container(
      margin: const EdgeInsets.only(left: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
          width: 0.6,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Button.icon(
            isLoading: isVotingUp,
            icon: const Icon(Icons.arrow_upward),
            size: 18,
            color: upColor,
            onPressed: () => vote(true),
          ),
          const SizedBox(width: 4),
          Text(widget.comment.score.toString()),
          const SizedBox(width: 4),
          Button.icon(
            isLoading: isVotingDown,
            icon: const Icon(Icons.arrow_downward),
            size: 18,
            color: downColor,
            onPressed: () => vote(false),
          ),
        ],
      ),
    );
  }
}

/// Shared by chapter-load entry and lazy footer. Requests start synchronously;
/// each source revision / work / episode owns an isolated controller generation.
// A declared provider always retains a recovery footer, even for an explicit
// unavailable/empty result. Payload and metadata remain unmodified.
class _ProviderChapterFeed extends CommentsController {
  _ProviderChapterFeed({required this.source, required super.loader, super.sort, super.block});
  final ComicSource source;
  VoidCallback? _ownerListener;
  bool _retired = false;
  bool _released = false;
  bool _releaseScheduled = false;

  void attachOwner(VoidCallback listener) {
    assert(_ownerListener == null && !_retired);
    _ownerListener = listener;
    addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    _finishDisposal();
  }

  // AnimatedBuilder owns the actual borrow: it can detach and reattach its
  // merged Listenable during one synchronous update, even after the reader
  // retires this generation. Never dispose between those two operations.
  void _finishDisposal() {
    // hasListeners may still include a removed listener while ChangeNotifier
    // is notifying. Check it only after that notification has unwound.
    if (!_retired || _released || _releaseScheduled) return;
    _releaseScheduled = true;
    scheduleMicrotask(() {
      _releaseScheduled = false;
      if (_released || hasListeners) return;
      _released = true;
      super.dispose();
    });
  }

  @override
  void dispose() {
    if (_retired) return;
    _retired = true;
    // Cancel generations now, not when the last footer eventually detaches.
    invalidate();
    final listener = _ownerListener;
    _ownerListener = null;
    if (listener != null) removeListener(listener);
    _finishDisposal();
  }

  @override
  bool get unavailable => source.commentProviderOptions.isEmpty && super.unavailable;
  @override
  bool get confirmedEmpty => source.commentProviderOptions.isEmpty && super.confirmedEmpty;
}

class ReaderChapterCommentsFeeds {
  ReaderChapterCommentsFeeds({this.onChanged}) {
    ComicSource.settingsChanges.addListener(_settingsChanged);
  }
  final Map<String, (ComicSource, String, String)> _requests = {};
  final Map<String, String> _revisions = {};
  void _settingsChanged() {
    final changed = _requests.entries.where((entry) =>
      _revisions[entry.key] != entry.value.$1.commentScopeRevision).toList();
    final sources = changed.map((entry) => entry.value.$1.key).toSet();
    for (final cached in _feeds.entries.toList()) {
      if (sources.any((key) => cached.key.startsWith('$key:'))) {
        // Retirement invalidates immediately, but disposal waits for the last
        // preview's AnimatedBuilder to detach (the reader rebuilds post-frame).
        cached.value.dispose();
        _feeds.remove(cached.key);
      }
    }
    for (final entry in changed) {
      final (source, comicId, epId) = entry.value;
      final feed = chapterLoading(source, comicId, epId);
      onChanged?.call(epId, source.commentScopeRevision, feed);
    }
  }
  final void Function(String epId, String revision, CommentsController feed)? onChanged;
  final Map<String, CommentsController> _feeds = {};
  CommentsController chapterLoading(ComicSource source,String comicId,String epId) {
    final requestKey = '${source.key}:$comicId:$epId';
    _requests[requestKey] = (source, comicId, epId);
    _revisions[requestKey] = source.commentScopeRevision;
    final revision = source.commentScopeRevision;
    final key = '${source.key}:$revision:$comicId:$epId';
    return _feeds.putIfAbsent(key, () {
      final feed = _ProviderChapterFeed(source: source,
        sort: source.preferredCommentSort(chapter: true),
        block:_shouldBlockComment,
        loader:(page,sort) async {
          final result = await source.loadCommentPage(comicId,epId,page,null,chapter:true,sort:sort);
          if(revision!=source.commentScopeRevision) return const Res.error('Source settings changed; refresh comments');
          return result;
        });
      feed.attachOwner(() => onChanged?.call(epId,revision,feed));
      unawaited(feed.refresh());
      return feed;
    });
  }
  void dispose() {
    ComicSource.settingsChanges.removeListener(_settingsChanged);
    _requests.clear(); _revisions.clear();
    for(final feed in _feeds.values) { feed.dispose(); }
    _feeds.clear();
  }
}

/// A compact chapter footer in the reader, with a full comments route.
/// Never fabricates a total count: the badge counts the fetched first page.
class ChapterCommentsPreview extends StatefulWidget {
  const ChapterCommentsPreview({super.key, required this.comicId,
    required this.epId, required this.source, required this.comicTitle,
    required this.chapterTitle, this.sharedFeed, this.horizontal = false, this.reverse = false});
  final bool horizontal, reverse;
  final String comicId, epId, comicTitle, chapterTitle;
  final CommentsController? sharedFeed;
  final ComicSource source;
  @override
  State<ChapterCommentsPreview> createState() => ChapterCommentsPreviewState();
}

class ChapterCommentsPreviewState extends State<ChapterCommentsPreview> {
  bool _ownsFeed = false;
  bool _ignoreShared = false;
  void _settingsChanged() {
    if (_scopeRevision == widget.source.commentScopeRevision) return;
    // ReaderChapterCommentsFeeds owns invalidation/replacement for a borrowed
    // feed. The reader's next build passes that replacement; do not also issue
    // an independent preview request in this notification.
    if (!_ownsFeed && widget.sharedFeed != null) return;
    feed.invalidate();
    _ignoreShared = true;
    scheduleMicrotask(() {
      if (!mounted) return;
      setState(() {
        if (_ownsFeed) feed.dispose();
        _createFeed();
      });
    });
  }
  late CommentsController feed;
  late String _scopeRevision;
  void _createFeed() {
    _scopeRevision = widget.source.commentScopeRevision;
    if (!_ignoreShared && widget.sharedFeed != null) {
      _ownsFeed = false; feed = widget.sharedFeed!; return;
    }
    _ownsFeed = true;
    feed = CommentsController(loader: (page, sort) async {
      final revision = _scopeRevision;
      final result = await widget.source.loadCommentPage(
        widget.comicId, widget.epId, page, null, chapter: true, sort: sort);
      if (revision != widget.source.commentScopeRevision) return const Res.error("Source settings changed; refresh comments");
      return result;
    },
      sort: widget.source.preferredCommentSort(chapter: true), block: _shouldBlockComment);
    feed.refresh();
  }
  @override
  void initState() { super.initState(); _createFeed(); ComicSource.settingsChanges.addListener(_settingsChanged); }
  @override
  void didUpdateWidget(covariant ChapterCommentsPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_scopeRevision != widget.source.commentScopeRevision || oldWidget.epId != widget.epId || oldWidget.comicId != widget.comicId ||
        oldWidget.source != widget.source || oldWidget.sharedFeed != widget.sharedFeed) {
      if (_ownsFeed) feed.dispose();
      _ignoreShared = false;
      _createFeed();
    }
  }
  @override
  void dispose() { ComicSource.settingsChanges.removeListener(_settingsChanged); if (_ownsFeed) feed.dispose(); super.dispose(); }
  void _openAll() => context.to(() => ChapterCommentsPage(
    comicId: widget.comicId, epId: widget.epId, source: widget.source,
    comicTitle: widget.comicTitle, chapterTitle: widget.chapterTitle));
  void _openReply(Comment comment) => context.to(() => ChapterCommentsPage(
    comicId: widget.comicId, epId: widget.epId, source: widget.source,
    comicTitle: widget.comicTitle, chapterTitle: widget.chapterTitle, replyComment: comment));

  // Natural chapter content; old persisted height multipliers are inert.
  static const previewLimit = 4;
  @override
  Widget build(BuildContext context) {
    final hasSelector = widget.source.commentProviderOptions.isNotEmpty;
    if (!widget.source.hasChapterComments && !hasSelector) return const SizedBox.shrink();
    return AnimatedBuilder(animation: Listenable.merge([feed, appdata.settings]),
      builder: (context, _) {
        if ((feed.unavailable || feed.confirmedEmpty) && !hasSelector) return const SizedBox.shrink();
        final sorts = widget.source.availableCommentSorts(chapter: true);
        final sortSelector = CommentSortSelector(sorts: sorts, value: feed.sort,
          onSelected: (sort) async {
            try { await widget.source.setPreferredCommentSort(sort, chapter: true); }
            catch (_) { if (mounted) context.showMessage(message: '评论排序保存失败'); }
          });
        if (widget.horizontal) {
          return LayoutBuilder(builder: (context, constraints) {
          final width = MediaQuery.sizeOf(context).width;
          // Each semantic section occupies a chapter-scroll panel. No nested
          // scrollable: at large text/short heights the reply action gets its
          // own reachable panel instead of overflowing below the viewport.
          Widget panel(List<Widget> children) => SizedBox(width: width,
            child: Padding(padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: children)));
          Widget preview(String text, {TextStyle? style, int maxLines = 2}) => Expanded(
            child: LayoutBuilder(builder: (context, constraints) {
              final base = style?.fontSize ?? 14;
              final lineHeight = MediaQuery.textScalerOf(context).scale(base) * 1.5;
              final lines = (constraints.maxHeight / lineHeight).floor();
              if (lines < 1) return const SizedBox.shrink();
              return Text(text, maxLines: lines.clamp(1, maxLines), overflow: TextOverflow.ellipsis,
                style: (style ?? const TextStyle()).copyWith(height: 1.5));
            }));
          // Unlike the old ellipsized body, every measured line gets a panel.
          // This keeps a finite horizontal chapter viewport free of inner scroll.
          List<Widget> textPanels(String text, {double? fontSize}) {
            final style = TextStyle(fontSize: fontSize ?? commentsFontSize, height: 1.5);
            final available = math.max(1.0, constraints.maxHeight - 32);
            final painter = TextPainter(text: TextSpan(text: text, style: style),
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context))..layout(maxWidth: math.max(1.0, width - 32));
            final result = <Widget>[];
            var start = 0;
            while (start < text.length) {
              var end = start;
              final startY = painter.getOffsetForCaret(TextPosition(offset: start), Rect.zero).dy;
              for (final line in painter.computeLineMetrics()) {
                if (line.baseline - line.ascent < startY - 0.1) continue;
                if (line.baseline + line.descent - startY > available && end > start) break;
                final position = painter.getPositionForOffset(Offset(0, line.baseline));
                final boundary = painter.getLineBoundary(position);
                end = math.max(end, boundary.end);
                if (end < text.length && text.codeUnitAt(end) == 10) end++;
                if (line.baseline + line.descent - startY > available) break;
              }
              if (end <= start) end = text.length;
              result.add(panel([Text(text.substring(start, end), style: style)]));
              start = end;
            }
            painter.dispose();
            return result;
          }
          return Material(color:context.colorScheme.surface,child:Row(
            textDirection:widget.reverse ? TextDirection.rtl : TextDirection.ltr,
            key:const ValueKey('chapter-comments-region'),
            crossAxisAlignment:CrossAxisAlignment.stretch,children:[
            panel([
              Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [Text('Chapter Comments'.tl,style:ts.s18), CommentProviderSelector(source: widget.source)]),
              preview(widget.chapterTitle),
              TextButton(onPressed:_openAll,child:Text('View all comments'.tl)),
            ]),
            if (sorts.length > 1 || feed.commentContext != null) panel([
              if (sorts.length > 1) sortSelector,
              CommentContextStats(context: feed.commentContext),
            ]),
            if(feed.loading) panel([const Center(child:CircularProgressIndicator())]),
            if(feed.error!=null) panel([
              preview(feed.error!),
              TextButton(onPressed:feed.refresh,child:const Text('重试')),
            ]),
            if(!feed.loading && feed.error==null)
              for(final comment in feed.comments.take(previewLimit)) ...[
                panel([CommentAvatar(url:comment.avatar,sourceKey:widget.source.key),
                  preview(comment.userName)]),
                panel([CommentMetadata(comment: comment),
                  if (comment.time != null) preview(comment.time!, style: ts.s12)]),
                panel([CommentReadOnlyStats(comment:comment,onReply:
                  widget.source.canReadReplies(comment,chapter:true) ? ()=>_openReply(comment) : null)]),
                ...textPanels(comment.content),
                for (final reply in comment.effectiveReplyPreviews) ...[
                  ...textPanels(reply.userName, fontSize: 14),
                  panel([CommentMetadata(comment: reply),
                    if (reply.time != null) preview(reply.time!, style: ts.s12)]),
                  ...textPanels(reply.content),
                ],
              ],
            panel([OutlinedButton(onPressed:_openAll,child:Text('View all comments'.tl))]),
          ]));
          });
        }
        return Material(color: context.colorScheme.surface,
          child: Column(key: const ValueKey('chapter-comments-region'),
            crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(padding: const EdgeInsets.fromLTRB(16,12,16,0), child: Wrap(
              alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center,
              children: [Text('Chapter Comments'.tl, style: ts.s18),
                CommentProviderSelector(source: widget.source),
                TextButton(onPressed: _openAll, child: Text('View all comments'.tl))])),
            if (widget.chapterTitle.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(horizontal:16),
              child: Text(widget.chapterTitle,style: ts.s12)),
            if (sorts.length > 1) Align(alignment: Alignment.centerLeft,
              child: sortSelector),
            CommentContextStats(context: feed.commentContext),
            if (feed.loading) const Padding(padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()))
            else if (feed.error != null) Padding(padding: const EdgeInsets.all(16),
              child: Column(children:[Text(feed.error!),
                TextButton(onPressed:feed.refresh,child:const Text('重试'))]))
            else for (final comment in feed.comments.take(previewLimit))
              CommentPresentation(key: ValueKey('${feed.sort}:${comment.id}:${comment.content}'),
                comment:comment,sourceKey:widget.source.key,fontSize:commentsFontSize,
                selectable:false,
                onReply:widget.source.canReadReplies(comment,chapter:true) ? () => _openReply(comment) : null),
            Padding(padding: const EdgeInsets.fromLTRB(16,0,16,12), child: OutlinedButton(
              onPressed:_openAll,child:Text('View all comments'.tl))),
          ]));
      });
  }
}
