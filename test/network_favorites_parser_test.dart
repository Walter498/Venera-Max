import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/js_engine.dart';
import 'package:venera/utils/translations.dart';

// Real QuickJS Promise -> ComicSourceParser -> Comic.fromJson regression.
// This source only exists in tests; production favorites always call their
// configured source and are never replaced with these responses.
String sourceScript(String key) =>
    '''
class FavoritesBoundaryFixture extends ComicSource {
  name = "Favorites boundary fixture";
  key = "$key";
  version = "1.0.0";
  minAppVersion = null;
  favorites = {
    multiFolder: true,
    async loadFolders(id) {
      return {folders: {one: "First folder"}, favorited: id ? ["one"] : []};
    },
    async loadComics(page, folder) {
      if (globalThis.invalidFavoriteResponse) return {comics: [1.5], maxPage: 2};
      return {comics: [new Comic({
        id: "page-" + page, title: folder || "Ungrouped", cover: "",
        tags: ["tag"], favoriteId: "fav-1", stars: 4.5
      })], maxPage: 2};
    },
    async loadNext(next, folder) {
      if (globalThis.invalidFavoriteResponse) return {comics: [1.5], next: null};
      return {comics: [new Comic({
        id: next || "first", title: folder || "Ungrouped", cover: "",
        favoriteId: "fav-2", stars: 3.5
      })], next: next ? null : "second"};
    }
  };
}
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late String oldPath;
  late ComicSource source;

  setUpAll(() async {
    oldPath = App.dataPath;
    temp = Directory.systemTemp.createTempSync('favorites-boundary-');
    App.dataPath = temp.path;
    await AppTranslation.init();
    await JsEngine().init();
    source = await ComicSourceParser().parse(
      sourceScript('favorites_boundary_fixture'),
      '${temp.path}/fixture.js',
    );
    expect(ComicSourceManager().add(source), isTrue);
    source.data['account'] = ['test-only'];
  });
  setUp(
    () => JsEngine().runCode('globalThis.invalidFavoriteResponse = false;'),
  );
  tearDownAll(() async {
    ComicSourceManager().remove(source.key);
    await appdata.saveData(false);
    JsEngine().dispose();
    App.dataPath = oldPath;
    temp.deleteSync(recursive: true);
  });

  test(
    'numbered favorites preserve valid fractional stars and metadata',
    () async {
      final data = source.favoriteData!;
      final folders = await data.loadFolders!('work');
      expect(folders.data, {'one': 'First folder'});
      expect(folders.subData, ['one']);
      for (final folder in <String?>[null, 'one']) {
        final result = await data.loadComic!(1, folder);
        expect(result.error, isFalse);
        expect(result.subData, 2);
        expect(result.data.single.id, 'page-1');
        expect(result.data.single.title, folder ?? 'Ungrouped');
        expect(result.data.single.stars, 4.5);
        expect(result.data.single.favoriteId, 'fav-1');
        expect(result.data.single.sourceKey, source.key);
      }
    },
  );

  test('cursor favorites keep cursor and fractional stars', () async {
    final data = source.favoriteData!;
    final first = await data.loadNext!(null, 'one');
    expect(first.error, isFalse);
    expect(first.data.single.id, 'first');
    expect(first.data.single.stars, 3.5);
    expect(first.subData, 'second');
    final second = await data.loadNext!(first.subData, 'one');
    expect(second.error, isFalse);
    expect(second.data.single.id, 'second');
    expect(second.subData, isNull);
  });

  test(
    'invalid JS items become explicit errors on both loading paths',
    () async {
      JsEngine().runCode('globalThis.invalidFavoriteResponse = true;');
      final numbered = await source.favoriteData!.loadComic!(1, 'one');
      final cursor = await source.favoriteData!.loadNext!(null, 'one');
      for (final result in [numbered, cursor]) {
        expect(result.error, isTrue);
        expect(result.errorMessage, contains('comics[0] must be an object'));
        expect(result.errorMessage, isNot(contains('is not a subtype')));
        expect(result.dataOrNull, isNull);
      }
    },
  );
}
