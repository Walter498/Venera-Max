part of 'comic_page.dart';

class _CommentsPart extends StatefulWidget {
  const _CommentsPart({required this.comments, required this.showMore, required this.source, required this.data, required this.feed});

  final CommentsController feed;

  final ComicSource source;
  final ComicDetails data;
  final List<Comment> comments;

  final void Function() showMore;

  @override
  State<_CommentsPart> createState() => _CommentsPartState();
}

class _CommentsPartState extends State<_CommentsPart> {
  late List<Comment> comments;

  @override
  void initState() {
    comments = widget.comments.where((c) => !_shouldBlockComment(c)).toList();
    super.initState();
  }

  @override
  void didUpdateWidget(covariant _CommentsPart oldWidget) {
    super.didUpdateWidget(oldWidget);
    comments = widget.comments.where((c) => !_shouldBlockComment(c)).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (comments.isEmpty) {
      return const SliverPadding(padding: EdgeInsets.zero);
    }
    return MultiSliver(
      children: [
        SliverLazyToBoxAdapter(
          child: _ComicSectionHeader(
            icon: Icons.forum_outlined,
            title: "Comments".tl,
            trailing: TextButton(
              onPressed: widget.showMore, child: Text("View more".tl)),
          ),
        ),
        SliverToBoxAdapter(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(alignment: Alignment.centerLeft, child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center, children: [
                  CommentProviderSelector(source: widget.source),
                  CommentSortSelector(sorts: widget.source.availableCommentSorts(),
                    value: widget.feed.sort, onSelected: (sort) async {
                      try { await widget.source.setPreferredCommentSort(sort); }
                      catch (_) { if (mounted) context.showMessage(message: '评论排序保存失败'); }
                    }),
                ])),
              CommentContextStats(context: widget.feed.commentContext),
              for (final comment in comments.take(4))
                _CommentWidget(comment: comment,
                  width: double.infinity, source: widget.source, data: widget.data),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ],
    );
  }
}

class _CommentWidget extends StatelessWidget {
  const _CommentWidget({required this.comment, required this.width, required this.source, required this.data});
  final Comment comment;
  final double width;
  final ComicSource source;
  final ComicDetails data;
  @override
  Widget build(BuildContext context) => Container(
    width: width, margin: const EdgeInsets.all(4),
    decoration: BoxDecoration(color: context.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12)),
    child: CommentPresentation(comment: comment,
      sourceKey: source.key, fontSize: commentsFontSize,
      onReply: source.canReadReplies(comment) ? () => showSideBar(context,
        CommentsPage(data: data, source: source, replyComment: comment), showBarrier: false) : null));
}
