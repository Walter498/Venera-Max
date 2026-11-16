import 'dart:convert';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/lizi_api_client.dart';

/// 栗子漫畫官方社區 API（ai.qsmm.fun）。
///
/// 接口來源：官方 App v1.1.5 (libapp.so) 提取 + 實測驗證。
/// 讀取接口匿名可用；寫接口（發帖/評論/點讚）需要 user/login 的 token，
/// 屬於第二期功能。
///
/// 注意：成功時 code 是 201（不是 200）。
class LiziCommunityApi {
  /// 域名池：官方域名會輪換/被封（ai.qsmm.fun 已被停用 DNS），
  /// 任何一個可用就自動用它並記住（跟漫畫源同一套策略）。
  static const List<String> apiHosts = LiziApiProtocol.hosts;

  static String get api => LiziApiClient.instance.api;

  /// 漫畫封面線路（與栗子源 lizimh.js 的線路1一致）
  static const String imgBase = "https://cdn.lzimg.xyz";

  static List<LiziCommunitySection>? _sectionsCache;

  /// POST through the same hook; needs the user's token, which the source
  /// reads from its own settings, so the app never handles the credential.
  static Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    final hook = ComicSource.find('lizimh')?.apiFetch;
    if (hook == null) throw StateError('此功能需要栗子源 v2.33.13 或以上');
    final res = await hook(path, jsonEncode(body));
    if (res.error) {
      // Show the server's own message: it distinguishes "not logged in" from
      // a rejected body, which an app-side guess cannot.
      throw StateError(res.errorMessage ?? '請求失敗');
    }
    dynamic raw = res.data;
    if (raw is String) raw = jsonDecode(raw);
    if (raw is! Map) throw StateError('回應格式錯誤');
    final data = raw['data'];
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  /// 刪除帖子（伺服器只允許自己的帖子）。
  static Future<bool> deletePost(int postId) async {
    await _postJson('/app/api/community/post/delete', {'id': postId});
    return true;
  }

  /// 刪除評論。
  static Future<bool> deleteComment(int commentId) async {
    await _postJson('/app/api/community/comment/delete', {'id': commentId});
    return true;
  }

  /// 發帖：sectionId + 內容（+ 可選漫畫 id）。
  static Future<bool> createPost({
    required int sectionId,
    required String content,
    int? comicId,
    String? collectionId,
  }) async {
    // A post carries either one attached comic or one collection, never both.
    // Official body: {"section_id":N,"content":"..."} — the 32-byte request in
    // the captured traffic matches this exactly; community_section_id is
    // rejected with 400 请求参数解析失败.
    final body = <String, dynamic>{
      'section_id': sectionId,
      'content': content,
      if (comicId != null) 'comic_ids': [comicId],
      if (collectionId != null) 'comic_collection_id': collectionId,
    };
    await _postJson('/app/api/community/post/create', body);
    return true;
  }

  /// 發評論；[parentId] 非空即為回覆。
  static Future<bool> createComment({
    required int postId,
    required String content,
    int? parentId,
  }) async {
    // The official client always sends parent_id (0 for a top-level comment);
    // omitting it makes the server reject the request.
    await _postJson('/app/api/community/comment/create', {
      'post_id': postId,
      'content': content,
      'parent_id': parentId ?? 0,
    });
    return true;
  }

  /// 點讚 / 取消點讚（帖子）。
  static Future<bool> likePost(int postId, bool like) async {
    await _postJson(
      like ? '/app/api/community/post/like' : '/app/api/community/post/unlike',
      {'id': postId},
    );
    return true;
  }

  /// 點讚 / 取消點讚（評論）。
  static Future<bool> likeComment(int commentId, bool like) async {
    await _postJson(
      like
          ? '/app/api/community/comment/like'
          : '/app/api/community/comment/unlike',
      {'id': commentId},
    );
    return true;
  }

  static Future<Map<String, dynamic>> _getJson(String path) async {
    // Prefer the comic source's own request path: this host accepts it while
    // the app's standalone client can be rejected by the CDN.
    final hook = ComicSource.find('lizimh')?.apiFetch;
    if (hook != null) {
      final res = await hook(path);
      if (!res.error) {
        dynamic raw = res.data;
        try {
          if (raw is String) raw = jsonDecode(raw);
        } catch (_) {
          raw = null;
        }
        if (raw is Map) {
          final code = raw['code'];
          if (code == 201 || code == 200) {
            final data = raw['data'];
            return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
          }
          throw StateError('栗子接口回傳 code=$code');
        }
      }
    }
    return LiziApiClient.instance.getJson(path);
  }

  /// 社區版塊（來自 configv2 的 cfg_general.community_sections）
  static Future<List<LiziCommunitySection>> fetchSections() async {
    if (_sectionsCache != null) return _sectionsCache!;
    try {
      final cfg = await _getJson('/app/api/configv2');
      final general = cfg['cfg_general'];
      if (general is Map && general['community_sections'] is List) {
        var list = (general['community_sections'] as List)
            .map((e) => LiziCommunitySection.fromJson(e))
            .toList();
        list.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
        if (list.isNotEmpty) return _sectionsCache = list;
      }
    } catch (_) {}
    // 後備：與 2026-09 實測一致的固定版塊
    return _sectionsCache = const [
      LiziCommunitySection(id: 3, name: '日常', sortOrder: 1),
      LiziCommunitySection(id: 2, name: '求書', sortOrder: 2),
      LiziCommunitySection(id: 1, name: '分享', sortOrder: 3),
    ];
  }

  /// 帖子流。sectionId 為 null 時抓全部版塊。
  static Future<LiziListPage<LiziCommunityPost>> fetchPosts({
    int? sectionId,
    int page = 1,
    int sortType = 0,
  }) async {
    // 0 = 最新, 1 = 最熱 (official client's sort_type).
    final qs = sectionId == null
        ? '?page=$page&page_size=20&sort_type=$sortType'
        : '?section_id=$sectionId&page=$page&page_size=20&sort_type=$sortType';
    final data = await _getJson('/app/api/community/posts$qs');
    final list = (data['list'] is List ? data['list'] as List : const [])
        .map((e) => LiziCommunityPost.fromJson(e))
        .toList();
    return LiziListPage(items: list, hasMore: data['has_more'] == true);
  }

  static Future<LiziCommunityPost> fetchPostDetail(int id) async {
    final data = await _getJson('/app/api/community/post/detail?id=$id');
    return LiziCommunityPost.fromJson(data);
  }

  static Future<LiziListPage<LiziCommunityComment>> fetchComments(
    int postId, {
    int page = 1,
  }) async {
    final data = await _getJson(
      '/app/api/community/comments?post_id=$postId&page=$page'
      '&page_size=20&sort_type=0',
    );
    final list = (data['list'] is List ? data['list'] as List : const [])
        .map((e) => LiziCommunityComment.fromJson(e))
        .toList();
    return LiziListPage(items: list, hasMore: data['has_more'] == true);
  }
}

class LiziListPage<T> {
  final List<T> items;
  final bool hasMore;
  const LiziListPage({required this.items, required this.hasMore});
}

class LiziCommunitySection {
  final int id;
  final String name;
  final int sortOrder;
  const LiziCommunitySection({
    required this.id,
    required this.name,
    required this.sortOrder,
  });
  factory LiziCommunitySection.fromJson(dynamic json) {
    final m = Map<String, dynamic>.from(json as Map);
    return LiziCommunitySection(
      id: (m['id'] as num?)?.toInt() ?? 0,
      name: m['name']?.toString() ?? '',
      sortOrder: (m['sort_order'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 帖子附帶的漫畫（點了可跳 App 內漫畫詳情）
class LiziPostComic {
  final int id;
  final String name;
  final String author;
  final String cover;
  const LiziPostComic({
    required this.id,
    required this.name,
    required this.author,
    required this.cover,
  });
  factory LiziPostComic.fromJson(dynamic json) {
    final m = Map<String, dynamic>.from(json as Map);
    var cover = (m['picY'] ?? m['picX'] ?? m['cover'] ?? '').toString();
    if (cover.isNotEmpty && !cover.startsWith('http')) {
      cover = LiziCommunityApi.imgBase + cover;
    }
    return LiziPostComic(
      id: (m['id'] as num?)?.toInt() ?? 0,
      name: m['name']?.toString() ?? '',
      author: m['author']?.toString() ?? '',
      cover: cover,
    );
  }
}

class LiziCommunityPost {
  final int id;
  final String content;
  final int sectionId;
  final String sectionName;
  final int likeCount;
  final int commentCount;
  final int viewCount;
  final DateTime? createdAt;
  final int userId;
  final String nickname;
  final List<LiziPostComic> comics;
  final bool isLiked;

  const LiziCommunityPost({
    required this.id,
    required this.content,
    required this.sectionId,
    required this.sectionName,
    required this.likeCount,
    required this.commentCount,
    required this.viewCount,
    required this.createdAt,
    required this.userId,
    required this.nickname,
    required this.comics,
    required this.isLiked,
  });

  factory LiziCommunityPost.fromJson(dynamic json) {
    final m = Map<String, dynamic>.from(json as Map);
    final user = m['comic_user'] is Map
        ? Map<String, dynamic>.from(m['comic_user'] as Map)
        : <String, dynamic>{};
    final section = m['community_section'] is Map
        ? Map<String, dynamic>.from(m['community_section'] as Map)
        : <String, dynamic>{};
    DateTime? time;
    try {
      time = DateTime.parse(m['createdAt'].toString()).toLocal();
    } catch (_) {}
    return LiziCommunityPost(
      id: (m['id'] as num?)?.toInt() ?? 0,
      content: m['content']?.toString() ?? '',
      sectionId: (m['community_section_id'] as num?)?.toInt() ?? 0,
      sectionName: section['name']?.toString() ?? '',
      likeCount: (m['like_count'] as num?)?.toInt() ?? 0,
      commentCount: (m['comment_count'] as num?)?.toInt() ?? 0,
      viewCount: (m['view_count'] as num?)?.toInt() ?? 0,
      createdAt: time,
      userId: (user['id'] as num?)?.toInt() ?? 0,
      nickname: user['NickName']?.toString() ?? '匿名',
      comics: (m['comics'] is List ? m['comics'] as List : const [])
          .map((e) => LiziPostComic.fromJson(e))
          .toList(),
      isLiked: m['is_liked'] == true,
    );
  }
}

class LiziCommunityComment {
  final int id;
  final String content;
  final int? parentId;
  final int? replyToUserId;
  final int likeCount;
  final DateTime? createdAt;
  final int userId;
  final String nickname;

  const LiziCommunityComment({
    required this.id,
    required this.content,
    required this.parentId,
    required this.replyToUserId,
    required this.likeCount,
    required this.createdAt,
    required this.userId,
    required this.nickname,
  });

  factory LiziCommunityComment.fromJson(dynamic json) {
    final m = Map<String, dynamic>.from(json as Map);
    final user = m['comic_user'] is Map
        ? Map<String, dynamic>.from(m['comic_user'] as Map)
        : <String, dynamic>{};
    DateTime? time;
    try {
      time = DateTime.parse(m['createdAt'].toString()).toLocal();
    } catch (_) {}
    return LiziCommunityComment(
      id: (m['id'] as num?)?.toInt() ?? 0,
      content: m['content']?.toString() ?? '',
      parentId: (m['parent_id'] as num?)?.toInt(),
      replyToUserId: (m['reply_to_user_id'] as num?)?.toInt(),
      likeCount: (m['like_count'] as num?)?.toInt() ?? 0,
      createdAt: time,
      userId: (user['id'] as num?)?.toInt() ?? 0,
      nickname: user['NickName']?.toString() ?? '匿名',
    );
  }
}

/// 相對時間（x分鐘前 / x小時前 / x天前）
String liziRelativeTime(DateTime? time) {
  if (time == null) return '';
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return '剛剛';
  if (diff.inHours < 1) return '${diff.inMinutes}分鐘前';
  if (diff.inDays < 1) return '${diff.inHours}小時前';
  if (diff.inDays < 30) return '${diff.inDays}天前';
  return '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}';
}
