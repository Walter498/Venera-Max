import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/pages/reader/reader.dart';
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
          await tester.pumpAndSettle();
          expect(find.text(control), findsNothing);
          expect(find.bySemanticsLabel(control), findsNothing);
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

  test('uses one continuous light backdrop blur without overshoot', () {
    expect(ReaderBottomGlass.backdropSigma(0), 0);
    expect(ReaderBottomGlass.backdropSigma(-1), 0);
    expect(ReaderBottomGlass.backdropSigma(24), closeTo(6.72, 0.001));
    expect(ReaderBottomGlass.backdropSigma(100), 8);
    expect(ReaderTopGlass.backdropSigma(15), closeTo(4.2, 0.001));
    // The legacy curve remains monotonic, but must not be used to create
    // separately clipped horizontal backdrop bands.
    expect(ReaderBottomGlass.sigmaAt(0, 24), 0);
    expect(ReaderBottomGlass.sigmaAt(1, 24), 24);
    var previous = 0.0;
    for (var i = 0; i <= 100; i++) {
      final sigma = ReaderBottomGlass.sigmaAt(i / 100, 24);
      expect(sigma, inInclusiveRange(previous, 24.0));
      previous = sigma;
    }
  });

  testWidgets('bottom glass stays rounded, clear at top and dark below', (
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
    // A single full-card filter has no horizontal clip boundaries, while the
    // gradient layers below keep the lower controls readable.
    expect(find.byKey(ValueKey('reader-bottom-blur-band-0')), findsNothing);
    expect(find.byKey(ValueKey('reader-bottom-blur-band-15')), findsNothing);
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(find.byType(BackdropGroup), findsNothing);
    final decorations = tester
        .widgetList<DecoratedBox>(
          find.descendant(
            of: find.byType(ReaderBottomGlass),
            matching: find.byType(DecoratedBox),
          ),
        )
        .toList();
    expect(decorations, hasLength(2));

    final surfaceGradient = decorations[0].decoration as BoxDecoration;
    expect(surfaceGradient.color, isNull); // no opaque base material
    final surface = surfaceGradient.gradient! as LinearGradient;
    expect(surface.colors.first.a, 0);
    expect(surface.colors.last.a, greaterThanOrEqualTo(0.33));

    final shadeGradient = decorations[1].decoration as BoxDecoration;
    expect(shadeGradient.color, isNull); // tint is a controlled gradient
    final shade = shadeGradient.gradient! as LinearGradient;
    expect(shade.colors.first.a, 0);
    // The ramp stays visible without returning to the previous near-black
    // footer: its middle remains a readable translucent shade.
    expect(shade.colors[2].a, greaterThanOrEqualTo(0.12));
    expect(shade.colors[3].a, greaterThanOrEqualTo(0.38));
    expect(shade.colors.last.a, greaterThanOrEqualTo(0.65));
    expect(tester.takeException(), isNull);
  });

  test('reader HUD keeps the legacy outlined chapter and status style', () {
    final scaffold = File('lib/pages/reader/scaffold.dart').readAsStringSync();
    final hud = File('lib/pages/reader/reader_hud.dart').readAsStringSync();
    expect(hud, contains('PaintingStyle.stroke'));
    expect(hud, contains('..strokeWidth = 1.4'));
    expect(scaffold, contains('return ReaderHudText(text'));
    expect(scaffold, contains('return ReaderHudText(_currentTime'));
    expect(scaffold, contains('return ReaderHudBattery('));
    expect(scaffold, contains('ReaderHudPill('));
    expect(scaffold, contains('buildPageInfoText()'));
    expect(scaffold, contains('buildStatusInfo()'));
    expect(RegExp(r'child: ReaderChromeVisibility\(').allMatches(scaffold).length, 3);
    expect(scaffold, contains('return ReaderBottomGlass('));
  });

  test('first tap is allowed and swipe settling blocks only 600ms', () {
    final settledAt = DateTime(2025, 1, 1, 12, 0, 0);
    expect(readerTapSuppressionActive(null, settledAt), isFalse);
    expect(
      readerTapSuppressionActive(
        settledAt,
        settledAt.add(const Duration(milliseconds: 599)),
      ),
      isTrue,
    );
    expect(
      readerTapSuppressionActive(
        settledAt,
        settledAt.add(const Duration(milliseconds: 600)),
      ),
      isFalse,
    );
    // A clock adjustment before the end timestamp must not block the initial
    // tap or turn the settling window into an unbounded one.
    expect(
      readerTapSuppressionActive(
        settledAt,
        settledAt.add(const Duration(milliseconds: 300)),
        delayMs: 300,
      ),
      isFalse,
    );
    expect(
      readerTapSuppressionActive(
        settledAt,
        settledAt.add(const Duration(milliseconds: 999)),
        delayMs: 1000,
      ),
      isTrue,
    );
  });
}
