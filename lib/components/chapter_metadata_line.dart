import 'package:flutter/material.dart';
import 'package:venera/foundation/chapter_metadata.dart';

/// Kept outside the cover so metadata never obscures comic artwork.
class ChapterMetadataLine extends StatelessWidget {
  const ChapterMetadataLine({super.key, required this.metadata});
  final ChapterMetadata metadata;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return DefaultTextStyle(
      style: Theme.of(context).textTheme.bodySmall!.copyWith(color: color),
      child: Row(children: [
        Flexible(child: Text(metadata.displayDate ?? '日期暂无',
          key: const ValueKey('chapter-update-date'),
          maxLines: 1, overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 6),
        Text('|', style: TextStyle(color: color.withValues(alpha: 0.45))),
        const SizedBox(width: 6),
        Tooltip(message: metadata.likesSource == 'tencent' ? '腾讯章节点赞' : '章节点赞',
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.thumb_up_outlined, size: 13, color: color),
            const SizedBox(width: 3),
            Text(metadata.displayLikes ?? '暂无',
              key: const ValueKey('chapter-like-count'), maxLines: 1),
          ])),
      ]),
    );
  }
}
