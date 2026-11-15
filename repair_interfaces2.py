from pathlib import Path
import subprocess
root=Path('/var/minis/workspace/Venera-3.0.0-custom')

def add_once(fn, anchor, text):
 p=root/fn; s=p.read_text()
 if text.strip() not in s:
  if anchor not in s: raise RuntimeError(f'missing anchor {fn}: {anchor!r}')
  p.write_text(s.replace(anchor, anchor+text, 1))

# Remaining imports/state fields.
add_once('lib/pages/comic_details_page/comic_page.dart', "import 'dart:async';\n", "import 'dart:convert';\n")
add_once('lib/pages/comic_details_page/comic_page.dart', "import 'package:venera/foundation/comic_details_cache.dart';\n", "import 'package:venera/foundation/cache_manager.dart';\nimport 'package:venera/foundation/js_engine.dart';\n")
add_once('lib/pages/comic_details_page/comic_page.dart', "    with _ComicPageActions {\n", "  int _coverRefreshVersion = 0;\n\n  String get _coverUrl => comic.cover.isNotEmpty ? comic.cover : widget.cover ?? '';\n\n")

# Add the coherent upstream collection cover helper if it is absent.
p=root/'lib/pages/comic_details_page/comic_page.dart'; s=p.read_text()
if 'Widget _buildCollectionCovers()' not in s:
 up=subprocess.check_output(['git','show','synthetic/upstream-v3.0.0-walter-base:lib/pages/comic_details_page/comic_page.dart'],cwd=root,text=True)
 i=up.index('  Widget _buildCollectionCovers()'); j=up.index('  Widget buildThumbnails()',i)
 anchor=s.index('  Widget buildChapters()')
 p.write_text(s[:anchor]+up[i:j]+s[anchor:])

# Chapter cover grid state and loader helper.
p=root/'lib/pages/comic_details_page/chapters.dart'; s=p.read_text()
if '_locatedChapter' not in s[:s.index('class _NormalComicChaptersState')+500]:
 s=s.replace('    with _ChapterSelectionMixin {\n', '    with _ChapterSelectionMixin {\n  int? _locatedChapter;\n  final _chapterGridKey = GlobalKey();\n', 1)
if 'class _LazyChapterCover' not in s:
 s += "\n\nclass _LazyChapterCover extends StatelessWidget {\n  const _LazyChapterCover({required this.coverUrl, required this.placeholderIndex, required this.sourceKey, required this.comicId, required this.epId});\n  final String? coverUrl;\n  final int placeholderIndex;\n  final String sourceKey;\n  final String comicId;\n  final String epId;\n  @override\n  Widget build(BuildContext context) {\n    final url = coverUrl;\n    if (url == null || url.isEmpty) {\n      return ColoredBox(color: context.colorScheme.surfaceContainerHighest, child: Center(child: Text('$placeholderIndex')));\n    }\n    return AnimatedImage(image: CachedImageProvider(url, sourceKey: sourceKey));\n  }\n}\n"
 p.write_text(s)

# Minimal last-read locator action remains wired and scrolls the chapter section into view.
p=root/'lib/pages/comic_details_page/comic_page.dart'; s=p.read_text()
if 'VoidCallback? get jumpToLastReadChapter' not in s:
 anchor='  @override\n  void reloadDetails() {'
 insert="  VoidCallback? get jumpToLastReadChapter => history == null ? null : () {\n    if (scrollController.hasClients) {\n      scrollController.animateTo(\n        scrollController.position.maxScrollExtent,\n        duration: const Duration(milliseconds: 250),\n        curve: Curves.easeOut,\n      );\n    }\n  };\n\n"
 s=s.replace(anchor,insert+anchor,1)
 p.write_text(s)
print('interfaces2 done')
