import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/pages/reader/reader_chrome.dart';

const _duration = Duration(milliseconds: 200);

void main() {
  for (final fromTop in [true, false]) {
    for (final height in [56.0, 180.0]) {
      testWidgets(
        '${fromTop ? 'top' : 'bottom'} $height card fully hides and restores',
        (tester) async {
          final semantics = tester.ensureSemantics();
          var visible = false;
          var pageTaps = 0;
          var controlTaps = 0;
          late StateSetter setHostState;
          final control = fromTop ? 'top control' : 'bottom control';
          await tester.pumpWidget(
            MaterialApp(
              home: StatefulBuilder(
                builder: (context, setState) {
                  setHostState = setState;
                  return Scaffold(
                    body: Stack(
                      children: [
                        Positioned.fill(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => pageTaps++,
                            child: const ColoredBox(color: Colors.white),
                          ),
                        ),
                        Positioned(
                          // Reproduce the safe-area gap which defeated a
                          // one-card-height slide in the original reader.
                          top: fromTop ? 76 : null,
                          bottom: fromTop ? null : 46,
                          left: 12,
                          right: 12,
                          child: ReaderChromeVisibility(
                            visible: visible,
                            fromTop: fromTop,
                            duration: _duration,
                            child: SizedBox(
                              height: height,
                              child: TextButton(
                                onPressed: () => controlTaps++,
                                child: Text(control),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          );
          expect(find.text(control), findsNothing);
          expect(find.text(control, skipOffstage: false), findsOneWidget);
          expect(find.bySemanticsLabel(control), findsNothing);

          setHostState(() => visible = true);
          await tester.pumpAndSettle();
          expect(find.text(control).hitTestable(), findsOneWidget);
          final openRect = tester.getRect(find.byType(TextButton));
          await tester.tap(find.text(control));
          expect(controlTaps, 1);

          setHostState(() => visible = false);
          await tester.pump();
          // Even during the closing animation, taps go to the page.
          await tester.tapAt(openRect.center);
          expect(pageTaps, 1);
          expect(controlTaps, 1);
          expect(find.bySemanticsLabel(control), findsNothing);
          await tester.pumpAndSettle();
          expect(find.text(control), findsNothing);
          final offstage = tester.widget<Offstage>(
            find.descendant(
              of: find.byType(ReaderChromeVisibility),
              matching: find.byType(Offstage, skipOffstage: false),
              skipOffstage: false,
            ),
          );
          expect(offstage.offstage, isTrue);

          // A rapid reversal must not strand a half-collapsed card.
          setHostState(() => visible = true);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 70));
          setHostState(() => visible = false);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 30));
          setHostState(() => visible = true);
          await tester.pumpAndSettle();
          expect(tester.getRect(find.byType(TextButton)), openRect);
          expect(find.text(control).hitTestable(), findsOneWidget);
          await tester.tap(find.text(control));
          expect(controlTaps, 2);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          semantics.dispose();
        },
      );
    }
  }

  test('blur starts clear and increases smoothly without overshoot', () {
    expect(ReaderBottomGlass.sigmaAt(0, 24), 0);
    expect(ReaderBottomGlass.sigmaAt(0.2, 24), 0);
    expect(ReaderBottomGlass.sigmaAt(1, 24), 24);
    expect(ReaderBottomGlass.sigmaAt(-1, 24), 0);
    expect(ReaderBottomGlass.sigmaAt(2, 24), 24);
    var previous = 0.0;
    for (var i = 0; i <= 100; i++) {
      final sigma = ReaderBottomGlass.sigmaAt(i / 100, 24);
      expect(sigma, inInclusiveRange(previous, 24.0));
      previous = sigma;
    }
  });

  testWidgets('bottom glass stays rounded, inset and transparent at the top', (
    tester,
  ) async {
    const radius = BorderRadius.all(Radius.circular(18));
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 340,
              child: ReaderBottomGlass(
                borderRadius: radius,
                surfaceColor: Colors.white,
                borderColor: Colors.grey,
                blurSigma: 24,
                child: SizedBox(height: 160, child: Text('controls')),
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(ReaderBottomGlass)), const Size(340, 160));
    expect(tester.widget<ClipRRect>(find.byType(ClipRRect)).borderRadius, radius);
    expect(find.text('controls'), findsOneWidget);
    // The top quarter has no backdrop filter at all, not merely a clear tint.
    for (var i = 0; i < 4; i++) {
      expect(find.byKey(ValueKey('reader-bottom-blur-band-$i')), findsNothing);
    }
    expect(find.byType(BackdropFilter), findsNWidgets(12));
    expect(find.byType(BackdropGroup), findsOneWidget);
    final decorations = tester.widgetList<DecoratedBox>(
      find.descendant(
        of: find.byType(ReaderBottomGlass),
        matching: find.byType(DecoratedBox),
      ),
    );
    for (final widget in decorations) {
      final box = widget.decoration as BoxDecoration;
      expect(box.color, isNull); // no opaque base material
      final gradient = box.gradient! as LinearGradient;
      expect(gradient.colors.first.a, 0);
      expect(gradient.colors.last.a, lessThanOrEqualTo(0.31));
    }
    expect(tester.takeException(), isNull);
  });

  test('reader uses only one glyph layer for chapter, clock and battery', () {
    final scaffold = File('lib/pages/reader/scaffold.dart').readAsStringSync();
    expect(scaffold, isNot(contains('PaintingStyle.stroke')));
    expect(scaffold, contains('color: context.colorScheme.onInverseSurface'));
    expect(scaffold, contains("Text('\$batteryLevel%',"));
    expect(scaffold, contains('if (!_isOpen && !isOnChapterCommentsPage)'));
    expect(RegExp(r'child: ReaderChromeVisibility\(').allMatches(scaffold).length, 3);
    expect(scaffold, contains('return ReaderBottomGlass('));
  });
}
