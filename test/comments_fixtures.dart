import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/utils/translations.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/res.dart';

// Each test file runs in its own isolate. Load the real bundled translations
// once per isolate, before any production widget or translated legacy layout.
// Keep App.isInitialized false: App.init also boots unrelated device plugins.
Future<void>? _commentsTranslations;

Future<void> initCommentsTestHost() =>
    _commentsTranslations ??= _initializeCommentsHost();

Future<void> _initializeCommentsHost() async {
  await AppTranslation.init();
  await _loadCommentsFonts();
}

// Test-only fonts. Never copy Apple system fonts into assets or the repository.
// The macos-15 runner supplies these public files; another host must explicitly
// provide equivalent real fonts via these paths, rather than silently use Ahem.
Future<void> _loadCommentsFonts() async {
  Future<Uint8List> readFont(String role, String variable,
      List<String> candidates) async {
    final override = Platform.environment[variable];
    final paths = override == null ? candidates : [override];
    for (final path in paths) {
      final file = File(path);
      if (!await file.exists()) {
        continue;
      }
      final bytes = await file.readAsBytes();
      if (bytes.length < 4) {
        throw StateError('Comments $role font is empty or truncated: $path');
      }
      final signature = bytes.take(4).toList();
      if (!(signature[0] == 0 && signature[1] == 1 &&
            signature[2] == 0 && signature[3] == 0) &&
          ascii.decode(signature, allowInvalid: true) != 'OTTO' &&
          ascii.decode(signature, allowInvalid: true) != 'ttcf') {
        throw StateError('Comments $role font is not an SFNT/OTF/TTC: $path');
      }
      // Retained by the JSON test reporter in every isolate. Hash + path + host
      // distinguish changed macOS font versions before approving any baseline.
      debugPrint('COMMENTS_FONT_RECORD ${jsonEncode({
        'role': role, 'path': path, 'bytes': bytes.length,
        'sha256': sha256.convert(bytes).toString(),
        'host': Platform.operatingSystemVersion,
      })}');
      return bytes;
    }
    throw StateError('Missing real comments $role font. Checked: $paths. '
        'Use macos-15 system fonts or set $variable to a licensed local font. '
        'Ahem fallback is not permitted.');
  }

  final cjk = await readFont('CJK', 'COMMENTS_CJK_FONT', const [
    '/System/Library/Fonts/PingFang.ttc',
    '/System/Library/Fonts/Supplemental/PingFang.ttc',
    '/System/Library/Fonts/Hiragino Sans GB.ttc',
    '/System/Library/Fonts/Supplemental/Hiragino Sans GB.ttc',
  ]);
  final latin = await readFont('Latin', 'COMMENTS_LATIN_FONT', const [
    '/System/Library/Fonts/Supplemental/Arial.ttf',
    '/Library/Fonts/Arial.ttf',
  ]);
  Future<void> register(String family, Uint8List bytes) async {
    final loader = FontLoader(family);
    loader.addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
    await loader.load();
  }
  await register('CommentsLatin', latin);
  await register('CommentsCJK', cjk);
  // Also cover default TextStyles and Cupertino/Material defaults in tests
  // that don't install the golden theme. PingFang has Latin and CJK glyphs.
  for (final family in ['Ahem', 'Roboto', 'Arial', 'monospace',
      '.SF UI Text', '.SF UI Display']) {
    await register(family, cjk);
  }
  final icons = FontLoader('MaterialIcons');
  final iconBytes = await rootBundle.load('fonts/MaterialIcons-Regular.otf');
  icons.addFont(Future<ByteData>.value(iconBytes));
  await icons.load();
  debugPrint('COMMENTS_FONT_RECORD ${jsonEncode({
    'role': 'MaterialIcons', 'path': 'fonts/MaterialIcons-Regular.otf',
    'bytes': iconBytes.lengthInBytes,
    'sha256': sha256.convert(iconBytes.buffer.asUint8List(
      iconBytes.offsetInBytes, iconBytes.lengthInBytes)).toString(),
  })}');
}

void setUpCommentsTestHost() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initCommentsTestHost);
  late dynamic previousLanguage;
  setUp(() {
    previousLanguage = appdata.settings['language'];
    appdata.settings['language'] = 'en-US';
  });
  tearDown(() {
    appdata.settings['language'] = previousLanguage;
  });
}

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
