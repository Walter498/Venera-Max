import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/components/components.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/foundation/favorites.dart';
import 'package:venera/foundation/history.dart';
import 'package:venera/pages/favorites/shelf_page.dart';

void main() {
  late Directory dataDirectory;
  late String oldDataPath;
  late String oldCachePath;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    dataDirectory = await Directory.systemTemp.createTemp('shelf-regression-');
    oldDataPath = App.dataPath;
    oldCachePath = App.cachePath;
    App.dataPath = dataDirectory.path;
    App.cachePath = dataDirectory.path;
    await appdata.init();
    await LocalFavoritesManager().init();
    await HistoryManager().init();
  });

  tearDownAll(() async {
    HistoryManager().close();
    LocalFavoritesManager().close();
    App.dataPath = oldDataPath;
    App.cachePath = oldCachePath;
    await dataDirectory.delete(recursive: true);
  });

  setUp(() {
    appdata.settings['shelf_folder'] = '';
  });

  Future<void> pumpShell(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final observer = NaviObserver();
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        home: NaviPane(
          paneItems: [
            PaneItemEntry(
              label: '首頁', icon: Icons.home_outlined, activeIcon: Icons.home,
            ),
            PaneItemEntry(
              label: '收藏', icon: Icons.favorite_border, activeIcon: Icons.favorite,
            ),
          ],
          paneActions: const [],
          observer: observer,
          navigatorKey: navigatorKey,
          initialPage: 1,
          pageBuilder: (_) => const ShelfPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() => appdata.saveData(false));
    });
  }

  testWidgets('real shelf tabs and repeated favorites taps return to local tab',
      (tester) async {
    await pumpShell(tester);

    expect(find.text('全部漫畫'), findsOneWidget);
    await tester.tap(find.text('足跡'));
    await tester.pumpAndSettle();
    expect(find.text('還沒有閱讀足跡'), findsOneWidget);

    // A detail-route round trip must preserve the selected shelf tab.
    // Use an offline route: a real ComicPage would load a comic source.
    final navigator = tester.state<NavigatorState>(find.byType(Navigator).last);
    navigator.push<void>(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('Offline detail route')),
    ));
    await tester.pumpAndSettle();
    navigator.pop();
    await tester.pumpAndSettle();
    expect(find.text('還沒有閱讀足跡'), findsOneWidget);

    // NaviPane.updatePage notifies listeners even when currentPage is already
    // the selected page, so this covers repeated bottom-entry taps too.
    await tester.tap(find.byIcon(Icons.favorite).last);
    await tester.pumpAndSettle();
    expect(find.text('還沒有收藏，去首頁逛逛吧'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.favorite).last);
    await tester.pumpAndSettle();
    expect(find.text('還沒有收藏，去首頁逛逛吧'), findsOneWidget);
    expect(find.text('還沒有閱讀足跡'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('local folder named 漫画 remains distinct from 全部漫畫',
      (tester) async {
    final favorites = LocalFavoritesManager();
    if (!favorites.folderNames.contains('漫画')) {
      favorites.createFolder('漫画');
    }
    await pumpShell(tester);

    await tester.tap(find.text('全部漫畫'));
    await tester.pumpAndSettle();
    expect(find.text('全部漫畫'), findsWidgets);
    expect(find.text('漫画'), findsWidgets);

    await tester.tap(find.text('漫画').last);
    await tester.pumpAndSettle();
    expect(find.text('漫画'), findsWidgets);
    expect(find.text('全部漫畫'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
