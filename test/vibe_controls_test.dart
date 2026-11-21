import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/components/components.dart';
import 'package:venera/main.dart';
import 'package:venera/utils/translations.dart';

import 'helpers/hud_font_fixture.dart';

Widget controlsHost(Widget child, {
  Brightness brightness = Brightness.light,
  double scale = 1,
  bool reduce = false,
  bool accessibleNavigation = false,
  TextDirection direction = TextDirection.ltr,
}) {
  // Use the actual app tokens and typography without booting plugins/routes.
  final dynamic themeFactory = const MyApp().createState();
  final ThemeData productionTheme = themeFactory.getTheme(
    Colors.purple, null, null, brightness,
  );
  final theme = productionTheme.copyWith(
    platform: TargetPlatform.iOS,
    textTheme: productionTheme.textTheme.apply(
      fontFamily: 'HudLatin', fontFamilyFallback: const ['HudCJK']),
    primaryTextTheme: productionTheme.primaryTextTheme.apply(
      fontFamily: 'HudLatin', fontFamilyFallback: const ['HudCJK']),
  );
  return MaterialApp(
    theme: theme,
    debugShowCheckedModeBanner: false,
    builder: (context, body) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(scale),
        disableAnimations: reduce,
        accessibleNavigation: accessibleNavigation,
      ),
      child: Directionality(textDirection: direction, child: body!),
    ),
    home: Scaffold(body: Center(child: child)),
  );
}

Finder buttonSurface() => find.descendant(
  of: find.byType(Button), matching: find.byType(AnimatedContainer),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await AppTranslation.init();
    if (Platform.environment['VIBE_EVIDENCE'] == '1') {
      for (final variable in ['HUD_LATIN_FONT', 'HUD_CJK_FONT']) {
        final path = Platform.environment[variable];
        if (path == null || !File(path).existsSync()) {
          throw StateError('Missing real screenshot font: $variable');
        }
      }
    }
    await loadHudTestFonts();
  });

  for (final brightness in Brightness.values) {
    testWidgets('production buttons preserve loading geometry / $brightness', (tester) async {
      for (final type in ButtonType.values) {
        var taps = 0;
        var anchors = 0;
        Widget control(bool loading) => controlsHost(
          Button(type: type, isLoading: loading,
            onPressed: () => taps++, onPressedAt: (_) => anchors++,
            child: const Text('Download entire selected collection')),
          brightness: brightness,
        );
        await tester.pumpWidget(control(false));
        await tester.pump();
        final size = tester.getSize(find.byType(Button));
        expect(size.height, greaterThanOrEqualTo(44));
        await tester.pumpWidget(control(true));
        await tester.pump(const Duration(milliseconds: 240));
        expect(tester.getSize(find.byType(Button)), size);
        expect(find.text('Download entire selected collection'), findsNothing);
        await tester.tap(find.byType(Button));
        await tester.pump();
        expect(taps, 0);
        expect(anchors, 0);
        await tester.pumpWidget(control(false));
        await tester.pump(const Duration(milliseconds: 240));
        expect(tester.getSize(find.byType(Button)), size);
        await tester.tap(find.byType(Button));
        expect(taps, 1);
        expect(anchors, 1);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('first-frame busy geometry matches ready / $brightness', (tester) async {
      Widget control(bool loading) => controlsHost(
        Button.filled(isLoading: loading, onPressed: () {},
          child: const Text('A deliberately long loading label')),
        brightness: brightness,
      );
      await tester.pumpWidget(control(true));
      final size = tester.getSize(find.byType(Button));
      await tester.pumpWidget(control(false));
      await tester.pump(const Duration(milliseconds: 240));
      expect(tester.getSize(find.byType(Button)), size);
    });

    testWidgets('press depth cancels without callbacks / $brightness', (tester) async {
      var taps = 0;
      final anchors = <Offset>[];
      await tester.pumpWidget(controlsHost(
        Button.normal(onPressed: () => taps++, onPressedAt: anchors.add,
          child: const Text('Action')),
        brightness: brightness,
      ));
      final surface = tester.widget<AnimatedContainer>(buttonSurface());
      final initial = surface.decoration! as BoxDecoration;
      expect(initial.boxShadow, isNotEmpty);
      final gesture = await tester.startGesture(tester.getCenter(find.byType(Button)));
      await tester.pump(const Duration(milliseconds: 160));
      final pressed = tester.widget<AnimatedContainer>(buttonSurface());
      expect(pressed.transform!.storage[13], 1);
      expect((pressed.decoration! as BoxDecoration).boxShadow, isEmpty);
      await gesture.cancel();
      await tester.pump(const Duration(milliseconds: 240));
      expect(tester.widget<AnimatedContainer>(buttonSurface()).transform!.storage[13], 0);
      expect(taps, 0);
      expect(anchors, isEmpty);
      final anchor = tester.getTopLeft(find.byType(Button));
      await tester.tap(find.byType(Button));
      expect(taps, 1);
      expect(anchors.single.dx, closeTo(anchor.dx, .01));
      expect(anchors.single.dy, closeTo(anchor.dy, 1.01));
    });
  }

  testWidgets('dragging a button in a scroll view does not activate', (tester) async {
    var taps = 0;
    await tester.pumpWidget(controlsHost(SizedBox(
      width: 300, height: 240,
      child: ListView(children: [
        Button.filled(onPressed: () => taps++, child: const Text('Scroll past')),
        const SizedBox(height: 1000),
      ]),
    )));
    await tester.drag(find.byType(Button), const Offset(0, -180));
    await tester.pumpAndSettle();
    expect(taps, 0);
    expect(tester.widget<AnimatedContainer>(buttonSurface()).transform!.storage[13], 0);
  });

  testWidgets('keyboard activation preserves both callback contracts', (tester) async {
    var taps = 0;
    var anchors = 0;
    await tester.pumpWidget(controlsHost(Button.filled(
      onPressed: () => taps++, onPressedAt: (_) => anchors++, child: const Text('Keyboard'),
    )));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(taps, 1);
    expect(anchors, 1);
    await tester.pumpWidget(controlsHost(Button.filled(
      isLoading: true, onPressed: () => taps++, onPressedAt: (_) => anchors++,
      child: const Text('Keyboard'),
    )));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(taps, 1);
    expect(anchors, 1);
  });

  testWidgets('pressable long press never also invokes tap', (tester) async {
    var taps = 0;
    var longs = 0;
    await tester.pumpWidget(controlsHost(VeneraPressable(
      onTap: () => taps++, onLongPress: () => longs++,
      child: const SizedBox(width: 100, height: 44, child: Text('Hold')),
    )));
    await tester.longPress(find.byType(VeneraPressable));
    await tester.pump(const Duration(milliseconds: 240));
    expect(longs, 1);
    expect(taps, 0);
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
    expect(tester.takeException(), isNull);
  });

  for (final accessible in [false, true]) {
    testWidgets('reduced motion policy and controls accessible=$accessible', (tester) async {
      late BuildContext motionContext;
      await tester.pumpWidget(controlsHost(Builder(builder: (context) {
        motionContext = context;
        return Column(mainAxisSize: MainAxisSize.min, children: [
          Button.normal(onPressed: () {}, child: const Text('Reduced')),
          VeneraIconButton(icon: const Icon(Icons.bookmark_outline), onPressed: () {}),
          Button.icon(icon: const Icon(Icons.download), onPressed: () {}, isLoading: true),
          SizedBox(width: 300, child: VeneraSegmentedControl(
            labels: const ['Recent', 'All'], selectedIndex: 0, onChanged: (_) {})),
        ]);
      }), reduce: !accessible, accessibleNavigation: accessible));
      expect(VeneraMotion.reduce(motionContext), isTrue);
      expect(VeneraMotion.duration(motionContext, const Duration(milliseconds: 220)), Duration.zero);
      final gesture = await tester.startGesture(tester.getCenter(find.byType(Button)));
      await tester.pump(const Duration(milliseconds: 120));
      final surface = tester.widget<AnimatedContainer>(buttonSurface());
      expect(surface.duration, Duration.zero);
      expect(surface.transform!.storage[13], 0);
      expect(tester.widget<AnimatedAlign>(find.byType(AnimatedAlign)).duration, Duration.zero);
      final progress = tester.widget<CircularProgressIndicator>(find.byType(CircularProgressIndicator));
      expect(progress.value, .72);
      expect(progress.semanticsValue, isNot(contains('%')));
      expect(progress.semanticsLabel, isNotEmpty);
      await gesture.cancel();
      await tester.pump();
    });
  }

  testWidgets('segmented selection travels continuously and reports only tapped index', (tester) async {
    var selected = 0;
    final changes = <int>[];
    late StateSetter change;
    await tester.pumpWidget(controlsHost(StatefulBuilder(builder: (context, setState) {
      change = setState;
      return SizedBox(width: 320, child: VeneraSegmentedControl(
        labels: const ['Recent', 'All'], selectedIndex: selected,
        onChanged: (index) { changes.add(index); change(() => selected = index); },
      ));
    })));
    final thumb = find.byType(FractionallySizedBox);
    final start = tester.getTopLeft(thumb).dx;
    final tapTargets = find.descendant(of: find.byType(VeneraSegmentedControl), matching: find.byType(InkWell));
    for (final target in tapTargets.evaluate()) {
      expect(tester.getSize(find.byWidget(target.widget)).height, greaterThanOrEqualTo(44));
    }
    final radius = tester.widget<InkWell>(tapTargets.first).borderRadius!;
    final context = tester.element(find.byType(VeneraSegmentedControl));
    expect(radius.topLeft.x, VeneraDesignTokens.of(context).controlRadius - 3);
    await tester.tap(find.text('All'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 110));
    final middle = tester.getTopLeft(thumb).dx;
    await tester.pump(const Duration(milliseconds: 220));
    final end = tester.getTopLeft(thumb).dx;
    expect(middle, greaterThan(start));
    expect(middle, lessThan(end));
    expect(changes, [1]);
    expect(selected, 1);
  });

  testWidgets('segmented empty/single and RTL remain valid', (tester) async {
    await tester.pumpWidget(controlsHost(VeneraSegmentedControl(
      labels: const [], selectedIndex: 0, onChanged: (_) {},
    )));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(controlsHost(SizedBox(width: 280,
      child: VeneraSegmentedControl(labels: const ['Only'], selectedIndex: 99, onChanged: (_) {}))));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(controlsHost(SizedBox(width: 280,
      child: VeneraSegmentedControl(labels: const ['First', 'Second'], selectedIndex: 0, onChanged: (_) {})),
      direction: TextDirection.rtl));
    await tester.pumpAndSettle();
    final thumb = tester.getCenter(find.byType(FractionallySizedBox));
    final control = tester.getCenter(find.byType(VeneraSegmentedControl));
    expect(thumb.dx, greaterThan(control.dx));
  });

  testWidgets('icon controls retain 44pt targets and block loading/disabled callbacks', (tester) async {
    var taps = 0;
    Widget icons(bool loading) => controlsHost(Row(mainAxisSize: MainAxisSize.min, children: [
      VeneraIconButton(key: const ValueKey('material-icon'), size: 28,
        tooltip: 'Bookmark', icon: const Icon(Icons.bookmark_outline),
        onPressed: loading ? null : () => taps++),
      Button.icon(key: const ValueKey('plain-icon'), size: 18, isLoading: loading,
        behavior: HitTestBehavior.opaque, tooltip: 'Close',
        icon: const Icon(Icons.close), onPressed: () => taps++),
    ]));
    await tester.pumpWidget(icons(false));
    final sizes = <Size>[];
    for (final key in ['material-icon', 'plain-icon']) {
      final target = find.byKey(ValueKey(key));
      final size = tester.getSize(target);
      sizes.add(size);
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
      await tester.tap(target);
    }
    expect(taps, 2);
    await tester.pumpWidget(icons(true));
    await tester.pump(const Duration(milliseconds: 240));
    var i = 0;
    for (final key in ['material-icon', 'plain-icon']) {
      final target = find.byKey(ValueKey(key));
      expect(tester.getSize(target), sizes[i++]);
      await tester.tap(target);
    }
    expect(taps, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('control labels occur once in semantics', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(controlsHost(Column(mainAxisSize: MainAxisSize.min, children: [
        Button.normal(onPressed: () {}, child: const Text('Save action')),
        VeneraIconButton(icon: const Icon(Icons.close), tooltip: 'Close action', onPressed: () {}),
        SizedBox(width: 300, child: VeneraSegmentedControl(
          labels: const ['Recent items', 'All items'], selectedIndex: 0, onChanged: (_) {})),
        VeneraChip(label: 'Filter action', selected: true, onTap: () {}),
      ])));
      for (final label in ['Save action', 'Close action', 'Recent items', 'All items', 'Filter action']) {
        expect(find.bySemanticsLabel(label), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    } finally { semantics.dispose(); }
  });

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('production control viewport ${brightness.name} ${scale}x', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390, 844);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final boundaryKey = GlobalKey();
        var selected = 0;
        await tester.pumpWidget(controlsHost(
          RepaintBoundary(key: boundaryKey, child: SizedBox.expand(
            child: Builder(builder: (context) => ColoredBox(
              color: Theme.of(context).colorScheme.surface,
              child: SingleChildScrollView(child: Padding(
                padding: const EdgeInsets.all(20),
                child: StatefulBuilder(builder: (context, setState) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Library controls · 收藏操作', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 20),
                    VeneraSegmentedControl(
                      labels: const ['Recently updated 最近更新', 'All collections 全部收藏'],
                      selectedIndex: selected,
                      onChanged: (index) => setState(() => selected = index),
                    ),
                    const SizedBox(height: 20),
                    Button.filled(onPressed: () {}, child: const Text('Continue reading · 继续阅读')),
                    const SizedBox(height: 12),
                    Button.normal(onPressed: () {}, child: const Text('Save the complete collection to library')),
                    const SizedBox(height: 12),
                    Button.outlined(onPressed: () {}, child: const Text('Manage selected collections · 管理收藏')),
                    const SizedBox(height: 12),
                    Button.text(onPressed: () {}, child: const Text('Cancel · 取消')),
                    const SizedBox(height: 12),
                    Button.filled(isLoading: true, onPressed: () {},
                      child: const Text('Download selected collections')),
                    const SizedBox(height: 12),
                    Align(alignment: AlignmentDirectional.centerStart, child: VeneraChip(
                      label: 'Unread collections 未阅读收藏', selected: true, onTap: () {})),
                    const SizedBox(height: 16),
                    Row(children: [
                      VeneraIconButton(icon: const Icon(Icons.bookmark_outline),
                        tooltip: 'Save', onPressed: () {}),
                      const SizedBox(width: 12),
                      const VeneraIconButton(icon: Icon(Icons.bookmark_outline),
                        tooltip: 'Unavailable', onPressed: null),
                      const SizedBox(width: 12),
                      Button.icon(icon: const Icon(Icons.close), tooltip: 'Close', onPressed: () {}),
                    ]),
                  ],
                )),
              )),
            )),
          )), brightness: brightness, scale: scale, reduce: scale == 2,
        ));
        // A live loading spinner is intentional; never pumpAndSettle here.
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull, reason: 'No layout overflow at 390pt / ${scale}x');
        if (Platform.environment['VIBE_EVIDENCE'] == '1') {
          await tester.runAsync(() async {
            final boundary = boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: 3);
            try {
              final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
              final file = File('build/vibe-evidence/controls-${brightness.name}-${scale}x.png');
              file.parent.createSync(recursive: true);
              file.writeAsBytesSync(bytes!.buffer.asUint8List());
            } finally { image.dispose(); }
          });
        }
        // Exercise the same long labels, not a separate static look-alike.
        await tester.tap(find.text('All collections 全部收藏'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(selected, 1);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
