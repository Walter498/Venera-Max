import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/components/components.dart';
import 'package:venera/foundation/res.dart';
import 'package:venera/main.dart';
import 'package:venera/utils/translations.dart';

import 'helpers/hud_font_fixture.dart';

class _LoadingProbe extends StatefulWidget {
  const _LoadingProbe({required this.result, required this.onLoad});
  final Future<Res<String>> result;
  final VoidCallback onLoad;

  @override
  State<_LoadingProbe> createState() => _LoadingProbeState();
}

class _LoadingProbeState extends LoadingState<_LoadingProbe, String> {
  @override
  Future<Res<String>> loadData() {
    widget.onLoad();
    return widget.result;
  }

  @override
  Widget buildContent(BuildContext context, String data) => Text(data);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await AppTranslation.init();
    await loadHudTestFonts();
  });

  final captureKey = GlobalKey();
  Widget app(Widget child, {bool reduce = true, double scale = 1,
    Brightness brightness = Brightness.light, double keyboard = 0}) {
    // Match the app's real type metrics, component themes and surface tokens.
    // Only replace fonts so CI raster evidence uses the real fixture fonts.
    final dynamic themeFactory = const MyApp().createState();
    final ThemeData productionTheme = themeFactory.getTheme(
      Colors.purple, null, null, brightness);
    final fontTheme = productionTheme.copyWith(
      textTheme: productionTheme.textTheme.apply(
        fontFamily: 'HudLatin', fontFamilyFallback: const ['HudCJK']),
      primaryTextTheme: productionTheme.primaryTextTheme.apply(
        fontFamily: 'HudLatin', fontFamilyFallback: const ['HudCJK']),
    );
    return RepaintBoundary(
      key: captureKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: fontTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: reduce, accessibleNavigation: reduce,
            textScaler: TextScaler.linear(scale),
            padding: const EdgeInsets.only(top: 24, bottom: 24),
            viewInsets: EdgeInsets.only(bottom: keyboard),
          ),
          child: child!,
        ),
        home: Scaffold(body: child),
      ),
    );
  }

  void phone(WidgetTester tester, {Size size = const Size(430, 860)}) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> capture(WidgetTester tester, String name) async {
    if (Platform.environment['HUD_EVIDENCE'] != '1' &&
        Platform.environment['VIBE_EVIDENCE'] != '1') return;
    await tester.runAsync(() async {
      final boundary = captureKey.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('build/vibe-evidence/$name.png');
        file.parent.createSync(recursive: true);
        file.writeAsBytesSync(data!.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    });
  }

  testWidgets('loading is stable, accessible, reduced and never holds ready data',
      (tester) async {
    phone(tester);
    final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);
    final result = Completer<Res<String>>();
    var requests = 0;
    await tester.pumpWidget(app(_LoadingProbe(result: result.future,
      onLoad: () => requests++)));
    await tester.pump();
    final indicator = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator));
    expect(indicator.value, 0.65);
    expect(indicator.semanticsLabel, isNotEmpty);
    expect(tester.getSize(find.byType(CircularProgressIndicator)), const Size(32, 32));
    await capture(tester, 'loading-reduced-light');
    result.complete(const Res('Ready immediately'));
    await tester.pump();
    expect(find.text('Ready immediately'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(requests, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('list and lazy sliver retain 80pt slots without reduced-motion tickers',
      (tester) async {
    phone(tester);
    await tester.pumpWidget(app(const Column(children: [
      ListLoadingIndicator(),
      Expanded(child: CustomScrollView(slivers: [SliverListLoadingIndicator()])),
    ])));
    await tester.pumpAndSettle();
    expect(find.byType(ListLoadingIndicator), findsNWidgets(2));
    for (final finder in [find.byType(ListLoadingIndicator).first,
        find.byType(ListLoadingIndicator).last]) {
      expect(tester.getSize(finder).height, 80);
    }
    for (final indicator in tester.widgetList<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator))) {
      expect(indicator.value, 0.65);
      expect(indicator.semanticsLabel, isNotEmpty);
    }
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('five dots stop when reduce motion changes without layout movement',
      (tester) async {
    phone(tester);
    await tester.pumpWidget(app(const Center(child: SizedBox(height: 80, child: FiveDotLoadingAnimation())), reduce: false));
    await tester.pump(const Duration(milliseconds: 180));
    final before = tester.getRect(find.byType(FiveDotLoadingAnimation));
    await tester.pumpWidget(app(const Center(child: SizedBox(height: 80, child: FiveDotLoadingAnimation()))));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(FiveDotLoadingAnimation)), before);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets('long dialog scrolls and actions survive 2x ${brightness.name}',
        (tester) async {
      phone(tester);
      var confirmed = 0;
      await tester.pumpWidget(app(Builder(builder: (context) => TextButton(
        onPressed: () => showDialog<void>(context: context,
          builder: (context) => ContentDialog(
            title: 'Review connection settings before continuing',
            content: Text(List.filled(18, 'Long content remains readable.').join('\n')),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Not now')),
              FilledButton(onPressed: () { confirmed++; Navigator.pop(context); },
                child: const Text('Keep these settings')),
            ],
          )), child: const Text('Open'))),
        scale: 2, brightness: brightness, keyboard: 220));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await capture(tester, 'dialog-${brightness.name}-2x-keyboard');
      await tester.dragUntilVisible(find.text('Keep these settings'),
        find.descendant(of: find.byType(ContentDialog),
          matching: find.byType(SingleChildScrollView)), const Offset(0, -250));
      await tester.tap(find.text('Keep these settings'));
      await tester.pumpAndSettle();
      expect(confirmed, 1);
      expect(find.byType(ContentDialog), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('loading dialog preserves barrier and secondary/cancel callbacks',
      (tester) async {
    phone(tester);
    late LoadingDialogController controller;
    var canceled = 0;
    var secondary = 0;
    await tester.pumpWidget(app(Builder(builder: (context) => TextButton(
      onPressed: () {
        controller = showLoadingDialog(context, barrierDismissible: false,
          message: 'Preparing', onCancel: () => canceled++,
          onSecondary: () => secondary++, secondaryButtonText: 'Details');
      }, child: const Text('Start')))));
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    expect(tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value, 0.65);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(controller.closed, isFalse);
    expect(canceled, 0);
    controller.setProgress(0.4);
    controller.setMessage('Almost ready');
    await tester.pumpAndSettle();
    expect(find.text('Almost ready'), findsOneWidget);
    expect(tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value, 0.4);
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(secondary, 1);
    expect(canceled, 0);
    expect(controller.closed, isTrue);
    controller.setMessage('Closed updates are ignored');
    controller.close();
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(canceled, 1);
    expect(secondary, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('toast is a live region, avoids keyboard, retains action and expiry',
      (tester) async {
    phone(tester);
    final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);
    var actions = 0;
    await tester.pumpWidget(app(OverlayWidget(Builder(builder: (context) => TextButton(
      onPressed: () => showToast(context: context, message: 'Saved to your library',
        trailing: TextButton(onPressed: () => actions++, child: const Text('Undo'))),
      child: const Text('Notify')))), scale: 2, keyboard: 240));
    await tester.tap(find.text('Notify'));
    await tester.pumpAndSettle();
    final live = tester.widgetList<Semantics>(find.byType(Semantics))
      .where((widget) => widget.properties.liveRegion == true);
    expect(live, isNotEmpty);
    expect(tester.getRect(find.text('Undo')).bottom, lessThan(860 - 240));
    expect(tester.widget<Text>(find.text('Saved to your library')).maxLines, isNull);
    await capture(tester, 'toast-light-2x-keyboard');
    await tester.tap(find.text('Undo'));
    expect(actions, 1);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Saved to your library'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long error retains full message and working retry at 2x', (tester) async {
    phone(tester);
    var retries = 0;
    final message = List.filled(12, 'A useful diagnostic explanation.').join('\n');
    await tester.pumpWidget(app(NetworkError(withAppbar: false, message: message,
      retry: () => retries++, action: TextButton(onPressed: () {},
        child: const Text('Connection details'))), scale: 2, brightness: Brightness.dark));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.text(message)).maxLines, isNull);
    await capture(tester, 'error-dark-2x');
    await tester.dragUntilVisible(find.text('Retry'), find.byType(SingleChildScrollView),
      const Offset(0, -300));
    await tester.tap(find.text('Retry'));
    expect(retries, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('anchored flyout long content scrolls and pops the same route',
      (tester) async {
    phone(tester);
    var actions = 0;
    await tester.pumpWidget(app(Align(alignment: Alignment.bottomRight,
      child: Flyout(enableTap: true,
        flyoutBuilder: (context) => FlyoutContent(title: 'Source options',
          content: Text(List.filled(16, 'Readable source explanation.').join('\n')),
          actions: [FilledButton(onPressed: () { actions++; Navigator.pop(context); },
            child: const Text('Apply source'))]),
        child: const Padding(padding: EdgeInsets.all(24), child: Text('Options')))),
      scale: 2, brightness: Brightness.dark, keyboard: 200));
    await tester.tap(find.text('Options'));
    await tester.pumpAndSettle();
    expect(find.byType(FlyoutContent), findsOneWidget);
    expect(tester.takeException(), isNull);
    await capture(tester, 'flyout-dark-2x-keyboard');
    await tester.dragUntilVisible(find.text('Apply source'), find.byType(SingleChildScrollView),
      const Offset(0, -220));
    await tester.tap(find.text('Apply source'));
    await tester.pumpAndSettle();
    expect(actions, 1);
    expect(find.byType(FlyoutContent), findsNothing);
    await tester.tap(find.text('Options'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 40));
    await tester.pumpAndSettle();
    expect(find.byType(FlyoutContent), findsNothing);
    expect(actions, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sidebar keeps nondismissible barrier and result contract at 2x',
      (tester) async {
    phone(tester, size: const Size(760, 860));
    String? result;
    await tester.pumpWidget(app(Builder(builder: (context) => TextButton(
      onPressed: () async {
        result = await Navigator.of(context).push<String>(SideBarRoute<String>(
          Builder(builder: (context) => ListView(children: [
            const Text('Library actions'),
            for (var i = 0; i < 16; i++) ListTile(title: Text('Folder $i')),
            FilledButton(onPressed: () => Navigator.pop(context, 'selected'),
              child: const Text('Choose folder')),
          ])), width: 380, dismissible: false,
        ));
      }, child: const Text('Sidebar'))), scale: 2, brightness: Brightness.dark));
    await tester.tap(find.text('Sidebar'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(30, 50));
    await tester.pumpAndSettle();
    expect(find.text('Library actions'), findsOneWidget);
    expect(result, isNull);
    await capture(tester, 'sidebar-dark-2x-wide');
    await tester.dragUntilVisible(find.text('Choose folder'), find.byType(ListView),
      const Offset(0, -300));
    await tester.tap(find.text('Choose folder'));
    await tester.pumpAndSettle();
    expect(result, 'selected');
    expect(tester.takeException(), isNull);
  });

  testWidgets('popup preserves inner navigation and keeps last row above keyboard',
      (tester) async {
    phone(tester);
    const last = ValueKey('popup-last-action');
    await tester.pumpWidget(app(Builder(builder: (context) => TextButton(
      onPressed: () => showPopUpWidget<void>(context,
        PopUpWidgetScaffold(title: 'Connection', body: Builder(builder: (context) => ListView(
          children: [
            TextButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (context) => Scaffold(body: TextButton(
                onPressed: () => Navigator.pop(context), child: const Text('Inner back'))))),
              child: const Text('Inner page')),
            for (var i = 0; i < 16; i++) ListTile(title: Text('Setting $i')),
            FilledButton(key: last, onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
              child: const Text('Save connection')),
          ],
        )))), child: const Text('Popup'))), scale: 2, keyboard: 260));
    await tester.tap(find.text('Popup'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inner page'));
    await tester.pumpAndSettle();
    expect(find.text('Inner back'), findsOneWidget);
    await tester.tap(find.text('Inner back'));
    await tester.pumpAndSettle();
    expect(find.byType(PopUpWidgetScaffold), findsOneWidget);
    await tester.dragUntilVisible(find.byKey(last), find.byType(ListView), const Offset(0, -250));
    expect(tester.getRect(find.byKey(last)).bottom, lessThanOrEqualTo(860 - 260));
    await capture(tester, 'popup-light-2x-keyboard');
    await tester.tap(find.byKey(last));
    await tester.pumpAndSettle();
    expect(find.byType(PopUpWidgetScaffold), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('short dialog remains compact with ordinary entrance and close action',
      (tester) async {
    phone(tester);
    await tester.pumpWidget(app(Builder(builder: (context) => TextButton(
      onPressed: () => showDialog<void>(context: context, builder: (context) => ContentDialog(
        title: 'Saved', content: const Text('Your changes are ready.'),
        actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done'))],
      )), child: const Text('Show'))), reduce: false));
    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(SingleChildScrollView)).height, lessThan(500));
    await capture(tester, 'dialog-light-short');
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.byType(ContentDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ordinary flyout has bounded entrance and a dismissible exit', (tester) async {
    phone(tester);
    await tester.pumpWidget(app(Center(child: Flyout(
      enableTap: true,
      flyoutBuilder: (context) => const FlyoutContent(
        title: 'Quick actions', content: Text('Choose an action.'), actions: []),
      child: const Padding(padding: EdgeInsets.all(24), child: Text('Menu')),
    )), reduce: false));
    await tester.tap(find.text('Menu'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    final slide = tester.widget<SlideTransition>(find.ancestor(
      of: find.byType(FlyoutContent), matching: find.byType(SlideTransition)).first);
    expect(slide.position.value.dy, inExclusiveRange(-0.025, 0));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 40));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(find.byType(FlyoutContent), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byType(FlyoutContent), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
