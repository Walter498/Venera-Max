import 'package:flutter/material.dart';
import 'package:venera/components/components.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/comic_collection_store.dart';
import 'package:venera/foundation/favorites.dart';
import 'package:venera/foundation/image_provider/cached_image.dart';
import 'package:venera/foundation/lizi_community.dart';
import 'package:venera/pages/comic_details_page/comic_page.dart';
import 'package:venera/pages/community/post_detail_page.dart';
import 'package:venera/utils/user_error.dart';

const _kSections = <List<Object?>>[
  [null, '推薦'],
  [3, '日常'],
  [2, '求書'],
  [1, '分享'],
];

class CommunityPage extends StatefulWidget {
  const CommunityPage({super.key});

  @override
  State<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends State<CommunityPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs =
      TabController(length: _kSections.length, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: Appbar(title: Text('社區')),
      body: Column(children: [
        TabBar(
          controller: _tabs,
          tabs: [for (final s in _kSections) Tab(text: s[1] as String)],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              for (final s in _kSections)
                PostListView(sectionId: s[0] as int?),
            ],
          ),
        ),
      ]),
    );
  }
}

class PostListView extends StatefulWidget {
  const PostListView({super.key, required this.sectionId});

  /// null = 推薦 (all sections).
  final int? sectionId;

  @override
  State<PostListView> createState() => _PostListViewState();
}

class _PostListViewState extends State<PostListView> {
  final List<LiziCommunityPost> _posts = [];
  final ScrollController _scroll = ScrollController();
  int _sortType = 0;
  int _page = 0;
  bool _loading = false;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) {
        _loadMore();
      }
    });
    _refresh();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _posts.clear();
      _page = 0;
      _hasMore = true;
      _error = null;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    try {
      final res = await LiziCommunityApi.fetchPosts(
        sectionId: widget.sectionId,
        page: _page + 1,
        sortType: _sortType,
      );
      if (!mounted) return;
      setState(() {
        _posts.addAll(res.items);
        _page++;
        _hasMore = res.hasMore;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = userFacingNetworkError(e);
          _loading = false;
        });
      }
    }
  }

  Future<void> _openCreatePost() async {
    var section = widget.sectionId ?? 3;
    int? comicId;
    String? comicName;
    String? collectionId;
    String? collectionName;
    final field = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('發布帖子'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Wrap(spacing: 8, children: [
                for (final s in _kSections)
                  ChoiceChip(
                    label: Text(s[1] as String),
                    selected: section == s[0],
                    onSelected: (_) => setDialog(() => section = s[0] as int),
                  ),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.menu_book_outlined, size: 18),
                    label: Text(comicName ?? '添加漫畫',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    onPressed: () async {
                      final picked = await _pickFavoriteComic();
                      if (picked == null) return;
                      final id = int.tryParse(picked.id);
                      if (id == null) {
                        context.showMessage(message: '這個漫畫沒有數字 id，無法關聯');
                        return;
                      }
                      setDialog(() {
                        comicId = id;
                        comicName = picked.name;
                        collectionId = null;
                        collectionName = null;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon:
                        const Icon(Icons.collections_bookmark_outlined, size: 18),
                    label: Text(collectionName ?? '添加漫單',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    onPressed: () async {
                      final picked = await _pickCollection();
                      if (picked == null) return;
                      setDialog(() {
                        collectionId = picked.$1;
                        collectionName = picked.$2;
                        comicId = null;
                        comicName = null;
                      });
                    },
                  ),
                ),
              ]),
              TextField(
                controller: field,
                maxLines: 5,
                maxLength: 512,
                decoration: const InputDecoration(hintText: '分享你的想法…'),
              ),
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('發布'),
            ),
          ],
        ),
      ),
    );
    if (created != true || field.text.trim().isEmpty) return;
    try {
      await LiziCommunityApi.createPost(
        sectionId: section,
        content: field.text.trim(),
        comicId: comicId,
        collectionId: collectionId,
      );
      if (mounted) await _refresh();
    } catch (e) {
      if (mounted) context.showMessage(message: userFacingNetworkError(e));
    }
  }

  Future<FavoriteItem?> _pickFavoriteComic() async {
    final items = LocalFavoritesManager().getAllComics();
    if (items.isEmpty) {
      context.showMessage(message: '收藏是空的');
      return null;
    }
    return showDialog<FavoriteItem>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('選擇漫畫（${items.length}）'),
        content: SizedBox(
          width: 420,
          height: context.height * 0.7,
          child: ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, i) {
              final item = items[i];
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image(
                    image: CachedImageProvider(item.coverPath,
                        sourceKey: item.type.sourceKey, cid: item.id),
                    width: 48,
                    height: 64,
                    fit: BoxFit.cover,
                    errorBuilder: (c, e, st) => Container(
                      width: 48,
                      height: 64,
                      color: context.colorScheme.surfaceContainerHighest,
                    ),
                  ),
                ),
                title: Text(item.name,
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (item.author.trim().isNotEmpty)
                      Text(item.author,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (item.tags.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            for (final tag in item.tags.take(5))
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: context.colorScheme.surfaceContainerHigh,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(tag,
                                    style: const TextStyle(fontSize: 11)),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
                onTap: () => Navigator.pop(dialog, item),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  Future<(String, String)?> _pickCollection() async {
    final collections = ComicCollectionStore.all();
    if (collections.isEmpty) {
      context.showMessage(message: '沒有漫單');
      return null;
    }
    return showDialog<(String, String)>(
      context: context,
      builder: (dialog) => SimpleDialog(
        title: const Text('選擇漫單'),
        children: [
          for (final c in collections)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialog, (c.id, c.name)),
              child: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null && _posts.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('載入失敗：$_error'),
          const SizedBox(height: 12),
          FilledButton(onPressed: _refresh, child: const Text('重試')),
        ]),
      );
    }
    if (_posts.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: _openCreatePost,
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.all(8),
          itemCount: _posts.length + 2,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Row(children: [
                for (final entry in const <List<Object>>[
                  [0, '最新'],
                  [1, '最熱'],
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(entry[1] as String),
                      selected: _sortType == entry[0],
                      onSelected: (_) {
                        setState(() => _sortType = entry[0] as int);
                        _refresh();
                      },
                    ),
                  ),
              ]);
            }
            index--;
            if (index == _posts.length) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: _hasMore
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('沒有更多了'),
                ),
              );
            }
            return PostCard(post: _posts[index]);
          },
        ),
      ),
    );
  }
}

class PostCard extends StatelessWidget {
  const PostCard({super.key, required this.post});

  final LiziCommunityPost post;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.to(
            () => PostDetailPage(postId: post.id, initial: post)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                CircleAvatar(
                  radius: 14,
                  child: Text(post.nickname.isEmpty ? '?' : post.nickname[0],
                      style: const TextStyle(fontSize: 12)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(post.nickname,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                ),
                Text(liziRelativeTime(post.createdAt),
                    style: TextStyle(
                        fontSize: 11, color: context.colorScheme.outline)),
              ]),
              const SizedBox(height: 8),
              Text(post.content, maxLines: 5, overflow: TextOverflow.ellipsis),
              if (post.comics.isNotEmpty) ...[
                const SizedBox(height: 8),
                SizedBox(
                  height: 96,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: post.comics.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, i) {
                      final c = post.comics[i];
                      return Column(children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image(
                            image: CachedImageProvider(c.cover, sourceKey: 'lizimh', cid: '${c.id}'),
                            width: 64,
                            height: 64,
                            fit: BoxFit.cover,
                          ),
                        ),
                        SizedBox(
                          width: 64,
                          child: Text(c.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 10)),
                        ),
                      ]);
                    },
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Row(children: [
                Icon(Icons.visibility_outlined,
                    size: 14, color: context.colorScheme.outline),
                const SizedBox(width: 4),
                Text('${post.viewCount}',
                    style: TextStyle(
                        fontSize: 11, color: context.colorScheme.outline)),
                const SizedBox(width: 12),
                Icon(Icons.chat_bubble_outline,
                    size: 14, color: context.colorScheme.outline),
                const SizedBox(width: 4),
                Text('${post.commentCount}',
                    style: TextStyle(
                        fontSize: 11, color: context.colorScheme.outline)),
                const SizedBox(width: 12),
                Icon(
                  post.isLiked ? Icons.favorite : Icons.favorite_border,
                  size: 14,
                  color: post.isLiked
                      ? context.colorScheme.primary
                      : context.colorScheme.outline,
                ),
                const SizedBox(width: 4),
                Text('${post.likeCount}',
                    style: TextStyle(
                        fontSize: 11, color: context.colorScheme.outline)),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
