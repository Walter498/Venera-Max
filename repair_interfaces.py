from pathlib import Path
import subprocess
root=Path('/var/minis/workspace/Venera-3.0.0-custom')

def edit(fn, old, new, count=1):
 p=root/fn; s=p.read_text(); n=s.count(old)
 if n != count: raise RuntimeError(f'{fn}: expected {count}, got {n} for {old[:50]!r}')
 p.write_text(s.replace(old,new,count))

# Source parser types and dynamic API hook.
edit('lib/foundation/comic_source/comic_source.dart', "import 'package:venera/foundation/chapter_metadata.dart';", "import 'package:venera/foundation/chapter_metadata.dart';\nimport 'package:venera/foundation/category_filter_plan.dart';")
edit('lib/foundation/comic_source/comic_source.dart', "  final String version;\n\n  final ({CommentCapabilities? work, CommentCapabilities? chapter})", "  final String version;\n\n  /// Optional source-owned API transport used by the Lizi/Qingman bridges.\n  Future<Res<String>> Function(String path, [dynamic body])? apiFetch;\n\n  final ({CommentCapabilities? work, CommentCapabilities? chapter})")
edit('lib/foundation/comic_source/comic_source.dart', "  final RankingData? rankingData;\n\n  const CategoryComicsData({", "  final RankingData? rankingData;\n\n  /// Source-declared groups that can be selected together in category filters.\n  final List<String>? multiSelectGroups;\n\n  const CategoryComicsData({")
edit('lib/foundation/comic_source/comic_source.dart', "    this.rankingData,\n  });\n}\n\nclass RankingData", "    this.rankingData,\n    this.multiSelectGroups,\n  });\n}\n\nclass RankingData")

# Keep image download validation and make the page-list refresh hook optional.
edit('lib/network/images.dart', "const _imageStreamIdleTimeout = Duration(seconds: 30);", "const _imageStreamIdleTimeout = Duration(seconds: 30);\n\nbool isValidDownloadedImage(Uint8List data) =>\n    data.length >= 100 && detectFileType(data).mime.startsWith('image/');\n\nFuture<String?> _refreshComicPageUrl(\n  String sourceKey, String cid, String eid, String imageKey) async => null;")

# Search page compatibility with the upstream split ComicList.
edit('lib/pages/search_result_page.dart', "  final List<String>? options;\n\n  @override", "  final List<String>? options;\n\n  final Set<String> initialTags;\n\n  @override")

# ComicList accepts the custom source-filter hooks retained by the Walter page.
edit('lib/components/comic_list.dart', "    this.scrollbarTopPadding = 0,\n  });", "    this.scrollbarTopPadding = 0,\n    this.filterTags = const <String>{},\n    this.emptyFilterText,\n    this.onAvailableTags,\n    this.onResultCount,\n  });")
edit('lib/components/comic_list.dart', "  final double scrollbarTopPadding;\n\n  @override", "  final double scrollbarTopPadding;\n\n  final Set<String> filterTags;\n  final String? emptyFilterText;\n  final ValueChanged<Set<String>>? onAvailableTags;\n  final void Function(int? total, int loaded)? onResultCount;\n\n  @override")
edit('lib/components/comic_list.dart', "  Widget _buildGrid(List<Comic> comics, {void Function()? onLastItemBuild}) {\n    return SliverGridComics(\n      comics: comics,", "  Widget _buildGrid(List<Comic> comics, {void Function()? onLastItemBuild}) {\n    final available = <String>{\n      for (final comic in comics) ...?comic.tags,\n    };\n    widget.onAvailableTags?.call(available);\n    final visible = widget.filterTags.isEmpty\n        ? comics\n        : comics.where((comic) {\n            final tags = comic.tags ?? const <String>[];\n            return widget.filterTags.every((filter) => tags.any((tag) =>\n                tag == filter || tag.endsWith(':$filter') || tag.endsWith('@$filter')));\n          }).toList();\n    widget.onResultCount?.call(_maxPage, visible.length);\n    return SliverGridComics(\n      comics: visible,")

# Reader contracts.
edit('lib/pages/reader/gallery_mode.dart', "  void onCommentsChanged() {\n    if (mounted) setState(() {});\n  }", "  void onCommentsChanged() {\n    if (mounted) setState(() {});\n  }")
edit('lib/pages/reader/comic_image.dart', "  /// Whether the page is laid out as two stacked halves.\n  bool get isShownSplit {", "  bool get split => _imageInfo != null &&\n      widget.width == double.infinity &&\n      widget.widePageSplit.appliesTo(Size(\n        _imageInfo!.image.width.toDouble(), _imageInfo!.image.height.toDouble(),\n      ));\n\n  /// Whether the page is laid out as two stacked halves.\n  bool get isShownSplit {")
edit('lib/foundation/app_page_route.dart', "        final Velocity velocity =\n            _velocityTracker?.getVelocity() ?? Velocity.zero;", "        final velocity =\n            _velocityTracker?.getVelocity().pixelsPerSecond.dx ?? 0.0;")

# Enhancement preview uses the 3.0 builder API.
edit('lib/pages/settings/image_enhance_preview.dart', "child: EnhancedComicImage(image: image, fit: BoxFit.cover)", "child: EnhancedComicImage(\n                    image: image,\n                    builder: (enhanced) => RawImage(image: enhanced, fit: BoxFit.cover),\n                  )")

# Comment tile keeps both provider gating and reader tap ownership.
edit('lib/pages/reader/chapter_comments.dart', "    this.provider,\n  });", "    this.provider,\n    this.onContentTap,\n  });")
# Append the upstream embedded reader page, which was moved after the custom feed.
comments=root/'lib/pages/reader/chapter_comments.dart'
cs=comments.read_text()
if 'class EmbeddedChapterCommentsPage' not in cs:
 up=subprocess.check_output(['git','show','synthetic/upstream-v3.0.0-walter-base:lib/pages/reader/chapter_comments.dart'],cwd=root,text=True)
 i=up.index('class EmbeddedChapterCommentsPage')
 comments.write_text(cs+'\n\n'+up[i:])

# Details cover state and imports needed by the retained cache reset path.
edit('lib/pages/comic_details_page/comic_page.dart', "import 'dart:async';\nimport 'dart:ui';", "import 'dart:async';\nimport 'dart:convert';\nimport 'dart:ui';")
edit('lib/pages/comic_details_page/comic_page.dart', "import 'package:venera/foundation/comic_details_cache.dart';", "import 'package:venera/foundation/comic_details_cache.dart';\nimport 'package:venera/foundation/cache_manager.dart';\nimport 'package:venera/foundation/js_engine.dart';")
edit('lib/pages/comic_details_page/comic_page.dart', "class _ComicPageState extends LoadingState<ComicPage, ComicDetails> {", "class _ComicPageState extends LoadingState<ComicPage, ComicDetails> {\n  int _coverRefreshVersion = 0;\n\n  String get _coverUrl => comic.cover.isNotEmpty ? comic.cover : widget.cover ?? '';\n")
# The collection cover helper is required by the retained buildChapters path.
page=root/'lib/pages/comic_details_page/comic_page.dart'; ps=page.read_text()
if 'Widget _buildCollectionCovers()' not in ps:
 up=subprocess.check_output(['git','show','synthetic/upstream-v3.0.0-walter-base:lib/pages/comic_details_page/comic_page.dart'],cwd=root,text=True)
 i=up.index('  Widget _buildCollectionCovers()')
 j=up.index('  Widget buildChapters()',i)
 anchor=ps.index('  Widget buildChapters()')
 ps=ps[:anchor]+up[i:j]+ps[anchor:]
 page.write_text(ps)

# Chapter cover grid state/helpers.
chap=root/'lib/pages/comic_details_page/chapters.dart'; s=chap.read_text()
s=s.replace('class _NormalComicChaptersState extends State<_NormalComicChapters>', 'class _NormalComicChaptersState extends State<_NormalComicChapters> {\n  int? _locatedChapter;\n  final _chapterGridKey = GlobalKey();', 1)
# The replacement above closes the declaration's opening brace; remove the old one on the next line.
s=s.replace('  int? _locatedChapter;\n  final _chapterGridKey = GlobalKey(); {', '  int? _locatedChapter;\n  final _chapterGridKey = GlobalKey();', 1)
if 'class _LazyChapterCover' not in s:
 s += "\n\nclass _LazyChapterCover extends StatelessWidget {\n  const _LazyChapterCover({required this.coverUrl, required this.placeholderIndex, required this.sourceKey, required this.comicId, required this.epId});\n  final String? coverUrl;\n  final int placeholderIndex;\n  final String sourceKey;\n  final String comicId;\n  final String epId;\n  @override\n  Widget build(BuildContext context) {\n    final url = coverUrl;\n    if (url == null || url.isEmpty) {\n      return ColoredBox(color: context.colorScheme.surfaceContainerHighest, child: Center(child: Text('$placeholderIndex')));\n    }\n    return AnimatedImage(image: CachedImageProvider(url, sourceKey: sourceKey));\n  }\n}\n"
chap.write_text(s)
print('repaired interfaces')
