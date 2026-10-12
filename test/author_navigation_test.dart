import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/components/components.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/appdata.dart';
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
  comic = {$hook};
  search = {$search};
}
''';

const pageSearch = '''
  async load(keyword, options, page) {
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

  testWidgets('page jump builds author loader, excludes keyword/filter paths and returns', (tester) async {
    final source = (await tester.runAsync(() => register(pageSearch)))!;
    JsEngine().runCode('globalThis.emitAuthorComics = false;');
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(
      builder: (context) => TextButton(
        onPressed: () => PageJumpTarget(source.key, 'author', {'author': author}).jump(context),
        child: const Text('open author'),
      ),
    ))));
    await tester.tap(find.text('open author'));
    await tester.pumpAndSettle();
    expect(find.text('作者作品 · $author'), findsOneWidget);
    expect(find.byIcon(Icons.filter_alt_outlined), findsNothing);
    expect(find.byIcon(Icons.tune_rounded), findsNothing);
    final list = tester.widget<ComicList>(find.byType(ComicList));
    expect(list.loadWithFilters, isNull);
    expect(list.loadNext, isNull);
    JsEngine().runCode('globalThis.emitAuthorComics = true;');
    final second = (await tester.runAsync(() => list.loadPage!(2)))!;
    expect(second.data.single.id, 'author-2');
    expect(second.data.single.title, author);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('open author'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cursor author page keeps source identity and sorting options', (tester) async {
    final source = (await tester.runAsync(() => register('''
      optionList: [{label: "Sort", options: ["recent-Recent", "old-Old"]}],
      async loadAuthorNext(author, options, next) {
        return {comics: globalThis.emitAuthorComics === false ? [] : [
          {id: next || "first", title: author + "|" + options[0], cover: ""}
        ], next: null};
      }
    ''')))!;
    JsEngine().runCode('globalThis.emitAuthorComics = false;');
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SearchResultPage(
      text: author, author: author, sourceKey: source.key, options: const ['old'],
    ))));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.tune_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pumpAndSettle();
    // Author identities are source-local: settings expose options, no source chips.
    expect(find.byType(OptionChip), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    final list = tester.widget<ComicList>(find.byType(ComicList));
    expect(list.loadPage, isNull);
    expect(list.loadWithFilters, isNull);
    JsEngine().runCode('globalThis.emitAuthorComics = true;');
    final second = (await tester.runAsync(() => list.loadNext!('cursor-two')))!;
    expect(second.data.single.id, 'cursor-two');
    expect(second.data.single.title, '$author|old');
    expect(tester.takeException(), isNull);
  });

  testWidgets('manual search pushes ordinary mode instead of reusing author', (tester) async {
    final source = (await tester.runAsync(() => register(pageSearch)))!;
    JsEngine().runCode('globalThis.emitAuthorComics = false;');
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SearchResultPage(
      text: author, author: author, sourceKey: source.key,
    ))));
    await tester.pumpAndSettle();
    final bar = tester.widget<SliverSearchBar>(find.byType(SliverSearchBar));
    bar.controller.onSearch!('ordinary keyword');
    await tester.pumpAndSettle();
    final pages = tester.widgetList<SearchResultPage>(find.byType(SearchResultPage, skipOffstage: false));
    expect(pages.any((page) => page.author == null && page.text == 'ordinary keyword'), isTrue);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('作者作品 · $author'), findsOneWidget);
  });

  testWidgets('source without author capability shows unsupported and no ComicList', (tester) async {
    final source = (await tester.runAsync(() => register(
      'async load(keyword, options, page) { return {comics: []}; }',
    )))!;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SearchResultPage(
      text: author, author: author, sourceKey: source.key,
    ))));
    await tester.pumpAndSettle();
    expect(find.text('此源未提供作者作品查詢'), findsOneWidget);
    expect(find.byType(ComicList), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('structured artist metadata wins; arbitrary subtitle is not an author', (tester) async {
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
