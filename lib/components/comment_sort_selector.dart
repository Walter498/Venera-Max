import 'package:flutter/material.dart';

/// Only source-advertised values are offered. Persistence belongs to the page;
/// legacy callers may instead refresh their local controller.
class CommentSortSelector extends StatelessWidget {
  const CommentSortSelector({super.key, required this.sorts,
    required this.value, required this.onSelected});
  final List<String> sorts;
  final String? value;
  final ValueChanged<String> onSelected;
  static String label(String sort) => const {
    'new': '最新', 'hot': '最热', 'wonderful': '精彩',
  }[sort] ?? sort;

  @override
  Widget build(BuildContext context) {
    if (sorts.length < 2) return const SizedBox.shrink();
    final current = sorts.contains(value) ? value! : sorts.first;
    return PopupMenuButton<String>(
      tooltip: '评论排序',
      initialValue: current,
      onSelected: (sort) { if (sorts.contains(sort)) onSelected(sort); },
      itemBuilder: (_) => [for (final sort in sorts)
        CheckedPopupMenuItem<String>(value: sort, checked: sort == current,
          child: Text(label(sort)))],
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label(current)),
          const Icon(Icons.arrow_drop_down, size: 18),
        ])),
    );
  }
}
