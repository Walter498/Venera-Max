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
      sort: widget.source.chapterCommentsOptionsLoader == null ? null : widget.source.chapterCommentCapabilities?.defaultSort,
      block: _shouldBlockComment);
    feed.refresh();
  }
  @override
  void initState() { super.initState(); _createFeed(); }
  @override
  void didUpdateWidget(covariant ChapterCommentsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_scopeRevision != widget.source.commentScopeRevision || oldWidget.source != widget.source || oldWidget.replyComment?.id != widget.replyComment?.id ||
        oldWidget.comicId != widget.comicId || oldWidget.epId != widget.epId) {
      feed.dispose(); _createFeed();
    }
  }
  @override
  void dispose() { feed.dispose(); controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: Appbar(
        title: Text(widget.replyComment == null ? 'Chapter Comments'.tl : '评论详情'),
        style: AppbarStyle.shadow,
      ),
      body: AnimatedBuilder(animation: feed, builder: (context, _) =>
        feed.unavailable ? const SizedBox.shrink() : buildBody(context)),
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
      Expanded(child: CommentsFeed(
      controller: feed,
      sorts: widget.source.chapterCommentsOptionsLoader == null ? const [] : widget.source.chapterCommentCapabilities?.sorts ?? const [],
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
    if (widget.source.sendChapterCommentFunc == null) {
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
        if (hasId && widget.source.voteCommentFunc != null) buildVote()
        else if (hasId && widget.source.likeCommentFunc != null) buildLike()
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

/// Embedded chapter comments page for displaying at end of chapter in gallery mode.
class _EmbeddedChapterCommentsPage extends StatefulWidget {
  const _EmbeddedChapterCommentsPage({
    required this.comicId,
    required this.epId,
    required this.source,
    required this.comicTitle,
    required this.chapterTitle,
  });

  final String comicId;
  final String epId;
  final ComicSource source;
  final String comicTitle;
  final String chapterTitle;

  @override
  State<_EmbeddedChapterCommentsPage> createState() =>
      _EmbeddedChapterCommentsPageState();
}

class _EmbeddedChapterCommentsPageState extends State<_EmbeddedChapterCommentsPage> {
  @override
  Widget build(BuildContext context) => ChapterCommentsPage(
    comicId: widget.comicId, epId: widget.epId, source: widget.source,
    comicTitle: widget.comicTitle, chapterTitle: widget.chapterTitle);
}

/// A compact chapter footer in the reader, with a full comments route.
/// Never fabricates a total count: the badge counts the fetched first page.
class ChapterCommentsPreview extends StatefulWidget {
  const ChapterCommentsPreview({super.key, required this.comicId,
    required this.epId, required this.source, required this.comicTitle,
    required this.chapterTitle, this.sharedFeed});
  final String comicId, epId, comicTitle, chapterTitle;
  final CommentsController? sharedFeed;
  final ComicSource source;
  @override
  State<ChapterCommentsPreview> createState() => ChapterCommentsPreviewState();
}

class ChapterCommentsPreviewState extends State<ChapterCommentsPreview> {
  late CommentsController feed;
  late String _scopeRevision;
  void _createFeed() {
    _scopeRevision = widget.source.commentScopeRevision;
    if (widget.sharedFeed != null) { feed = widget.sharedFeed!; return; }
    feed = CommentsController(loader: (page, sort) async {
      final revision = _scopeRevision;
      final result = await widget.source.loadCommentPage(
        widget.comicId, widget.epId, page, null, chapter: true, sort: sort);
      if (revision != widget.source.commentScopeRevision) return const Res.error("Source settings changed; refresh comments");
      return result;
    },
      sort: widget.source.chapterCommentsOptionsLoader == null ? null :
        widget.source.chapterCommentCapabilities?.defaultSort, block: _shouldBlockComment);
    feed.refresh();
  }
  @override
  void initState() { super.initState(); _createFeed(); }
  @override
  void didUpdateWidget(covariant ChapterCommentsPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_scopeRevision != widget.source.commentScopeRevision || oldWidget.epId != widget.epId || oldWidget.comicId != widget.comicId ||
        oldWidget.source != widget.source || oldWidget.sharedFeed != widget.sharedFeed) {
      if (oldWidget.sharedFeed == null) feed.dispose();
      _createFeed();
    }
  }
  @override
  void dispose() { if (widget.sharedFeed == null) feed.dispose(); super.dispose(); }
  void _openAll() => context.to(() => ChapterCommentsPage(
    comicId: widget.comicId, epId: widget.epId, source: widget.source,
    comicTitle: widget.comicTitle, chapterTitle: widget.chapterTitle));
  void _openReply(Comment comment) => context.to(() => ChapterCommentsPage(
    comicId: widget.comicId, epId: widget.epId, source: widget.source,
    comicTitle: widget.comicTitle, chapterTitle: widget.chapterTitle, replyComment: comment));

  final _legacyKey = GlobalKey();
  final _headerKey = GlobalKey();
  final _bottomKey = GlobalKey();
  double? _legacyHeight, _chromeHeight;
  bool _measureQueued = false;
  // Layout the actual fa7afe19 footer invisibly, under the same inherited
  // width/theme/textScaler. Its entire natural region is the 1x baseline.
  Widget _legacyFooter(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16,18,16,18),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [const Icon(Icons.chat_bubble_outline_rounded,size:20),
        const SizedBox(width:8), Expanded(child:Text('Chapter Comments'.tl,style:ts.s18)),
        TextButton(onPressed:_openAll,child:Text('View all comments'.tl))]),
      Text(widget.chapterTitle,style:ts.s12.withColor(context.colorScheme.outline)),
      const SizedBox(height:10),
      if (feed.loading) const Center(child:Padding(padding:EdgeInsets.all(12),child:CircularProgressIndicator()))
      else if (feed.error != null) TextButton(onPressed:feed.refresh,child:Text('Retry'.tl))
      else for(final comment in feed.comments.take(3)) Padding(
        padding:const EdgeInsets.symmetric(vertical:8),
        child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(comment.userName,style:const TextStyle(fontWeight:FontWeight.w600)),
          if(comment.time!=null) Text(comment.time!,style:ts.s12.withColor(context.colorScheme.outline)),
          Text(comment.content,maxLines:3,overflow:TextOverflow.ellipsis),
        ])),
      const SizedBox(height:8),
      OutlinedButton.icon(onPressed:_openAll,icon:const Icon(Icons.edit_outlined,size:18),
        label:Text('View comments and reply'.tl)),
    ]));
  void _measure() {
    if (_measureQueued) return;
    _measureQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureQueued = false;
      if (!mounted) return;
      final legacy = _legacyKey.currentContext?.findRenderObject();
      final header = _headerKey.currentContext?.findRenderObject();
      final bottom = _bottomKey.currentContext?.findRenderObject();
      if (legacy is! RenderBox || header is! RenderBox || bottom is! RenderBox) return;
      final height = legacy.size.height;
      final chrome = header.size.height + bottom.size.height;
      if (_legacyHeight != height || _chromeHeight != chrome) {
        setState(() { _legacyHeight = height; _chromeHeight = chrome; });
      }
    });
  }
  @override
  Widget build(BuildContext context) {
    if (!widget.source.hasChapterComments) return const SizedBox.shrink();
    return AnimatedBuilder(animation: Listenable.merge([feed, appdata.settings]),
      builder: (context, _) {
        if (!widget.source.hasChapterComments || feed.unavailable || feed.confirmedEmpty) return const SizedBox.shrink();
        final scale = chapterCommentsScale(appdata.settings.getReaderSetting(
          widget.comicId, widget.source.key, 'chapterCommentsHeightScale'));
        return Material(color: context.colorScheme.surface, child: LayoutBuilder(
          builder: (context, constraints) {
            _measure();
            return Stack(children: [
              Offstage(child:SizedBox(width:constraints.maxWidth,
                child:SizedBox(key:_legacyKey,child:_legacyFooter(context)))),
              Column(key:const ValueKey('chapter-comments-region'),
                crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Column(key:_headerKey,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
            Padding(padding: const EdgeInsets.fromLTRB(16,12,16,0), child: Wrap(
              alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center,
              children: [Text('Chapter Comments'.tl, style: ts.s18),
                TextButton(onPressed: _openAll, child: Text('View all comments'.tl))])),
            if (widget.chapterTitle.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(horizontal:16),
              child: Text(widget.chapterTitle,style: ts.s12)),
            ]),
            SizedBox(height: math.max(1, (_legacyHeight ?? 300) * scale - (_chromeHeight ?? 100)),
              child: CommentsFeed(controller: feed,
                sorts: widget.source.chapterCommentsOptionsLoader == null ? const [] :
                  widget.source.chapterCommentCapabilities?.sorts ?? const [],
                itemBuilder: (comment) => CommentPresentation(
                  key: ValueKey('${feed.sort}:${comment.id}:${comment.content}'),
                  comment: comment, sourceKey: widget.source.key, fontSize: commentsFontSize,
                  onReply: widget.source.canReadReplies(comment, chapter:true) ? () => _openReply(comment) : null))),
            Padding(key:_bottomKey,padding: const EdgeInsets.fromLTRB(16,0,16,12), child: OutlinedButton(
              onPressed: _openAll, child: Text('View all comments'.tl))),
          ]),]);
          }));
      });
  }
}
