import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/res.dart';

Comment commentFixture(String id, {String? avatar, int? score = 12,
  int? replies = 2, bool preview = true}) => Comment.fromJson({
  'id': id, 'userName': 'A thoughtful reader with a long nickname',
  'content': 'A real comment with protocol [em]unknown[/em] preserved.\nThe chapter ending was wonderful.',
  'time': '3年前', 'avatar': avatar, 'score': score, 'replyCount': replies,
  if (preview) 'replyPreview': {'id': '$id-preview', 'userName': 'Reply author',
    'content': 'A genuine preview, separate from the parent text.', 'time':'2026-10-14'},
});

ComicSource commentsSource({CommentsLoader? legacy, CommentsOptionsLoader? options,
  CommentCapabilities? capabilities, ChapterCommentsLoader? chapterLegacy,
  CommentsOptionsLoader? chapterOptions, CommentCapabilities? chapterCapabilities}) => ComicSource(
  'Fixture', 'comments_fixture', null, null, null, null, const [], null,
  null, null, null, null, null, null, '', '', '1.0',
  legacy, null, chapterLegacy, null, null, null, null,
  null, null, null, null, null, false, false, null, null,
  commentCapabilities: capabilities, commentsOptionsLoader: options,
  chapterCommentCapabilities: chapterCapabilities, chapterCommentsOptionsLoader: chapterOptions);

ComicDetails commentsDetails() => ComicDetails.fromJson({
  'title': 'Fixture work', 'cover': '', 'tags': <String,List<String>>{},
  'sourceKey': 'comments_fixture', 'comicId': 'work', 'subId':'sub',
});

Future<Res<List<Comment>>> fixturePage(int page) async =>
  Res([commentFixture('topic-$page')], subData: 2, total: 2);
