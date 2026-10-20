import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/components/chapter_metadata_line.dart';
import 'package:venera/components/chapter_date_source_button.dart';
import 'package:venera/foundation/chapter_metadata.dart';
import 'package:venera/foundation/comic_details_cache.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';

void main() {
  test('metadata reads per-chapter dates and exact nonnegative integer likes', () {
    final data = ChapterMetadata.parse({'52': {
      'updateTime': '2022-04-23T10:00:00Z', 'likesCount': 21000,
      'likesSource': 'tencent',
    }, '53': {'likesCount': -1}, '54': {'likesCount': 1.5}, 'bad': 'no'});
    expect(data['52']!.displayDate, '22-04-23');
    expect(data['52']!.displayLikes, '2.1万');
    expect(data['53']!.likesCount, isNull);
    expect(data['54']!.likesCount, isNull);
    expect(data.containsKey('bad'), isFalse);
  });
  test('real zero is distinct from missing; timestamps are not synthesized', () {
    expect(const ChapterMetadata(likesCount: 0).displayLikes, '0');
    expect(const ChapterMetadata().displayLikes, isNull);
    expect(const ChapterMetadata().displayDate, isNull);
  });
  test('enrichment merges Tencent likes without overwriting Lizi date', () {
    const base = ChapterMetadata(updateTime: '2026-01-17T11:13:30.812Z');
    final merged = base.merge(const ChapterMetadata(likesCount: 23000, likesSource: 'tencent'));
    expect(merged.updateTime, base.updateTime);
    expect(merged.displayLikes, '2.3万');
  });
  test('details disk cache preserves chapter covers and metadata by explicit id', () {
    final details = ComicDetails.fromJson({'title': 'Test', 'cover': 'cover',
      'tags': <String,dynamic>{}, 'sourceKey': 'test', 'comicId': '1',
      'chapters': {'52': '050 制造罪名', '53': '051 捣蛋鬼'},
      'chapterCovers': {'52': 'first.jpg'},
      'chapterMetadata': {'52': {'updateTime': '2022-04-23', 'likesCount': 21000}},
    });
    final restored = ComicDetails.fromJson(ComicDetailsCache.encode(details));
    expect(restored.chapterMetadata['52']!.displayDate, '22-04-23');
    expect(restored.chapterMetadata['52']!.likesCount, isNull);
    expect(restored.chapterMetadata.containsKey('53'), isFalse);
    expect(restored.chapterCovers!['52'], 'first.jpg');
    final jsonRestored = ComicDetails.fromJson({...details.toJson(), 'subtitle': null});
    expect(jsonRestored.chapterMetadata['52']!.likesCount, isNull);
  });
  for (final theme in [ThemeData.light(), ThemeData.dark()]) {
    testWidgets('chapter facts visible under cover without overflow ${theme.brightness}', (tester) async {
      await tester.pumpWidget(MaterialApp(theme: theme, home: const Scaffold(
        body: SizedBox(width: 180, child: ChapterMetadataLine(metadata: ChapterMetadata(
          updateTime: '2022-04-23', likesCount: 21000, likesSource: 'tencent'))))));
      expect(find.text('22-04-23'), findsOneWidget);
      expect(find.text('2.1万'), findsOneWidget);
      expect(find.byIcon(Icons.thumb_up_outlined), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('missing likes renders unknown instead of fabricated zero', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox(width: 150,
      child: ChapterMetadataLine(metadata: ChapterMetadata(updateTime: '2026-01-17'))))));
    expect(find.text('暂无'), findsOneWidget);
    expect(find.text('0'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('date selector offers Lizi and Tencent and reports selection', (tester) async {
    var selected = 'lizi';
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ChapterDateSourceButton(
      value: selected, onChanged: (value) => selected = value))));
    await tester.tap(find.byKey(const ValueKey('chapter-date-source')));
    await tester.pumpAndSettle();
    expect(find.text('栗子日期'), findsOneWidget);
    expect(find.text('腾讯发布日期'), findsOneWidget);
    await tester.tap(find.text('腾讯发布日期'));
    await tester.pumpAndSettle();
    expect(selected, 'tencent');
    expect(tester.takeException(), isNull);
  });
  test('Tencent date can persist independently, fresh likes never serialize', () {
    const data = ChapterMetadata(updateTime: '2026-01-17', tencentUpdateTime: '2022-04-23', likesCount: 4);
    final datesOnly = ChapterMetadata.fromJson(data.toJson(includeLikes: false));
    expect(datesOnly.updateTime, '2026-01-17');
    expect(datesOnly.tencentUpdateTime, '2022-04-23');
    expect(datesOnly.likesCount, isNull);
  });

}
