import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/components/chapter_grid_locator.dart';

class _LocateHost extends StatefulWidget {
  const _LocateHost({required this.cover, required this.reverse});
  final bool cover;
  final bool reverse;
  @override
  State<_LocateHost> createState() => _LocateHostState();
}

class _LocateHostState extends State<_LocateHost> {
  final scroll = ScrollController();
  final grid = GlobalKey();
  final section = GlobalKey();
  bool expanded = false;
  bool? result;
  int taps = 0;
  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }
  Future<void> locate() async {
    taps++;
    setState(() => expanded = true);
    // A custom order, followed by reverse display, must still address raw 350.
    final order = [for (var i = 0; i < 500; i++) (i + 117) % 500];
    if (widget.reverse) order.setAll(0, order.reversed.toList());
    result = await revealChapterGrid(
      gridKey: grid, sectionKey: section, controller: scroll,
      slot: order.indexOf(350), topInset: 16, isActive: () => mounted,
    );
  }
  @override
  Widget build(BuildContext context) {
    final order = [for (var i = 0; i < 500; i++) (i + 117) % 500];
    if (widget.reverse) order.setAll(0, order.reversed.toList());
    return Scaffold(
      appBar: AppBar(actions: [TextButton(onPressed: locate,
        child: const Text('Locate'))]),
      body: CustomScrollView(controller: scroll, slivers: [
        const SliverToBoxAdapter(child: SizedBox(height: 2400)),
        SliverLayoutBuilder(key: section, builder: (context, constraints) =>
          SliverMainAxisGroup(slivers: [
            const SliverToBoxAdapter(child: SizedBox(height: 120)),
            if (!expanded && widget.cover)
              const SliverToBoxAdapter(child: SizedBox(height: 360))
            else
              SliverPadding(padding: const EdgeInsets.symmetric(horizontal: 12),
                sliver: SliverGrid(key: grid,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: widget.cover ? 4 : 2,
                    mainAxisExtent: widget.cover ? 160 : 60),
                  delegate: SliverChildBuilderDelegate((_, i) =>
                    Center(child: Text('Raw chapter ${order[i]}')),
                    childCount: expanded ? 500 : 16))),
          ])),
        const SliverToBoxAdapter(child: SizedBox(height: 300)),
      ]),
    );
  }
}

void main() {
  for (final cover in [false, true]) {
    for (final reverse in [false, true]) {
      testWidgets('one click reveals distant ${cover ? "cover" : "text"} '
          'chapter with custom order, reverse=$reverse', (tester) async {
        await tester.pumpWidget(MaterialApp(home:
          _LocateHost(cover: cover, reverse: reverse)));
        expect(find.text('Raw chapter 350'), findsNothing);
        await tester.tap(find.text('Locate'));
        await tester.pumpAndSettle();
        final state = tester.state<_LocateHostState>(find.byType(_LocateHost));
        expect(state.taps, 1);
        expect(state.result, isTrue);
        expect(find.text('Raw chapter 350').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
  testWidgets('obsolete locate is cancelled without using detached render tree',
      (tester) async {
    final scroll = ScrollController();
    var active = true;
    await tester.pumpWidget(MaterialApp(home: CustomScrollView(
      controller: scroll, slivers: const [SliverToBoxAdapter(
        child: SizedBox(height: 1000))])));
    final result = revealChapterGrid(gridKey: GlobalKey(),
      sectionKey: GlobalKey(), controller: scroll, slot: 1, topInset: 0,
      isActive: () => active);
    active = false;
    await tester.pump();
    expect(await result, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    scroll.dispose();
    expect(tester.takeException(), isNull);
  });
}
