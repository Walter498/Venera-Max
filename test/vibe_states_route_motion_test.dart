import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/components/components.dart';

/// These tests deliberately never pumpAndSettle or advance the clock for a
/// reduced-motion route. Hiding its tween alone must not leave a modal barrier
/// intercepting the page behind it for the ordinary 220ms route lifetime.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final popup in [true, false]) {
    final name = popup ? 'popup' : 'sidebar';
    for (final accessibilityOnly in [false, true]) {
      final policy = accessibilityOnly
          ? 'accessibleNavigation only'
          : 'disableAnimations only';
      testWidgets('$name has zero entry/exit duration and immediate taps: $policy',
          (tester) async {
        tester.view.physicalSize = const Size(760, 860);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        TransitionRoute<String>? route;
        String? result;
        var underlyingTaps = 0;
        const underlyingKey = ValueKey('underlying-action');
        const closeKey = ValueKey('close-overlay');

        await tester.pumpWidget(MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: !accessibilityOnly,
              accessibleNavigation: accessibilityOnly,
            ),
            child: child!,
          ),
          home: Scaffold(body: Builder(builder: (context) => Stack(children: [
            Align(
              alignment: Alignment.topLeft,
              child: TextButton(
                onPressed: () {
                  final overlay = Material(child: Center(child: Builder(
                    builder: (context) => TextButton(
                      key: closeKey,
                      onPressed: () => Navigator.of(context, rootNavigator: true)
                          .pop('closed'),
                      child: const Text('Close overlay'),
                    ),
                  )));
                  // Exercise both legacy constructors without adding context
                  // parameters; route installation must find its host policy.
                  route = popup
                      ? PopUpWidget<String>(overlay)
                      : SideBarRoute<String>(overlay, width: 380);
                  Navigator.of(context).push<String>(route!).then((value) {
                    result = value;
                  });
                },
                child: const Text('Open overlay'),
              ),
            ),
            Align(
              alignment: Alignment.bottomLeft,
              child: TextButton(
                key: underlyingKey,
                onPressed: () => underlyingTaps++,
                child: const Text('Underlying action'),
              ),
            ),
          ]))),
        ));
        await tester.tap(find.text('Open overlay'));
        await tester.pump();
        await tester.pump();
        expect(route!.transitionDuration, Duration.zero);
        expect(route!.reverseTransitionDuration, Duration.zero);
        expect(route!.animation!.value, 1);
        expect(route!.animation!.status, AnimationStatus.completed);
        expect(find.byKey(closeKey), findsOneWidget);

        await tester.tap(find.byKey(closeKey));
        // Two zero-time frames permit Navigator finalization/overlay removal,
        // but cannot accidentally wait out the old 220ms reverse animation.
        await tester.pump();
        await tester.pump();
        expect(result, 'closed');
        expect(find.byKey(closeKey), findsNothing);
        await tester.tap(find.byKey(underlyingKey));
        expect(underlyingTaps, 1,
            reason: 'No invisible outgoing route or modal barrier may block taps');
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('$name keeps ordinary forward and reverse timing', (tester) async {
      TransitionRoute<void>? route;
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: false, accessibleNavigation: false),
          child: child!,
        ),
        home: Scaffold(body: Builder(builder: (context) => TextButton(
          onPressed: () {
            route = popup
                ? PopUpWidget<void>(const Material(child: Text('Ordinary overlay')))
                : SideBarRoute<void>(const Text('Ordinary overlay'), width: 380);
            Navigator.of(context).push<void>(route!);
          },
          child: const Text('Open ordinary'),
        ))),
      ));
      await tester.tap(find.text('Open ordinary'));
      await tester.pump();
      expect(route!.transitionDuration, const Duration(milliseconds: 220));
      expect(route!.reverseTransitionDuration, const Duration(milliseconds: 220));
      await tester.pump(const Duration(milliseconds: 110));
      expect(route!.animation!.value, greaterThan(0));
      expect(route!.animation!.value, lessThan(1));
      await tester.pump(const Duration(milliseconds: 110));
      expect(route!.animation!.value, 1);
      route!.navigator!.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 110));
      expect(find.text('Ordinary overlay'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 110));
      await tester.pump();
      expect(find.text('Ordinary overlay'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
