import 'package:flutter/material.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/image_provider/cached_image.dart';
import 'package:venera/components/rich_comment_content.dart';

/// Always reserves a real avatar or explicit generic placeholder, including errors.
class CommentAvatar extends StatelessWidget {
  const CommentAvatar({super.key, this.url, this.sourceKey});
  final String? url, sourceKey;
  @override
  Widget build(BuildContext context) {
    final fallback = ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(Icons.person_outline, color: Theme.of(context).colorScheme.onSurfaceVariant));
    return SizedBox(width: 40, height: 40, child: ClipOval(child:
      url == null ? fallback : Image(image: CachedImageProvider(url!, sourceKey: sourceKey),
        fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback)));
  }
}

/// Shared between work, chapter, embedded and footer entry points.
class CommentPresentation extends StatelessWidget {
  const CommentPresentation({super.key, required this.comment, this.sourceKey,
    this.fontSize = 15, this.actions, this.onReply, this.compact = false});
  final Comment comment;
  final String? sourceKey;
  final double fontSize;
  final Widget? actions;
  final VoidCallback? onReply;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    Widget preview(Comment reply) => Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(reply.userName, style: TextStyle(fontSize: fontSize - 1, fontWeight: FontWeight.w600)),
        if (reply.time != null) Text(reply.time!, style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
        const SizedBox(height: 4),
        CommentContent(text: reply.content, fontSize: fontSize),
        if (onReply != null) Align(alignment: Alignment.centerRight,
          child: TextButton(onPressed: onReply, child: const Text('查看回复详情'))),
      ]));
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CommentAvatar(url: comment.avatar, sourceKey: sourceKey),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(comment.userName, style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600)),
          if (comment.time != null) Text(comment.time!,
            style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
          const SizedBox(height: 6),
          // Unknown protocol emoji stays intact. The rich renderer handles only known formats.
          CommentContent(text: comment.content, fontSize: fontSize),
          if (comment.replyPreview != null) preview(comment.replyPreview!),
          if (actions != null) actions! else CommentReadOnlyStats(comment: comment, onReply: onReply),
        ])),
      ]));
  }
}

class CommentReadOnlyStats extends StatelessWidget {
  const CommentReadOnlyStats({super.key, required this.comment, this.onReply});
  final Comment comment;
  final VoidCallback? onReply;
  @override
  Widget build(BuildContext context) {
    if (comment.score == null && comment.replyCount == null) return const SizedBox.shrink();
    Widget stat(IconData icon, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 16), const SizedBox(width: 6), Text(label),
    ]);
    return Padding(padding: const EdgeInsets.only(top: 8), child: Wrap(
      spacing: 16, crossAxisAlignment: WrapCrossAlignment.center, children: [
        if (comment.score != null) stat(Icons.favorite_border, '${comment.score}'),
        if (comment.replyCount != null)
          if (onReply != null) TextButton(onPressed: onReply,
            child: stat(Icons.chat_bubble_outline, '${comment.replyCount}'))
          else stat(Icons.chat_bubble_outline, '${comment.replyCount}'),
      ]));
  }
}
