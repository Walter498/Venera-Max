// Run with: dart run test/author_index_checks.dart
// No Flutter, package:test, platform plugins or JS runtime are required.
import 'dart:convert';
import 'dart:io';

import '../lib/foundation/author_index.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> record(
  AuthorIndex index,
  String source,
  String id,
  Map<String, List<String>> tags, {
  String title = 'Title',
}) => index.recordDetails(
  sourceKey: source,
  comicId: id,
  title: title,
  cover: '',
  tags: tags,
);

Future<void> main() async {
  final directory = await Directory.systemTemp.createTemp('author-index-');
  try {
    final index = AuthorIndex();
    await index.init(directory.path);
    const original = ' A "Quoted" Name: with spaces, Jr. ';
    await record(index, 'one', 'id', {
      'artist': [original, original],
      'authors': [original],
      'uploader': ['Not an author'],
      'group': ['Not an author'],
    });
    await record(index, 'two', 'id', {'author': [original]});
    check(index.find('one', original).length == 1, 'Deduplicate associations');
    check(index.find('two', original).length == 1, 'Source isolation');
    check(index.find('missing', original).isEmpty, 'No cross-source results');
    check(index.find('one', original).single.author == original,
        'Preserve the author verbatim');
    check(index.find('one', original.trim()).isEmpty, 'No name normalization');
    check(index.find('one', 'Jr.').isEmpty, 'Do not split commas');
    check(index.find('one', 'Not an author').isEmpty,
        'Only explicit author namespaces');

    await record(index, 'one', 'id', {'作者': ['New'], '画师': ['New']},
        title: 'Updated');
    check(index.find('one', original).isEmpty, 'Delete obsolete associations');
    check(index.find('two', original).length == 1, 'Keep other source intact');
    check(index.find('one', 'New').single.title == 'Updated', 'Update metadata');

    // Queue multiple snapshots without awaiting individual writes.
    await Future.wait([
      record(index, 'one', 'second', {'artists': ['New']}),
      record(index, 'one', 'third', {'AUTHOR': ['New']}),
    ]);
    final restored = AuthorIndex();
    await restored.init(directory.path);
    check(restored.find('one', 'New').length == 3,
        'Serialized writes preserve the latest snapshot');
    check(restored.find('two', original).single.author == original,
        'Persist source and exact author text');

    await record(restored, 'one', 'id', {});
    final afterRemoval = AuthorIndex();
    await afterRemoval.init(directory.path);
    check(afterRemoval.find('one', 'New').length == 2,
        'Empty author tags remove old association durably');

    final file = File('${directory.path}/author_index.json');
    for (final invalid in [
      '{broken',
      jsonEncode({'version': 1, 'entries': [{'author': 42}]}),
      jsonEncode({'version': 2, 'entries': []}),
    ]) {
      await file.writeAsString(invalid);
      final recovered = AuthorIndex();
      await recovered.init(directory.path);
      check(recovered.find('one', 'New').isEmpty, 'Recover corrupt index');
      final json = jsonDecode(await file.readAsString()) as Map;
      check(json['version'] == 1 && (json['entries'] as List).isEmpty,
          'Recovery writes a valid empty index');
    }
    stdout.writeln('PASS: source isolation, original names, commas, deduplication, '
        'updates, persistence, serialized writes and corrupt-file recovery');
  } finally {
    await directory.delete(recursive: true);
  }
}
