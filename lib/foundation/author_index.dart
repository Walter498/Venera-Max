import 'dart:convert';
import 'dart:io';

/// A source-scoped association from an explicit author tag to a comic.
class AuthorIndexEntry {
  final String sourceKey;
  final String author;
  final String comicId;
  final String title;
  final String cover;

  const AuthorIndexEntry({
    required this.sourceKey,
    required this.author,
    required this.comicId,
    required this.title,
    required this.cover,
  });

  String get key => jsonEncode([sourceKey, author, comicId]);

  Map<String, dynamic> toJson() => {
        'sourceKey': sourceKey,
        'author': author,
        'comicId': comicId,
        'title': title,
        'cover': cover,
      };

  factory AuthorIndexEntry.fromJson(Map<String, dynamic> json) {
    return AuthorIndexEntry(
      sourceKey: json['sourceKey'] as String,
      author: json['author'] as String,
      comicId: json['comicId'] as String,
      title: json['title'] as String,
      cover: json['cover'] as String,
    );
  }
}

/// Uses only dart:io/convert so storage can be tested without Flutter or JS.
/// Names are preserved exactly; commas are part of a name, never separators.
class AuthorIndex {
  static const _namespaces = {
    'author', 'authors', 'artist', 'artists', '作者', '画师',
  };

  final Map<String, AuthorIndexEntry> _entries = {};
  File? _file;
  Future<void> _writes = Future<void>.value();

  Future<void> init(String dataPath) async {
    await _writes;
    final file = File('$dataPath/author_index.json');
    _file = file;
    _entries.clear();
    if (!await file.exists()) {
      await _persist();
      return;
    }
    try {
      final json = jsonDecode(await file.readAsString());
      if (json is! Map || json['version'] != 1 || json['entries'] is! List) {
        throw const FormatException('Invalid author index');
      }
      final loaded = <String, AuthorIndexEntry>{};
      for (final value in json['entries'] as List) {
        final entry = AuthorIndexEntry.fromJson(
          Map<String, dynamic>.from(value as Map),
        );
        loaded[entry.key] = entry;
      }
      _entries.addAll(loaded);
    } on FormatException {
      await _persist();
    } on TypeError {
      await _persist();
    }
  }

  List<AuthorIndexEntry> find(String sourceKey, String author) =>
      List.unmodifiable(_entries.values.where(
        (entry) => entry.sourceKey == sourceKey && entry.author == author,
      ));

  /// Pass ComicDetails fields explicitly, without importing its Flutter model.
  /// Replaces all old author associations for this source/comic, including when
  /// the latest details contain no explicit author tags.
  Future<void> recordDetails({
    required String sourceKey,
    required String comicId,
    required String title,
    required String cover,
    required Map<String, List<String>> tags,
  }) {
    _entries.removeWhere(
      (_, entry) => entry.sourceKey == sourceKey && entry.comicId == comicId,
    );
    for (final group in tags.entries) {
      if (!_namespaces.contains(group.key.trim().toLowerCase())) continue;
      for (final author in group.value) {
        if (author.trim().isEmpty) continue;
        final entry = AuthorIndexEntry(
          sourceKey: sourceKey,
          author: author,
          comicId: comicId,
          title: title,
          cover: cover,
        );
        _entries[entry.key] = entry;
      }
    }
    return _persist();
  }

  Future<void> _persist() {
    final file = _file;
    if (file == null) return Future<void>.value();
    final content = jsonEncode({
      'version': 1,
      'entries': _entries.values.map((entry) => entry.toJson()).toList(),
    });
    final write = _writes.then((_) async {
      await file.parent.create(recursive: true);
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(content, flush: true);
      await temporary.rename(file.path);
    });
    // A failed write is reported to its caller but must not poison the queue.
    _writes = write.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return write;
  }
}
