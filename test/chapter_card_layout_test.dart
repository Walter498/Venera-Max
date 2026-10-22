import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/components/chapter_metadata_line.dart';
import 'package:venera/foundation/chapter_metadata.dart';
import 'comments_fixtures.dart';

const titles = ['686人脉遍布九州的圣子', '685不可化解的矛盾',
  '684搏一搏，单车变摩托', '683交换情报'];
const facts = [
  ChapterMetadata(updateTime: '2026-10-18', likesCount: 1549, likesSource: 'tencent'),
  ChapterMetadata(updateTime: '2026-10-17', likesCount: 1711, likesSource: 'tencent'),
  ChapterMetadata(updateTime: '2026-10-11', likesCount: 2215, likesSource: 'tencent'),
  ChapterMetadata(updateTime: '2026-10-10', likesCount: 1855, likesSource: 'tencent'),
];

void main() {
  setUpCommentsTestHost();
  for (final width in [320.0, 390.0, 430.0]) {
    for (final scale in [1.0, 2.0]) {
      for (final covers in [false, true]) {
        for (final expanded in [false, true]) {
          testWidgets('${covers ? 'four covers' : 'two text columns'} '
              '${expanded ? 'expanded' : 'collapsed'} width=$width scale=$scale', (tester) async {
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = Size(width, 1000);
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final boundary = GlobalKey();
            var tapped = -1;
            await tester.pumpWidget(MaterialApp(theme: ThemeData(
              brightness: Brightness.dark, platform: TargetPlatform.iOS,
              fontFamily: 'CommentsLatin', fontFamilyFallback: const ['CommentsCJK']),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!), home: Scaffold(body: RepaintBoundary(key: boundary,
                  child: CustomScrollView(slivers: [SliverPadding(
                    padding: const EdgeInsets.all(12),
                    sliver: SliverLayoutBuilder(builder: (context, constraints) {
                      final columns = covers ? ChapterCardLayout.coverColumns(constraints.crossAxisExtent) : 2;
                      final cellWidth = (constraints.crossAxisExtent - 8 * (columns - 1)) / columns;
                      final height = covers ? ChapterCardLayout.coverExtent(context, cellWidth)
                          : ChapterCardLayout.textExtent(context);
                      Widget cell(int i) => SizedBox(key: ValueKey('chapter-card-$i'), width: cellWidth, height: height,
                        child: Material(color: covers ? Colors.transparent : const Color(0xff181c1d),
                          borderRadius: BorderRadius.circular(10),
                          child: InkWell(onTap: () => tapped = i,
                            child: covers ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                              Expanded(child: Container(color: const Color(0xff333538),
                                child: const Icon(Icons.image_outlined))),
                              const SizedBox(height: 4),
                              ChapterCoverCaption(title: titles[i], metadata: facts[i]),
                            ]) : Padding(padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: ChapterTextContent(title: titles[i], metadata: facts[i])))));
                      if (!expanded) {
                        return SliverToBoxAdapter(child: Wrap(
                          spacing: 8, runSpacing: 8, children: [for (var i=0;i<4;i++) cell(i)]));
                      }
                      return SliverGrid(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns, mainAxisExtent: height, crossAxisSpacing: 8, mainAxisSpacing: 14),
                        delegate: SliverChildBuilderDelegate((context,i) => cell(i), childCount: 4));
                    }))])))));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            for (final date in ['26-10-18', '26-10-17', '26-10-11', '26-10-10']) {
              expect(find.text(date), findsOneWidget);
            }
            for (final likes in ['1549', '1711', '2215', '1855']) {
              expect(find.text(likes), findsOneWidget);
            }
            // Align card boxes, not glyph bounds: font fallback can shift
            // glyph metrics by fractions of a pixel at 200% text scale.
            final a = tester.getTopLeft(find.byKey(const ValueKey('chapter-card-0')));
            final b = tester.getTopLeft(find.byKey(const ValueKey('chapter-card-1')));
            final c = tester.getTopLeft(find.byKey(const ValueKey('chapter-card-2')));
            Rect paintedRect(Finder finder) {
              final render = tester.renderObject<RenderBox>(finder);
              return MatrixUtils.transformRect(render.getTransformTo(null), render.paintBounds);
            }
            expect(b.dy, closeTo(a.dy, 0.1));
            if (covers) {
              expect(c.dy, closeTo(a.dy, 0.1));
              final title = paintedRect(find.text(titles[0]));
              final date = paintedRect(find.text('26-10-18'));
              final likes = paintedRect(find.text('1549'));
              expect(date.top, greaterThanOrEqualTo(title.bottom));
              expect(likes.top, greaterThanOrEqualTo(date.bottom));
            } else {
              expect(c.dy, greaterThan(a.dy));
            }
            await tester.tap(find.text(titles[2]));
            expect(tapped, 2);
            if (width == 430 && scale == 1 && !expanded) {
              final directory = Platform.environment['RUNNER_TEMP'];
              if (directory != null) {
                await tester.runAsync(() async {
                  final render = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
                  final image = await render.toImage(pixelRatio: 3);
                  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
                  final file = File('$directory/venera-comments-evidence/chapter-${covers ? 'four-covers' : 'two-text'}-260.png');
                  await file.parent.create(recursive: true);
                  await file.writeAsBytes(bytes!.buffer.asUint8List());
                  image.dispose();
                });
              }
            }
            expect(tester.takeException(), isNull);
          });
        }
      }
    }
  }
  test('four columns are stable at phone widths', () {
    for (final width in [296.0, 366.0, 406.0, 528.0]) {
      expect(ChapterCardLayout.coverColumns(width), 4);
    }
  });
  testWidgets('missing and refreshed facts never synthesize zero', (tester) async {
    Future<void> show(ChapterMetadata metadata) => tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SizedBox(width: 82, child: ChapterMetadataLine(
        metadata: metadata, stacked: true)))));
    await show(const ChapterMetadata());
    expect(find.byKey(const ValueKey('chapter-update-date')), findsNothing);
    expect(find.byKey(const ValueKey('chapter-like-count')), findsNothing);
    expect(find.text('日期暂无'), findsNothing);
    expect(find.text('暂无'), findsNothing);
    expect(find.text('0'), findsNothing);
    await show(const ChapterMetadata(updateTime: '2026-10-18', likesCount: 0));
    expect(find.text('0'), findsOneWidget);
    await show(const ChapterMetadata(updateTime: '2026-10-18', likesCount: 1549));
    expect(find.text('1549'), findsOneWidget);
    expect(find.text('0'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
