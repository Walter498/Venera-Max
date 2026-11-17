import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/components/components.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/res.dart';
import 'package:venera/utils/translations.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await AppTranslation.init();
  });

  for (final enabled in [false, true]) {
    testWidgets('legacy scroll offset is not list data (enabled=$enabled)', (
      tester,
    ) async {
      final bucket = PageStorageBucket();
      final key = GlobalKey<ComicListState>();
      const path = PageStorageKey('network-fixture');
      var loads = 0;
      Widget host(Widget child) => MaterialApp(
        home: Scaffold(
          body: PageStorage(
            bucket: bucket,
            child: KeyedSubtree(key: path, child: child),
          ),
        ),
      );
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) {
              // Same slot used by ScrollPosition.saveScrollOffset. Before the fix,
              // didChangeDependencies passes this double to a nullable Map argument.
              bucket.writeState(context, 128.5);
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpWidget(
        host(
          ComicList(
            key: key,
            enablePageStorage: enabled,
            loadPage: (_) async {
              loads++;
              return const Res(<Comic>[]);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(loads, 1);
      expect(key.currentState!.state['data'], {1: <Comic>[]});
    });
  }

  testWidgets('network source/folder data never overwrite scroll offsets', (
    tester,
  ) async {
    final bucket = PageStorageBucket();
    const slotA = ('network-favorites-data', 'source-a', 'folder');
    const slotB = ('network-favorites-data', 'source-b', 'folder');
    const slotC = ('network-favorites-data', 'source-a', 'other-folder');
    const path = PageStorageKey('network-fixture');
    var loads = 0;
    Widget host(Widget child) => MaterialApp(
      home: Scaffold(
        body: PageStorage(
          bucket: bucket,
          child: KeyedSubtree(key: path, child: child),
        ),
      ),
    );
    Widget list(Object slot) => ComicList(
      key: ValueKey(slot),
      enablePageStorage: true,
      pageStorageIdentifier: slot,
      loadPage: (_) async {
        loads++;
        return const Res(<Comic>[]);
      },
    );
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) {
            bucket.writeState(context, 64.25);
            // Also tolerate previously corrupted data in the explicitly named slot.
            bucket.writeState(context, 32.5, identifier: slotA);
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pumpWidget(host(list(slotA)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final context = tester.element(find.byType(ComicList));
    expect(bucket.readState(context), 64.25);
    expect(bucket.readState(context, identifier: slotA), isA<Map>());
    expect(loads, 1);
    await tester.pumpWidget(host(list(slotB)));
    await tester.pumpAndSettle();
    await tester.pumpWidget(host(list(slotC)));
    await tester.pumpAndSettle();
    expect(loads, 3);
    await tester.pumpWidget(host(list(slotA)));
    await tester.pumpAndSettle();
    expect(loads, 3, reason: 'returning to A restores its cached page');
    expect(tester.takeException(), isNull);
  });

  testWidgets('restoration validates atomically and drops obsolete requests', (
    tester,
  ) async {
    final key = GlobalKey<ComicListState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ComicList(
            key: key,
            enablePageStorage: true,
            loadPage: (_) async => const Res(<Comic>[]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final state = key.currentState!;
    final snapshot = state.state;
    state.restoreState(snapshot);
    expect(state.state['data'], {
      1: <Comic>[],
    }, reason: 'restoring must not clear an aliased data map');
    state.restoreState({'data': 1.5, 'page': 1});
    expect(state.state['data'], {1: <Comic>[]});
    state.restoreState({
      ...snapshot,
      'loading': <int, bool>{2: true},
    });
    expect(
      state.state['loading'],
      isEmpty,
      reason: 'old State futures cannot complete after remount',
    );
    state.restoreState(2.5);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
