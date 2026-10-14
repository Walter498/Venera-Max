part of 'comic_page.dart';

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

class CommentsPage extends StatefulWidget {
  const CommentsPage({
    super.key,
    required this.data,
    required this.source,
    this.replyComment,
    this.sharedSession,
  });

  final ComicDetails data;

  final ComicSource source;

  final Comment? replyComment;

  /// Detail owns this session. Reply pages always have their own dataset.
  final DetailsCommentsSession? sharedSession;

  @override
  State<CommentsPage> createState() => _CommentsPageState();
}

class _CommentsPageState extends State<CommentsPage> {
  late CommentsController feed;
  final controller = TextEditingController();
  bool sending = false;
  late String _scopeRevision;
  bool _ownsFeed = true;
  DetailsCommentsSession? _borrowedSession;
  bool get _scopeCurrent =>
      _scopeRevision == widget.source.commentScopeRevision &&
      (widget.replyComment != null || widget.sharedSession == null ||
          _borrowedSession?.isCurrent == true);

  void _createFeed() {
    _scopeRevision = widget.source.commentScopeRevision;
    final session = widget.sharedSession;
    if (widget.replyComment == null && session != null &&
        session.matches(widget.source, widget.data.comicId, widget.data.subId) &&
        session.borrow()) {
      _ownsFeed = false;
      _borrowedSession = session;
      feed = session.controller;
      unawaited(session.preload());
      return;
    }
    _ownsFeed = true;
    // A stale shared route must stay blank, never start an independent request
    // against its old source/subId. Reply pages still own their separate feed.
    feed = CommentsController(loader: (page, sort) async {
      final revision = _scopeRevision;
      final result = await widget.source.loadCommentPage(widget.data.comicId, widget.data.subId, page, widget.replyComment?.id, sort: sort);
      if (revision != widget.source.commentScopeRevision) return const Res.error("Source settings changed; refresh comments");
      return result;
    },
      sort: widget.source.commentsOptionsLoader == null ? null : widget.source.commentCapabilities?.defaultSort,
      block: _shouldBlockComment);
    if (_scopeCurrent) unawaited(feed.refresh());
  }

  void _onFeedChanged() {
    if (mounted) setState(() {});
  }

  void _onSettingsChanged() {
    if (_scopeRevision == widget.source.commentScopeRevision) return;
    if (_ownsFeed) feed.invalidate();
    // Settings can change during another widget's build/notification.
    scheduleMicrotask(() {
      if (mounted) setState(() {});
    });
  }

  void _detachFeed() {
    feed.removeListener(_onFeedChanged);
    final borrowed = _borrowedSession;
    _borrowedSession = null;
    if (_ownsFeed) {
      feed.dispose();
    } else {
      // Detach our listener before allowing the owner to dispose the notifier.
      borrowed!.releaseBorrow();
    }
  }

  @override
  void initState() {
    super.initState();
    _createFeed();
    feed.addListener(_onFeedChanged);
    appdata.settings.addListener(_onSettingsChanged);
  }
  @override
  void didUpdateWidget(covariant CommentsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_scopeRevision != widget.source.commentScopeRevision || oldWidget.source != widget.source || oldWidget.replyComment?.id != widget.replyComment?.id ||
        oldWidget.data != widget.data || oldWidget.sharedSession != widget.sharedSession) {
      _detachFeed();
      _createFeed();
      feed.addListener(_onFeedChanged);
    }
  }
  @override
  void dispose() {
    appdata.settings.removeListener(_onSettingsChanged);
    _detachFeed();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: Appbar(
        title: Text(widget.replyComment == null ? "Comments".tl : "评论详情"),
        style: AppbarStyle.shadow,
      ),
      body: feed.unavailable || !_scopeCurrent
          ? const SizedBox.shrink() : buildBody(context),
    );
  }

  Widget buildBody(BuildContext context) {
    if (!widget.source.hasComments) return const SizedBox.shrink();
    Widget tile(Comment comment, {bool actions = true}) => _CommentTile(
      key: ValueKey('${feed.sort}:${comment.id}:${comment.content}'),
      comment: comment, source: widget.source, comic: widget.data,
      showAvatar: true, showActions: actions);
    return Column(children: [Expanded(child: CommentsFeed(
      controller: feed,
      sorts: widget.source.commentsOptionsLoader == null ? const [] : widget.source.commentCapabilities?.sorts ?? const [],
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
    if (widget.source.sendCommentFunc == null) {
      return const SizedBox(
        height: 0,
      );
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
                    hintText: "Comment".tl),
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
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                  ),
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
                  var b = await widget.source.sendCommentFunc!(
                      widget.data.comicId,
                      widget.data.subId,
                      controller.text,
                      widget.replyComment?.id);
                  if (!mounted || !_scopeCurrent) return;
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
              )
          ],
        ).paddingLeft(16).paddingRight(4),
      ),
    );
  }
}

class _CommentTile extends StatefulWidget {
  const _CommentTile({
    super.key,
    required this.comment,
    required this.source,
    required this.comic,
    required this.showAvatar,
    this.showActions = true,
  });

  final Comment comment;

  final ComicSource source;

  final ComicDetails comic;

  final bool showAvatar;

  final bool showActions;

  @override
  State<_CommentTile> createState() => _CommentTileState();
}

class _CommentTileState extends State<_CommentTile> {
  @override
  void initState() {
    likes = widget.comment.score ?? 0;
    isLiked = widget.comment.isLiked ?? false;
    voteStatus = widget.comment.voteStatus;
    super.initState();
  }

  @override
  void didUpdateWidget(covariant _CommentTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.comment != widget.comment) {
      likes = widget.comment.score ?? 0;
      isLiked = widget.comment.isLiked ?? false;
      voteStatus = widget.comment.voteStatus;
    }
  }
  void openReply() {
    if (!widget.source.canReadReplies(widget.comment, chapter: false)) return;
    showSideBar(context, CommentsPage(data: widget.comic, source: widget.source,
      replyComment: widget.comment), showBarrier: false);
  }
  @override
  Widget build(BuildContext context) => CommentPresentation(
    comment: widget.comment, sourceKey: widget.source.key, fontSize: commentsFontSize,
    actions: widget.showActions ? buildActions() : CommentReadOnlyStats(comment: widget.comment),
    onReply: widget.showActions && widget.source.canReadReplies(widget.comment, chapter: false) ? openReply : null);

  Widget buildActions() {
    if (!widget.showActions) return const SizedBox.shrink();
    final hasId = widget.comment.id != null;
    final canReply = widget.source.canReadReplies(widget.comment, chapter: false);
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
            widget.comic.comicId,
            widget.comic.subId,
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
      widget.comic.comicId,
      widget.comic.subId,
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
