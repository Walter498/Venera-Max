import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:venera/foundation/chapter_metadata.dart';

/// Dates and live likes stay outside artwork in both chapter layouts.
class ChapterMetadataLine extends StatelessWidget {
  const ChapterMetadataLine({
    super.key, required this.metadata, this.stacked = false, this.centered = false,
  });
  final ChapterMetadata metadata;
  final bool stacked;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    final dateText = metadata.displayDate;
    final likesText = metadata.displayLikes;
    final date = dateText == null ? null : Text(dateText,
      key: const ValueKey('chapter-update-date'), maxLines: 1);
    final likes = likesText == null ? null : Tooltip(
      message: metadata.likesSource == 'tencent' ? '腾讯章节点赞' : '章节点赞',
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.thumb_up_outlined, size: 12, color: color),
        const SizedBox(width: 3),
        Text(likesText, key: const ValueKey('chapter-like-count'), maxLines: 1),
      ]),
    );
    final alignment = centered ? Alignment.center : Alignment.centerLeft;
    Widget fitted(Widget child) => FittedBox(
      fit: BoxFit.scaleDown, alignment: alignment, child: child);
    final facts = <Widget>[
      if (date != null) date,
      if (date != null && likes != null) ...[
        const SizedBox(width: 7),
        Text('|', style: TextStyle(color: color.withValues(alpha: 0.45))),
        const SizedBox(width: 7),
      ],
      if (likes != null) likes,
    ];
    if (facts.isEmpty) return const SizedBox.shrink();
    return DefaultTextStyle(
      style: Theme.of(context).textTheme.bodySmall!.copyWith(
        color: color, fontSize: 11, height: 16 / 11),
      child: stacked
        ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (date != null) fitted(date),
            if (likes != null) fitted(likes),
          ])
        : fitted(Row(mainAxisSize: MainAxisSize.min, children: facts)),
    );
  }
}

/// One shared sizing policy for collapsed Wrap and expanded SliverGrid.
class ChapterCardLayout {
  static int coverColumns(double width) => math.max(4, (width / 110).floor());
  static double coverExtent(BuildContext context, double width) =>
      width * 0.82 + 8 + MediaQuery.textScalerOf(context).scale(66);
  static double textExtent(BuildContext context) =>
      24 + MediaQuery.textScalerOf(context).scale(40);
}

class ChapterTextContent extends StatelessWidget {
  const ChapterTextContent({super.key, required this.title,
    required this.metadata, this.titleColor});
  final String title;
  final ChapterMetadata metadata;
  final Color? titleColor;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(title, maxLines: 1, textAlign: TextAlign.center,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: titleColor)),
      const SizedBox(height: 3),
      ChapterMetadataLine(metadata: metadata, centered: true),
    ],
  );
}

class ChapterCoverCaption extends StatelessWidget {
  const ChapterCoverCaption({super.key, required this.title,
    required this.metadata, this.titleColor});
  final String title;
  final ChapterMetadata metadata;
  final Color? titleColor;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(height: MediaQuery.textScalerOf(context).scale(34),
        child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, height: 17 / 12,
            fontWeight: FontWeight.w600, color: titleColor))),
      const SizedBox(height: 4),
      ChapterMetadataLine(metadata: metadata, stacked: true),
    ],
  );
}
