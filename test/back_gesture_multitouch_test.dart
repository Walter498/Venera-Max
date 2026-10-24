import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/app_page_route.dart';

/// Regression tests for the iOS edge-back gesture when more than one finger is
/// on the screen.
///
/// Bug: while the user was dragging the page back from the left edge, a second
/// finger touching the screen reset the swipe recognizer (new drag origin, the
/// `accepted` flag cleared, and the following pointer-up stopped tracking the
/// *wrong* pointer id). No drag-end ever reached [IOSBackGestureController], so
/// the page froze at a partial offset and the navigator stayed inside
/// `userGestureInProgress` — every later back swipe was then refused.
///
/// Expected behaviour after the fix:
///  * one finger: the swipe still completes the pop exactly as before;
///  * a second finger mid-swipe aborts the interactive pop, the page animates
///    back to its resting position (no pop, never stuck halfway) and the
///    navigator user gesture is released once the animation settles;
///  * pointer cancel restores instead of resolving by position/velocity;
///  * disposing the detector mid-swipe still releases the user gesture;
///  * once restored, a fresh swipe works normally.
void main() {
  const Size testSurface = Size(480, 720);

  /// Width of the edge area the swipe must start in.
  const double kEdgeX = 5;

  /// Logical screen width; drag deltas are divided by it.
  const double kWidth = 480;

  Future<AppPageRoute<void>> pumpRoute(
    WidgetTester tester,
    GlobalKey<NavigatorState> navigatorKey,
  ) async {
    tester.view.physicalSize = testSurface;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(body: Text('home')),
      ),
    );
    await tester.pumpAndSettle();

    final route = AppPageRoute<void>(
      enableIOSGesture: true,
      builder: (_) => const Scaffold(body: Text('details')),
    );
    navigatorKey.currentState!.push(route);
    await tester.pumpAndSettle();
    expect(find.text('details'), findsOneWidget);
    return route;
  }

  testWidgets(
    'second finger mid-swipe restores the page instead of freezing it halfway',
    (tester) async {
      final navigatorKey = GlobalKey<NavigatorState>();
      final route = await pumpRoute(tester, navigatorKey);
      final navigator = navigatorKey.currentState!;
      final animation = route.animation!;

      final first = await tester.startGesture(
        const Offset(kEdgeX, 300),
        pointer: 1,
      );
      await first.moveBy(const Offset(300, 0));
      await tester.pump();

      // 300 / 480 of the page has been dragged back — past the halfway point,
      // so releasing here would pop. The page is visibly mid-transition and
      // the navigator owns a user gesture.
      expect(animation.value, closeTo(1 - 300 / kWidth, 0.001));
      expect(navigator.userGestureInProgress, isTrue);

      // Second finger lands somewhere on the page while the swipe is in flight.
      final second = await tester.startGesture(
        const Offset(300, 300),
        pointer: 2,
      );
      await tester.pump();

      // The interactive pop is aborted and animates back towards the page —
      // it must not resolve as a pop just because the drag passed halfway.
      expect(animation.value, greaterThanOrEqualTo(1 - 300 / kWidth));
      await tester.pump(const Duration(milliseconds: 180));
      expect(animation.value, greaterThan(1 - 300 / kWidth));

      await tester.pumpAndSettle();

      // Fully restored: still on the detail page, never left mid-transition,
      // and the navigator lock is gone.
      expect(animation.value, closeTo(1.0, 0.0001));
      expect(animation.status, AnimationStatus.completed);
      expect(find.text('details'), findsOneWidget);
      expect(navigator.userGestureInProgress, isFalse);

      // Dragging the original finger afterwards must not move the page again.
      await first.moveBy(const Offset(-60, 0));
      await tester.pump();
      expect(animation.value, closeTo(1.0, 0.0001));
      await first.up();
      await second.up();
      await tester.pumpAndSettle();
      expect(find.text('details'), findsOneWidget);
      expect(navigator.userGestureInProgress, isFalse);

      // A fresh one-finger swipe still works after the aborted one.
      final retry = await tester.startGesture(
        const Offset(kEdgeX, 300),
        pointer: 3,
      );
      await retry.moveBy(const Offset(400, 0));
      await tester.pump();
      expect(animation.value, closeTo(1 - 400 / kWidth, 0.001));
      await retry.up();
      await tester.pumpAndSettle();

      expect(find.text('details'), findsNothing);
      expect(find.text('home'), findsOneWidget);
      expect(navigator.userGestureInProgress, isFalse);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'single-finger edge swipe still completes the pop',
    (tester) async {
      final navigatorKey = GlobalKey<NavigatorState>();
      final route = await pumpRoute(tester, navigatorKey);
      final navigator = navigatorKey.currentState!;
      final animation = route.animation!;

      final gesture = await tester.startGesture(
        const Offset(kEdgeX, 300),
        pointer: 1,
      );
      await gesture.moveBy(const Offset(300, 0));
      await tester.pump();
      expect(animation.value, closeTo(1 - 300 / kWidth, 0.001));
      expect(navigator.userGestureInProgress, isTrue);

      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.text('details'), findsNothing);
      expect(find.text('home'), findsOneWidget);
      expect(navigator.userGestureInProgress, isFalse);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'center swipe does not pop the route',
    (tester) async {
      final navigatorKey = GlobalKey<NavigatorState>();
      final route = await pumpRoute(tester, navigatorKey);
      final navigator = navigatorKey.currentState!;
      final animation = route.animation!;

      final gesture = await tester.startGesture(
        const Offset(240, 300),
        pointer: 1,
      );
      await gesture.moveBy(const Offset(300, 0));
      await tester.pump();
      expect(animation.value, closeTo(1.0, 0.0001));
      expect(navigator.userGestureInProgress, isFalse);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.text('details'), findsOneWidget);
      expect(find.text('home'), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );


    (tester) async {
      final navigatorKey = GlobalKey<NavigatorState>();
      final route = await pumpRoute(tester, navigatorKey);
      final navigator = navigatorKey.currentState!;
      final animation = route.animation!;

      final gesture = await tester.startGesture(
        const Offset(kEdgeX, 300),
        pointer: 1,
      );
      // Drag well past the halfway point, where a position-based drag end would
      // pop the route; a cancel must still return to the detail page.
      await gesture.moveBy(const Offset(350, 0));
      await tester.pump();
      expect(animation.value, closeTo(1 - 350 / kWidth, 0.001));

      await gesture.cancel();
      await tester.pumpAndSettle();

      expect(find.text('details'), findsOneWidget);
      expect(animation.value, closeTo(1.0, 0.0001));
      expect(animation.status, AnimationStatus.completed);
      expect(navigator.userGestureInProgress, isFalse);

      // The next swipe is not blocked by the cancelled one.
      final retry = await tester.startGesture(
        const Offset(kEdgeX, 300),
        pointer: 2,
      );
      await retry.moveBy(const Offset(400, 0));
      await retry.up();
      await tester.pumpAndSettle();
      expect(find.text('home'), findsOneWidget);
      expect(navigator.userGestureInProgress, isFalse);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'second finger before the swipe is accepted does not steal the drag',
    (tester) async {
      final navigatorKey = GlobalKey<NavigatorState>();
      final route = await pumpRoute(tester, navigatorKey);
      final navigator = navigatorKey.currentState!;
      final animation = route.animation!;

      final first = await tester.startGesture(
        const Offset(kEdgeX, 300),
        pointer: 1,
      );
      // Below the 12px threshold: the recognizer has not accepted the drag yet.
      await first.moveBy(const Offset(6, 0));
      await tester.pump();

      final second = await tester.startGesture(
        const Offset(240, 400),
        pointer: 2,
      );
      await tester.pump();
      expect(navigator.userGestureInProgress, isFalse);
      expect(animation.value, closeTo(1.0, 0.0001));

      // The owning pointer keeps controlling the swipe.
      await first.moveBy(const Offset(294, 0));
      await tester.pump();
      // Only the accepted move's delta is applied (the sub-threshold lead-in is
      // not replayed), matching a single continuous drag.
      expect(animation.value, closeTo(1 - 294 / kWidth, 0.001));

      await first.up();
      await second.up();
      await tester.pumpAndSettle();

      expect(find.text('home'), findsOneWidget);
      expect(navigator.userGestureInProgress, isFalse);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'disposing the detector mid-swipe releases the navigator user gesture',
    (tester) async {
      final navigatorKey = GlobalKey<NavigatorState>();
      final showDetector = ValueNotifier<bool>(true);
      addTearDown(showDetector.dispose);
      final animation = AnimationController(
        vsync: const TestVSync(),
        value: 1.0,
      );
      addTearDown(animation.dispose);

      tester.view.physicalSize = testSurface;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          home: Builder(
            builder: (context) {
              final navigator = Navigator.of(context);
              return ValueListenableBuilder<bool>(
                valueListenable: showDetector,
                builder: (context, show, _) {
                  if (!show) {
                    return const SizedBox.expand();
                  }
                  return IOSBackGestureDetector(
                    gestureWidth: 19,
                    enabledCallback: () => true,
                    onStartPopGesture: () =>
                        IOSBackGestureController(animation, navigator),
                    child: const Scaffold(body: Text('swipe surface')),
                  );
                },
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      final navigator = navigatorKey.currentState!;
      final gesture = await tester.startGesture(
        const Offset(kEdgeX, 300),
        pointer: 1,
      );
      await gesture.moveBy(const Offset(200, 0));
      await tester.pump();

      // Mid-swipe: navigator locked, animation driven by the gesture.
      expect(animation.value, lessThan(1.0));
      expect(navigator.userGestureInProgress, isTrue);

      // The route/detector disappears before the swipe is resolved.
      showDetector.value = false;
      await tester.pump();
      await tester.pump();

      expect(navigator.userGestureInProgress, isFalse,
          reason: 'dispose must release the user gesture exactly once');
      expect(animation.isAnimating, isFalse);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(navigator.userGestureInProgress, isFalse);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}
