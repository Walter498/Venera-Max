import 'dart:async';
import 'package:venera/foundation/chapter_metadata.dart';

/// One session per details-page entry. Requests are bounded so providers with
/// catalog limits cannot silently truncate the tail of a large chapter list.
class ChapterMetadataSession {
  ChapterMetadataSession({required this.load, required this.onResult});

  static const _batchSize = 512;
  static const _retryDepth = 3;

  final Future<Map<String, ChapterMetadata>> Function(List<String>) load;
  final void Function(Map<String, ChapterMetadata>) onResult;
  final Set<String> _requested = {};
  final Set<String> _unavailable = {};
  final Set<String> _pending = {};
  bool _running = false;
  bool _disposed = false;
  Future<void>? _flight;

  Future<void> request(Iterable<String> ids) {
    if (_disposed) return Future.value();
    _pending.addAll(ids.where((id) =>
        !_requested.contains(id) && !_unavailable.contains(id)));
    if (_running) return _flight!;
    if (_pending.isEmpty) return Future.value();
    _running = true;
    final done = Completer<void>();
    _flight = done.future;
    unawaited(_drain().whenComplete(() {
      _running = false;
      done.complete();
    }));
    return done.future;
  }

  Future<void> _drain() async {
    while (!_disposed && _pending.isNotEmpty) {
      final ids = _pending.toList(growable: false);
      _pending.clear();
      for (var start = 0; start < ids.length; start += _batchSize) {
        if (_disposed) return;
        final end = (start + _batchSize).clamp(0, ids.length).toInt();
        await _loadBatch(ids.sublist(start, end), depth: 0);
      }
    }
  }

  Future<void> _loadBatch(List<String> ids, {required int depth}) async {
    if (_disposed || ids.isEmpty) return;
    var unresolved = List<String>.from(ids);
    var receivedResponse = false;
    for (var attempt = 0; attempt < 2 && unresolved.isNotEmpty; attempt++) {
      try {
        final result = await load(List<String>.from(unresolved));
        receivedResponse = true;
        if (_disposed) return;
        final returned = result.keys.toSet();
        _requested.addAll(returned);
        unresolved = unresolved.where((id) => !returned.contains(id)).toList();
        if (result.isNotEmpty) onResult(result);
        if (unresolved.length == 1) break;
      } catch (_) {
        // Retry the same bounded request once. A failed enrichment must not
        // block the chapter list or reader.
      }
    }
    if (!receivedResponse || _disposed || unresolved.isEmpty || depth >= _retryDepth) {
      return;
    }
    if (unresolved.length == 1) {
      _unavailable.add(unresolved.single);
      return;
    }
    // A provider may cap or partially answer a request without throwing. Split
    // the missing IDs so the tail can still be enriched; unresolved singleton
    // IDs are left unrequested and can be retried by a later request().
    final split = unresolved.length > 1
        ? (unresolved.length + 1) ~/ 2
        : unresolved.length;
    for (var start = 0; start < unresolved.length; start += split) {
      final end = (start + split).clamp(0, unresolved.length).toInt();
      await _loadBatch(unresolved.sublist(start, end), depth: depth + 1);
    }
  }

  void dispose() {
    _disposed = true;
    _pending.clear();
  }
}
