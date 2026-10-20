import 'package:flutter/material.dart';

class ChapterDateSourceButton extends StatelessWidget {
  const ChapterDateSourceButton({super.key, required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    key: const ValueKey('chapter-date-source'),
    tooltip: value == 'tencent' ? '日期来源：腾讯发布日期' : '日期来源：栗子收录日期',
    initialValue: value,
    icon: const Icon(Icons.calendar_month_outlined),
    onSelected: onChanged,
    itemBuilder: (context) => [
      CheckedPopupMenuItem(value: 'lizi', checked: value != 'tencent', child: const Text('栗子日期')),
      CheckedPopupMenuItem(value: 'tencent', checked: value == 'tencent', child: const Text('腾讯发布日期')),
    ],
  );
}
