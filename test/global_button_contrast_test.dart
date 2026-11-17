import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/components/components.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final fill in [Colors.white, Colors.black, Colors.yellow, Colors.blue]) {
      testWidgets('filled button contrast: $brightness / $fill', (tester) async {
        await tester.pumpWidget(MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: Scaffold(body: Button.filled(
            color: fill,
            onPressed: () {},
            child: const Text('Action'),
          )),
        ));
        final context = tester.element(find.text('Action'));
        final foreground = DefaultTextStyle.of(context).style.color!;
        final a = fill.computeLuminance();
        final b = foreground.computeLuminance();
        final contrast = a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05);
        expect(contrast, greaterThanOrEqualTo(4.5));
        expect(tester.getSize(find.byType(Button)).height, greaterThanOrEqualTo(44));
      });
    }
  }

  testWidgets('initial loading uses readable foreground and blocks action', (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Button.filled(
        color: Colors.white,
        isLoading: true,
        onPressed: () => taps++,
        child: const Text('Action'),
      )),
    ));
    expect(find.text('Action'), findsNothing);
    expect(tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    ).color, Colors.black);
    await tester.tap(find.byType(Button));
    expect(taps, 0);
  });

  testWidgets('normal button has a visible border', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Button.normal(
        onPressed: () {},
        child: const Text('Action'),
      )),
    ));
    final container = tester.widget<AnimatedContainer>(
      find.descendant(of: find.byType(Button), matching: find.byType(AnimatedContainer)),
    );
    final decoration = container.decoration! as BoxDecoration;
    expect(decoration.border, isNotNull);
    expect((decoration.border! as Border).top.width, 1);
  });
}
