import 'package:flutter/material.dart';
import 'package:venera/foundation/res.dart';

/// Compact display only; Tooltip retains the exact integer, including zero.
String formatCommentCount(int count) {
  if (count < 10000) return '$count';
  final divisor = count >= 100000000 ? 100000000 : 10000;
  final suffix = count >= 100000000 ? '亿' : '万';
  final scaled = (count / divisor).toStringAsFixed(1);
  return '${scaled.endsWith('.0') ? scaled.substring(0, scaled.length - 2) : scaled}$suffix';
}

/// No click handler, fetching, guessed provider, or fabricated counts.
class CommentContextStats extends StatelessWidget {
  const CommentContextStats({super.key, required this.context});
  final Map<String, dynamic>? context;

  @override
  Widget build(BuildContext context) {
    final data = Res.parseCommentContext(this.context);
    if (data == null || data['provider'] != 'tencent') {
      return const SizedBox.shrink();
    }
    final favorite = data['comicFavoriteCount'] as int?;
    final chapterLikes = data['chapterLikeCount'] as int?;
    if (favorite == null && chapterLikes == null) return const SizedBox.shrink();
    Widget stat(IconData icon, String label, int count) => Tooltip(
      message: '$label $count',
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16), const SizedBox(width: 4),
        Flexible(child: Text('$label${formatCommentCount(count)}')),
      ]),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Wrap(spacing: 16, runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (favorite != null) stat(Icons.bookmark_border, '收藏', favorite),
          if (chapterLikes != null) stat(Icons.thumb_up_outlined, '本章获赞', chapterLikes),
        ]),
    );
  }
}
