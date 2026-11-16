import 'package:flutter/material.dart';
import 'package:venera/components/components.dart';
import 'package:venera/foundation/context.dart';
import 'package:venera/utils/ext.dart';
import 'package:venera/utils/translations.dart';

/// Chapter picker used by the in-reader download button.
///
/// The comic details page has its own private picker, but that one lives inside
/// the details page library and cannot be reused from the reader. This is a
/// standalone version with the same behaviour plus:
///   * [preselected] — the chapter currently open in the reader, so tapping
///     "Download" inside a chapter offers to download that very chapter.
///   * an explicit "Select All / Invert" row, because the reader has no
///     "Download All" concept otherwise.
class DownloadChapterSelect extends StatefulWidget {
  const DownloadChapterSelect({
    super.key,
    required this.titles,
    required this.downloadedEps,
    required this.finishSelect,
    this.preselected = const <int>{},
    this.hiddenEps = const <int>{},
  });

  final List<String> titles;

  /// Indices that are already downloaded. Rendered checked and disabled, and
  /// excluded from "Select All" / "Invert".
  final List<int> downloadedEps;

  final void Function(List<int>) finishSelect;

  final Set<int> preselected;

  /// Indices collapsed by the "hide duplicate chapters" switch.
  final Set<int> hiddenEps;

  @override
  State<DownloadChapterSelect> createState() => _DownloadChapterSelectState();
}

class _DownloadChapterSelectState extends State<DownloadChapterSelect> {
  late final List<int> selected = [
    for (final i in widget.preselected)
      if (!widget.downloadedEps.contains(i) && !widget.hiddenEps.contains(i)) i,
  ];

  /// Original indices into [widget.titles] that are rendered, in list order.
  List<int> get _visible => [
    for (int i = 0; i < widget.titles.length; i++)
      if (!widget.hiddenEps.contains(i)) i,
  ];

  void _selectAll() {
    setState(() {
      selected
        ..clear()
        ..addAll(
          _visible.where((i) => !widget.downloadedEps.contains(i)),
        );
    });
  }

  void _clearAll() {
    setState(() {
      selected.clear();
    });
  }

  void _invert() {
    setState(() {
      final next = <int>[];
      for (final i in _visible) {
        if (widget.downloadedEps.contains(i)) continue;
        if (!selected.contains(i)) next.add(i);
      }
      selected
        ..clear()
        ..addAll(next);
    });
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final selectableCount = visible
        .where((i) => !widget.downloadedEps.contains(i))
        .length;
    return Scaffold(
      appBar: Appbar(
        title: Text("Download".tl),
        backgroundColor: context.colorScheme.surfaceContainerLow,
        actions: [
          IconButton(
            tooltip: "Select All".tl,
            icon: const Icon(Icons.select_all),
            onPressed: selectableCount == 0 ? null : _selectAll,
          ),
          IconButton(
            tooltip: "Invert selection".tl,
            icon: const Icon(Icons.flip_to_back),
            onPressed: selectableCount == 0 ? null : _invert,
          ),
          IconButton(
            tooltip: "Deselect All".tl,
            icon: const Icon(Icons.deselect),
            onPressed: selected.isEmpty ? null : _clearAll,
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              "@a chapters selected".tlParams({"a": selected.length}),
              style: TextStyle(color: context.colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: visible.length,
              itemBuilder: (context, slot) {
                final i = visible[slot];
                final done = widget.downloadedEps.contains(i);
                return CheckboxListTile(
                  dense: true,
                  title: Text(
                    widget.titles[i],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: done ? Text("Already downloaded".tl) : null,
                  value: done || selected.contains(i),
                  onChanged: done
                      ? null
                      : (v) {
                          setState(() {
                            if (selected.contains(i)) {
                              selected.remove(i);
                            } else {
                              selected.add(i);
                            }
                          });
                        },
                );
              },
            ),
          ),
          Container(
            height: 50,
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: context.colorScheme.outlineVariant),
              ),
            ),
            child: Row(
              children: [
                const SizedBox(width: 16),
                Expanded(
                  child: TextButton(
                    onPressed: _clearAll,
                    child: Text("Cancel".tl),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: FilledButton(
                    onPressed: selected.isEmpty
                        ? null
                        : () {
                            widget.finishSelect(List<int>.from(selected));
                            context.pop();
                          },
                    child: Text("Download Selected".tl),
                  ),
                ),
                const SizedBox(width: 16),
              ],
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }
}

/// Shows [DownloadChapterSelect] as a sidebar and resolves to the picked
/// chapter indices, or `null` when the user dismisses it without choosing.
Future<List<int>?> showDownloadChapterSelect(
  BuildContext context, {
  required List<String> titles,
  required List<int> downloadedEps,
  Set<int> preselected = const <int>{},
  Set<int> hiddenEps = const <int>{},
}) async {
  List<int>? result;
  await showSideBar(
    context,
    DownloadChapterSelect(
      titles: titles,
      downloadedEps: downloadedEps,
      preselected: preselected,
      hiddenEps: hiddenEps,
      finishSelect: (v) => result = v,
    ),
  );
  return result;
}
