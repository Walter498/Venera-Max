import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/components/components.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/foundation/author_index.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/js_engine.dart';
import 'package:venera/pages/search_result_page.dart';
import 'package:venera/utils/translations.dart';

const author = 'A "Quoted" Name: with spaces, Jr.';

String fixture(String key, String search, {String hook = ''}) => '''
class AuthorFixture extends ComicSource {
  name = "Author fixture";
  key = "$key";
  version = "1.0.0";
  minAppVersion = null;
  comic = {
    async loadInfo(id) { return {title: id, cover: "", tags: {}}; },
    $hook
  };
  search = {$search};
}
''';

const pageSearch = '''
  async load(keyword, options, page) {
    if (keyword === "ordinary keyword") return {comics: [], maxPage: 0};
    throw new Error("keyword loader must not be called in author mode");
  },
  async loadAuthor(author, options, page) {
    return {
      comics: globalThis.emitAuthorComics === false ? [] : [
        {id: "author-" + page, title: author, cover: "", tags: ["author:" + author]}
      ], maxPage: 2, total: 2
    };
  }
''';

// QuickJS dispatch and source/history file IO use real asynchronous events.
// Start builds and navigation in that zone too, not only source registration.
void testJsWidgets(
  String description,
  Future<void> Function(WidgetTester tester) body,
) {
  testWidgets(description, (tester) async {
    await tester.runAsync(() async {
      try {
        await body(tester);
      } finally {
        // Unmount before the source registry and engine are torn down.
        await tester.pumpWidget(const SizedBox.shrink());
        await appdata.saveData(false);
      }
    });
  });
}

Future<void> pumpJsFrames(WidgetTester tester) async {
  // A fake-clock-only pumpAndSettle starves native Promise dispatch. Yield a
  // real event turn between frames; a stuck loader still fails within a bound.
  for (var frame = 0; frame < 120; frame++) {
    await Future<void>.delayed(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    if (!tester.binding.hasScheduledFrame) return;
  }
  fail('Author page did not settle after 120 real async frames');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late String oldPath;
  var serial = 0;
  final registered = <String>[];

  Future<ComicSource> parse(String search, {String hook = ''}) async {
    final key = 'author_fixture_${serial++}';
    return ComicSourceParser().parse(
      fixture(key, search, hook: hook), '${temp.path}/$key.js',
    );
  }

  Future<ComicSource> register(String search) async {
    final source = await parse(search);
    expect(ComicSourceManager().add(source), isTrue);
    registered.add(source.key);
    return source;
  }

  setUpAll(() async {
    oldPath = App.dataPath;
    temp = Directory.systemTemp.createTempSync('author_navigation_');
    App.dataPath = temp.path;
    await AppTranslation.init();
    await JsEngine().init();
  });
  setUp(() {
    JsEngine().runCode('globalThis.emitAuthorComics = true;');
    appdata.settings['autoAddLanguageFilter'] = 'chinese';
    appdata.settings['blockedTags'] = <String>[];
  });
  tearDown(() {
    for (final key in registered) {
      ComicSourceManager().remove(key);
    }
    registered.clear();
  });
  tearDownAll(() async {
    // Search history writes are async; drain them before removing the temp dir.
    await appdata.saveData(false);
    JsEngine().dispose();
    App.dataPath = oldPath;
    temp.deleteSync(recursive: true);
  });

  test('real JsEngine author pages preserve quotes, spaces and page identity', () async {
    final source = await parse(pageSearch);
    final data = source.searchPageData!;
    final first = await data.loadAuthor!(author, 1, []);
    final second = await data.loadAuthor!(author, 2, []);
    expect(first.error, isFalse);
    expect(first.data.single.title, author);
    expect(first.data.single.id, 'author-1');
    expect(second.data.single.title, author);
    expect(second.data.single.id, 'author-2');
    expect(first.subData, 2);
    expect(first.total, 2);
  });

  test('author-only search does not invent loadNext; cursor remains author-specific', () async {
    final source = await parse('''
      async loadAuthorNext(author, options, next) {
        return {comics: [{id: next || "first", title: author, cover: ""}],
          next: next ? null : "cursor with spaces", total: 2};
      }
    ''');
    final data = source.searchPageData!;
    expect(data.loadPage, isNull);
    expect(data.loadNext, isNull);
    final first = await data.loadAuthorNext!(author, null, []);
    final second = await data.loadAuthorNext!(author, first.subData, []);
    expect(first.data.single.title, author);
    expect(second.data.single.title, author);
    expect(second.data.single.id, 'cursor with spaces');
    expect(second.subData, isNull);
  });

  test('author hook supports canonical and legacy target protocols', () async {
    final source = await parse(pageSearch, hook: '''
      onClickAuthor(author) { return {page: "author", attributes: {author}}; }
    ''');
    expect(source.handleClickAuthorEvent!(author)!.attributes!['author'], author);
    expect(PageJumpTarget.parse('x', {'action': 'author', 'keyword': author})
        .attributes!['author'], author);
    expect(PageJumpTarget.parse('x', 'author:$author').attributes!['author'], author);
    expect(PageJumpTarget.parse('x', 'malformed').page, 'Invalid Data');
  });

  test('malformed author data and thrown source errors become Res.error', () async {
    for (final body in [
      'return null;', 'return {comics: [null]};',
      'return {comics: [] , next: 42};',
      'return {error: "source author failure"};',
      'throw new Error("source author failure");',
    ]) {
      final source = await parse('async loadAuthor(author, options, page) {$body}');
      final result = await source.searchPageData!.loadAuthor!(author, 1, []);
      expect(result.error, isTrue, reason: body);
    }
  });

  test('empty author responses accept zero pages and optional integer totals', () async {
    for (final loader in ['loadAuthor', 'loadAuthorNext']) {
      for (final total in ['0', 'null']) {
        final source = await parse('''
          async $loader(author, options, position) {
            return {comics: [], maxPage: 0, next: null, total: $total};
          }
        ''');
        final data = source.searchPageData!;
        final result = loader == 'loadAuthor'
            ? await data.loadAuthor!(author, 1, [])
            : await data.loadAuthorNext!(author, null, []);
        expect(result.error, isFalse);
        expect(result.data, isEmpty);
        expect(result.subData, loader == 'loadAuthor' ? 0 : isNull);
        expect(result.total, total == '0' ? 0 : isNull);
      }
    }
  });

  test('author pagination and totals reject invalid types without truncation', () async {
    for (final loader in ['loadAuthor', 'loadAuthorNext']) {
      for (final fields in [
        'comics: [{id: "one", title: "One", cover: ""}], maxPage: 0',
        'comics: [], maxPage: -1',
        'comics: [], maxPage: 1.5',
        'comics: [], maxPage: "0"',
        'comics: [], total: -1',
        'comics: [], total: 1.5',
        'comics: [], total: "0"',
        'comics: [], total: true',
      ]) {
        final source = await parse('''
          async $loader(author, options, position) { return {$fields}; }
        ''');
        final data = source.searchPageData!;
        final result = loader == 'loadAuthor'
            ? await data.loadAuthor!(author, 1, [])
            : await data.loadAuthorNext!(author, null, []);
        expect(result.error, isTrue, reason: '$loader: $fields');
        expect(result.errorMessage, contains(fields.contains('total:')
            ? 'total must be a non-negative integer' : 'invalid pagination'));
      }
    }
  });

  testJsWidgets('empty author page stays scoped, has no error and never fetches again', (tester) async {
    final oldMode = appdata.settings['comicListDisplayMode'];
    addTearDown(() => appdata.settings['comicListDisplayMode'] = oldMode);
    for (final mode in ['paging', 'continuous']) {
      for (final loader in ['loadAuthor', 'loadAuthorNext']) {
        appdata.settings['comicListDisplayMode'] = mode;
        JsEngine().runCode('globalThis.emptyAuthorCalls = 0;');
        final source = await register('''
          async load(keyword, options, page) {
            throw new Error("keyword loader must not be called");
          },
          async $loader(author, options, position) {
            globalThis.emptyAuthorCalls++;
            return {comics: [], maxPage: 0, next: null, total: 0};
          }
        ''');
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: SearchResultPage(
          key: ValueKey('$mode-$loader'),
          text: author, author: author, sourceKey: source.key,
        ))));
        await pumpJsFrames(tester);
        expect(find.text('作者作品 · $author'), findsOneWidget);
        expect(find.byType(NetworkError), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        final list = tester.widget<ComicList>(find.byType(ComicList));
        expect(list.loadWithFilters, isNull);
        expect(loader == 'loadAuthor' ? list.loadNext : list.loadPage, isNull);
        await tester.drag(find.byType(CustomScrollView).first, const Offset(0, -500));
        await pumpJsFrames(tester);
        await tester.pump(const Duration(seconds: 1));
        final calls = JsEngine().runCode('globalThis.emptyAuthorCalls');
        expect(calls, 1, reason: '$mode: $loader');
        expect(tester.takeException(), isNull);
      }
    }
  });

  testJsWidgets('page jump builds author loader, excludes keyword/filter paths and returns', (tester) async {
    final source = await register(pageSearch);
    JsEngine().runCode('globalThis.emitAuthorComics = false;');
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(
      builder: (context) => TextButton(
        onPressed: () => PageJumpTarget(source.key, 'author', {'author': author}).jump(context),
        child: const Text('open author'),
      ),
    ))));
    await tester.tap(find.text('open author'));
    await pumpJsFrames(tester);
    expect(find.text('作者作品 · $author'), findsOneWidget);
    expect(find.byIcon(Icons.filter_alt_outlined), findsNothing);
    expect(find.byIcon(Icons.tune_rounded), findsNothing);
    final list = tester.widget<ComicList>(find.byType(ComicList));
    expect(list.loadWithFilters, isNull);
    expect(list.loadNext, isNull);
    JsEngine().runCode('globalThis.emitAuthorComics = true;');
    final second = await list.loadPage!(2);
    expect(second.data.single.id, 'author-2');
    expect(second.data.single.title, author);
    await tester.pageBack();
    await pumpJsFrames(tester);
    expect(find.text('open author'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testJsWidgets('cursor author page keeps source identity and sorting options', (tester) async {
    final source = await register('''
      optionList: [{label: "Sort", options: ["recent-Recent", "old-Old"]}],
      async loadAuthorNext(author, options, next) {
        return {comics: globalThis.emitAuthorComics === false ? [] : [
          {id: next || "first", title: author + "|" + options[0], cover: ""}
        ], next: null};
      }
    ''');
    JsEngine().runCode('globalThis.emitAuthorComics = false;');
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SearchResultPage(
      text: author, author: author, sourceKey: source.key, options: const ['old'],
    ))));
    await pumpJsFrames(tester);
    expect(find.byIcon(Icons.tune_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await pumpJsFrames(tester);
    // Author identities are source-local: settings expose options, no source chips.
    final optionChips = tester.widgetList<OptionChip>(find.byType(OptionChip));
    expect(optionChips.map((chip) => chip.text), ['Recent', 'Old']);
    expect(optionChips.any((chip) => chip.text == source.name), isFalse);
    await tester.pageBack();
    await pumpJsFrames(tester);
    final list = tester.widget<ComicList>(find.byType(ComicList));
    expect(list.loadPage, isNull);
    expect(list.loadWithFilters, isNull);
    JsEngine().runCode('globalThis.emitAuthorComics = true;');
    final second = await list.loadNext!('cursor-two');
    expect(second.data.single.id, 'cursor-two');
    expect(second.data.single.title, '$author|old');
    expect(tester.takeException(), isNull);
  });

  testJsWidgets('manual search pushes ordinary mode instead of reusing author', (tester) async {
    final source = await register(pageSearch);
    JsEngine().runCode('globalThis.emitAuthorComics = false;');
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SearchResultPage(
      text: author, author: author, sourceKey: source.key,
    ))));
    await pumpJsFrames(tester);
    final bar = tester.widget<SliverSearchBar>(find.byType(SliverSearchBar));
    bar.controller.onSearch!('ordinary keyword');
    await pumpJsFrames(tester);
    final pages = tester.widgetList<SearchResultPage>(find.byType(SearchResultPage, skipOffstage: false));
    expect(pages.any((page) => page.author == null && page.text == 'ordinary keyword'), isTrue);
    await tester.pageBack();
    await pumpJsFrames(tester);
    expect(find.text('作者作品 · $author'), findsOneWidget);
  });

  testJsWidgets('source without author capability shows local author results', (tester) async {
    final source = await register(
      'async load(keyword, options, page) { return {comics: []}; }',
    );
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SearchResultPage(
      text: author, author: author, sourceKey: source.key,
    ))));
    await pumpJsFrames(tester);
    expect(find.text('作者作品 · $author'), findsOneWidget);
    expect(find.text('查找更多（關鍵詞候選）'), findsOneWidget);
    expect(find.byType(ComicList), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SearchResultPage(
      key: const ValueKey('local-author-fixture'),
      text: author,
      author: author,
      sourceKey: source.key,
      localAuthorResults: [
        AuthorIndexEntry(
          sourceKey: source.key, author: author, comicId: 'opened',
          title: 'Already opened', cover: '',
        ),
        const AuthorIndexEntry(
          sourceKey: 'other-source', author: author, comicId: 'foreign',
          title: 'Other source', cover: '',
        ),
      ],
    ))));
    await pumpJsFrames(tester);
    final list = tester.widget<ComicList>(find.byType(ComicList));
    final result = await list.loadPage!(1);
    expect(result.data.map((comic) => comic.id), ['opened']);
    expect(result.data.single.sourceKey, source.key);
    expect(result.total, 1);
    expect(tester.takeException(), isNull);
  });

  testJsWidgets('structured artist metadata wins; arbitrary subtitle is not an author', (tester) async {
    final tapped = <String>[];
    Widget description(List<String> tags) => MaterialApp(home: Scaffold(body: ComicDescription(
      title: 'Title', subtitle: 'Ongoing, English', description: '',
      tags: tags, enableTranslate: false,
      onTapAuthor: (name, _) => tapped.add(name),
    )));
    await tester.pumpWidget(description(['artist:$author']));
    await tester.tap(find.text(author));
    expect(tapped, [author]);
    await tester.pumpWidget(description([]));
    expect(find.text('Ongoing'), findsNothing);
    expect(find.text('English'), findsNothing);
  });
}
