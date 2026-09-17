import 'package:flutter/material.dart';
import 'package:venera/components/components.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/image_provider/cached_image.dart';
import 'package:venera/foundation/lizi_community.dart';
import 'package:venera/pages/community/post_detail_page.dart';

/// 栗子漫畫社區（第一期：只讀瀏覽）。
/// 資料來源：官方社區 API（ai.qsmm.fun），匿名可讀。
class CommunityPage extends StatefulWidget {
  const CommunityPage({super.key});

  @override
  State<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends State<CommunityPage> {
  List<LiziCommunitySection>? _sections;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final sections = await LiziCommunityApi.fetchSections();
      if (mounted) setState(() => _sections = sections);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('載入失敗：$_error'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () {
                  setState(() {
                    _error = null;
                    _sections = null;
                  });
                  _load();
                },
                child: const Text('重試'),
              ),
            ],
          ),
        ),
      );
    }
    if (_sections == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return DefaultTabController(
      length: _sections!.length,
      child: Scaffold(
        // 無 Appbar：底部 tab 的 chrome 已顯示「社區」標題，
        // 這裡不再放帶返回箭頭的重複列（用戶要求刪除無用按鈕）
        body: Column(
          children: [
            TabBar(
              tabs: [for (final s in _sections!) Tab(text: s.name)],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  for (final s in _sections!)
                    _PostListView(key: PageStorageKey(s.id), sectionId: s.id),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PostListView extends StatefulWidget {
  final int sectionId;
  const _PostListView({super.key, required this.sectionId});

  @override
  State<_PostListView> createState() => _PostListViewState();
}

class _PostListViewState extends State<_PostListView>
    with AutomaticKeepAliveClientMixin {
  final List<LiziCommunityPost> _posts = [];
  int _page = 1;
  bool _hasMore = true;
  bool _loading = false;
  String? _error;
  final _scroll = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _refresh();
    _scroll.addListener(() {
      if (_scroll.position.pixels >
          _scroll.position.maxScrollExtent - 400) {
        _loadMore();
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _page = 1;
      _hasMore = true;
      _error = null;
    });
    await _fetch(1);
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    await _fetch(_page + 1);
  }

  Future<void> _fetch(int page) async {
    if (_loading) return;
    _loading = true;
    try {
      final res = await LiziCommunityApi.fetchPosts(
        sectionId: widget.sectionId,
        page: page,
      );
      if (!mounted) return;
      setState(() {
        if (page == 1) _posts.clear();
        _posts.addAll(res.items);
        _hasMore = res.hasMore;
        _page = page;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      _loading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_posts.isEmpty) {
      if (_error != null) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('載入失敗：$_error'),
              const SizedBox(height: 12),
              FilledButton(onPressed: _refresh, child: const Text('重試')),
            ],
          ),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.all(8),
        itemCount: _posts.length + 1,
        itemBuilder: (context, index) {
          if (index == _posts.length) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: _hasMore
                    ? (_loading
                        ? const CircularProgressIndicator()
                        : const SizedBox.shrink())
                    : Text('沒有更多了',
                        style: TextStyle(
                            color: context.colorScheme.outline, fontSize: 12)),
              ),
            );
          }
          return _PostCard(post: _posts[index]);
        },
      ),
    );
  }
}

class _PostCard extends StatelessWidget {
  final LiziCommunityPost post;
  const _PostCard({required this.post});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.to(() => PostDetailPage(postId: post.id, initial: post)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                CircleAvatar(
                  radius: 14,
                  child: Text(
                    post.nickname.isEmpty ? '?' : post.nickname[0],
                    style: const TextStyle(fontSize: 12),
                  ),
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
              Text(post.content,
                  maxLines: 5, overflow: TextOverflow.ellipsis),
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
                            image: CachedImageProvider(
                              c.cover,
                              sourceKey: 'lizimh',
                              cid: c.id.toString(),
                            ),
                            width: 56,
                            height: 72,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: 56,
                              height: 72,
                              color: context.colorScheme.surfaceContainerHighest,
                              child: const Icon(Icons.broken_image, size: 18),
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        SizedBox(
                          width: 60,
                          child: Text(c.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 10)),
                        ),
                      ]);
                    },
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Row(children: [
                Icon(Icons.favorite_border,
                    size: 15, color: context.colorScheme.outline),
                const SizedBox(width: 3),
                Text('${post.likeCount}', style: _statStyle(context)),
                const SizedBox(width: 16),
                Icon(Icons.mode_comment_outlined,
                    size: 15, color: context.colorScheme.outline),
                const SizedBox(width: 3),
                Text('${post.commentCount}', style: _statStyle(context)),
                const SizedBox(width: 16),
                Icon(Icons.visibility_outlined,
                    size: 15, color: context.colorScheme.outline),
                const SizedBox(width: 3),
                Text('${post.viewCount}', style: _statStyle(context)),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  TextStyle _statStyle(BuildContext context) =>
      TextStyle(fontSize: 12, color: context.colorScheme.outline);
}
