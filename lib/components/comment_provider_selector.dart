import 'package:flutter/material.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/pages/settings/qingman_profile.dart';

/// Candidates and defaults are owned by the source, not a host-wide list.
/// Remains usable when the currently selected provider is unavailable.
class CommentProviderSelector extends StatefulWidget {
  const CommentProviderSelector({super.key, required this.source});
  final ComicSource source;
  @override
  State<CommentProviderSelector> createState() => _CommentProviderSelectorState();
}

class _CommentProviderSelectorState extends State<CommentProviderSelector> {
  @override
  void initState() {
    super.initState();
    ComicSource.settingsChanges.addListener(_changed);
  }
  void _changed() { if (mounted) setState(() {}); }
  @override
  void dispose() {
    ComicSource.settingsChanges.removeListener(_changed);
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    final options = widget.source.commentProviderOptions;
    if (options.isEmpty) return const SizedBox.shrink();
    final value = widget.source.commentProviderValue;
    return PopupMenuButton<String>(
      tooltip: '默认评论接口',
      initialValue: value,
      onSelected: (selected) async {
        if (selected == '\u0000profile') {
          await Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => const QingmanProfilePage()));
          widget.source.refreshCommentProvider();
          return;
        }
        try {
          await widget.source.setCommentProvider(selected);
        } catch (_) {
          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('评论接口设置保存失败，请重试')));
        }
      },
      itemBuilder: (_) => [
        for (final option in options.entries)
          CheckedPopupMenuItem(value: option.key, checked: option.key == value,
            child: Text(option.value)),
        if (options.containsKey('qingman')) ...[
          const PopupMenuDivider(),
          const PopupMenuItem(value: '\u0000profile', child: Text('青漫连接配置')),
        ],
      ],
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(options[value] ?? '评论接口', style: Theme.of(context).textTheme.labelLarge),
          const Icon(Icons.arrow_drop_down, size: 18),
        ])),
    );
  }
}
