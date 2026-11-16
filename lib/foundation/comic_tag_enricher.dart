import 'package:flutter/foundation.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';

/// Completes sparse list tags with the source's detail tags, without assuming
/// any source-specific protocol. Results are cached by source + comic id.
class ComicTagEnricher extends ChangeNotifier {
  ComicTagEnricher._();
  static final instance = ComicTagEnricher._();
  final _tags = <String, Set<String>>{};
  final _pending = <String, Future<void>>{};

  Set<String> tagsFor(Comic comic) =>
      _tags['${comic.sourceKey}:${comic.id}'] ??
      {for (final tag in comic.tags ?? const <String>[]) tag.trim()};

  Future<void> enrich(Comic comic) {
    final key = '${comic.sourceKey}:${comic.id}';
    if (_tags.containsKey(key)) return Future.value();
    return _pending[key] ??= _load(key, comic).whenComplete(() => _pending.remove(key));
  }

  Future<void> _load(String key, Comic comic) async {
    final loader = ComicSource.find(comic.sourceKey)?.loadComicInfo;
    if (loader == null) {
      _tags[key] = tagsFor(comic);
      return;
    }
    try {
      final result = await loader(comic.id);
      if (result.success) {
        final full = <String>{};
        for (final entry in result.data.tags.entries) {
          for (final value in entry.value) {
            final clean = value.trim();
            if (clean.isNotEmpty) full.add(clean);
          }
        }
        _tags[key] = full.isEmpty ? tagsFor(comic) : full;
      } else {
        _tags[key] = tagsFor(comic);
      }
    } catch (_) {
      _tags[key] = tagsFor(comic);
    }
    notifyListeners();
  }
}
