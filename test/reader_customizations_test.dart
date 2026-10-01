import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/category_filter_plan.dart';
import 'package:venera/foundation/reader_page_plan.dart';
import 'package:venera/foundation/image_provider/reader_image.dart';

void main() {
  test('RTL spreads retain their original page ordinals', () {
    expect([for (var slot = 0; slot < 2; slot++)
      readerImagePageOrdinal(10, 2, slot, reversed: true)], [12, 11]);
    expect([for (var slot = 0; slot < 3; slot++)
      readerImagePageOrdinal(0, 3, slot, reversed: false)], [1, 2, 3]);
  });
  test('same URL reused by two pages does not alias translated image cache', () {
    const a = ReaderImageProvider('same.jpg', 'demo', 'book', 'chapter', 1,
      translationKey: 'pageTranslation@2@ja>zh@demo@book@chapter@p1@');
    const b = ReaderImageProvider('same.jpg', 'demo', 'book', 'chapter', 2,
      translationKey: 'pageTranslation@2@ja>zh@demo@book@chapter@p2@');
    expect(a.key, isNot(b.key));
  });
  test('current page wins then future pages then prior pages', () {
    final pages = [10, 2, 4, 1, 3];
    pages.sort((a, b) => readerTranslationPriority(a, 3, sameChapter: true)
        .compareTo(readerTranslationPriority(b, 3, sameChapter: true)));
    expect(pages, [3, 4, 10, 2, 1]);
    expect(readerTranslationPriority(1, 3, sameChapter: false),
      greaterThan(readerTranslationPriority(10, 3, sameChapter: true)));
  });

  test('region/status OR, rows AND, tag anchor preserved', () {
    expect(buildCategoryQueries([
      ['class:1', 'class:3'], ['isend:0', 'isend:1'],
    ], tags: ['tag:热血', 'tag:冒险']), [
      'tag:热血|class:1|isend:0', 'tag:热血|class:1|isend:1',
      'tag:热血|class:3|isend:0', 'tag:热血|class:3|isend:1',
    ]);
  });
  test('all/reset does not filter', () {
    expect(buildCategoryQueries([[], []]), [null]);
  });
  test('all selected tags required, not first-page intersection', () {
    expect(matchesAllCategoryTags(['热血', '冒险'], ['tag:热血', 'tag:冒险']), isTrue);
    expect(matchesAllCategoryTags(['热血'], ['tag:热血', 'tag:冒险']), isFalse);
  });
  testWidgets('one short page still accepts drag and overscroll', (tester) async {
    final controller = ScrollController();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: CustomScrollView(
      controller: controller,
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      slivers: const [SliverToBoxAdapter(child: SizedBox(height: 100))],
    ))));
    final metrics = controller.position;
    expect(metrics.minScrollExtent, metrics.maxScrollExtent);
    expect(metrics.physics.shouldAcceptUserOffset(metrics), isTrue);
    expect(metrics.physics.applyBoundaryConditions(metrics, -60), 0);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -180));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('collapsed grid expands and jumps to a distant chapter', (tester) async {
    final controller = ScrollController();
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: CustomScrollView(
      controller: controller,
      slivers: [SliverMainAxisGroup(slivers: [
        const SliverToBoxAdapter(child: SizedBox(height: 700)),
        SliverGrid(key: key,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2, mainAxisExtent: 44),
          delegate: SliverChildBuilderDelegate((_, i) => Text('Chapter $i'), childCount: 500)),
      ])],
    ))));
    final render = key.currentContext!.findRenderObject() as RenderSliverGrid;
    final base = RenderAbstractViewport.of(render).getOffsetToReveal(render, 0).offset;
    final offset = render.gridDelegate.getLayout(render.constraints).getGeometryForChildIndex(350).scrollOffset;
    controller.jumpTo(base + offset);
    await tester.pump();
    expect(find.text('Chapter 350'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
