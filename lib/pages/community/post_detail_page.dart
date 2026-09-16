import 'package:flutter/material.dart';
import 'package:venera/components/components.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/lizi_community.dart';
import 'package:venera/pages/comic_details_page/comic_page.dart';

/// 栗子社區帖子詳情（第一期：只讀；點讚/評論等互動屬於第二期登入功能）。
class PostDetailPage extends StatefulWidget {
  final int postId;
  final LiziCommunityPost? initial;
  const PostDetailPage({super.key, required this.postId, this.initial});

  @override
  State<PostDetailPage> createState() => _PostDetailPageState();
}

class _PostDetailPageState extends State<PostDetailPage> {
  LiziCommunityPost? _post;
  final List<LiziCommunityComment> _comments = [];
  bool _commentsHasMore = false;
  int _commentPage = 0;
  bool _loadingComments = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _post = widget.initial;
    _load();
  }

  Future<void> _load() async {
    try {
      final detail = await LiziCommunityApi.fetchPostDetail(widget.postId);
      if (mounted) setState(() => _post = detail);
    } catch (_) {
      // 詳情失敗就用列表傳進來的資料，不阻塞
    }
    await _loadComments();
  }

  Future<void> _loadComments() async {
    if (_loadingComments) return;
    _loadingComments = true;
    try {
      final res = await LiziCommunityApi.fetchComments(
        widget.postId,
        page: _commentPage + 1,
      );
      if (!mounted) return;
      setState(() {
        _comments.addAll(res.items);
        _commentsHasMore = res.hasMore;
        _commentPage++;
      });
    } catch (e) {
      if (mounted && _comments.isEmpty) {
        setState(() => _error = e.toString());
      }
    } finally {
      _loadingComments = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final post = _post;
    return Scaffold(
      appBar: Appbar(title: Text(post?.sectionName ?? '帖子')),
      body: post == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _buildHeader(context, post),
                const SizedBox(height: 12),
                SelectableText(post.content,
                    style: const TextStyle(fontSize: 15, height: 1.5)),
                if (post.comics.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _buildComics(context, post),
                ],
                const SizedBox(height: 16),
                const Divider(),
                _buildCommentHeader(context),
                if (_error != null && _comments.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text('評論載入失敗：$_error',
                        style: TextStyle(color: context.colorScheme.outline)),
                  ),
                ..._buildCommentTree(context),
                if (_commentsHasMore)
                  TextButton(
                    onPressed: _loadingComments ? null : _loadComments,
                    child: const Text('載入更多評論'),
                  ),
              ],
            ),
    );
  }

  Widget _buildHeader(BuildContext context, LiziCommunityPost post) {
    return Row(children: [
      CircleAvatar(
        child: Text(post.nickname.isEmpty ? '?' : post.nickname[0]),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(post.nickname,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(liziRelativeTime(post.createdAt),
              style: TextStyle(
                  fontSize: 12, color: context.colorScheme.outline)),
        ]),
      ),
      Icon(Icons.favorite_border,
          size: 16, color: context.colorScheme.outline),
      const SizedBox(width: 4),
      Text('${post.likeCount}'),
      const SizedBox(width: 12),
      Icon(Icons.visibility_outlined,
          size: 16, color: context.colorScheme.outline),
      const SizedBox(width: 4),
      Text('${post.viewCount}'),
    ]);
  }

  Widget _buildComics(BuildContext context, LiziCommunityPost post) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('相關漫畫',
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: context.colorScheme.primary)),
      const SizedBox(height: 8),
      for (final c in post.comics)
        Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image(
                image: CachedImageProvider(
                  c.cover,
                  sourceKey: 'lizimh',
                  cid: c.id.toString(),
                ),
                width: 42,
                height: 56,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 42,
                  height: 56,
                  color: context.colorScheme.surfaceContainerHighest,
                  child: const Icon(Icons.book, size: 18),
                ),
              ),
            ),
            title: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: c.author.isEmpty
                ? null
                : Text(c.author,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => to(() => ComicPage(
                  id: c.id.toString(),
                  sourceKey: 'lizimh',
                  cover: c.cover,
                  title: c.name,
                )),
          ),
        ),
    ]);
  }

  Widget _buildCommentHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text('評論（${_post?.commentCount ?? _comments.length}）',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
    );
  }

  /// 樓中樓：頂層評論 + 縮進回覆
  List<Widget> _buildCommentTree(BuildContext context) {
    final byId = {for (final c in _comments) c.id: c};
    final top = _comments.where((c) => c.parentId == null).toList();
    final widgets = <Widget>[];
    for (final c in top) {
      widgets.add(_commentTile(context, c, indent: 0));
      // 回覆（可能多層，這裡全部平鋪在頂層評論下，保持簡潔）
      void addReplies(int parentId, int depth) {
        for (final r
            in _comments.where((e) => e.parentId == parentId)) {
          widgets.add(_commentTile(context, r,
              indent: depth, byId: byId));
          if (depth < 3) addReplies(r.id, depth + 1);
        }
      }
      addReplies(c.id, 1);
    }
    if (widgets.isEmpty && _error == null) {
      widgets.add(Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text('還沒有評論',
              style: TextStyle(color: context.colorScheme.outline)),
        ),
      ));
    }
    return widgets;
  }

  Widget _commentTile(BuildContext context, LiziCommunityComment c,
      {int indent = 0, Map<int, LiziCommunityComment>? byId}) {
    String? replyTo;
    if (c.replyToUserId != null && byId != null) {
      for (final other in byId.values) {
        if (other.userId == c.replyToUserId && other.id != c.id) {
          replyTo = other.nickname;
          break;
        }
      }
    }
    return Padding(
      padding: EdgeInsets.only(left: indent * 20.0, top: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CircleAvatar(
          radius: indent == 0 ? 15 : 12,
          child: Text(c.nickname.isEmpty ? '?' : c.nickname[0],
              style: TextStyle(fontSize: indent == 0 ? 12 : 10)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(
                child: Text(c.nickname,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: context.colorScheme.outline)),
              ),
              const SizedBox(width: 8),
              Text(liziRelativeTime(c.createdAt),
                  style: TextStyle(
                      fontSize: 11, color: context.colorScheme.outline)),
            ]),
            if (replyTo != null)
              Text('回覆 @$replyTo',
                  style: TextStyle(
                      fontSize: 11, color: context.colorScheme.primary)),
            const SizedBox(height: 2),
            Text(c.content),
            if (c.likeCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(children: [
                  Icon(Icons.favorite_border,
                      size: 12, color: context.colorScheme.outline),
                  const SizedBox(width: 3),
                  Text('${c.likeCount}',
                      style: TextStyle(
                          fontSize: 11,
                          color: context.colorScheme.outline)),
                ]),
              ),
          ]),
        ),
      ]),
    );
  }
}
