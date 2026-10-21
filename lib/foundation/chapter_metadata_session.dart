import 'dart:async';
import 'package:venera/foundation/chapter_metadata.dart';

/// One session per details-page entry. No periodic or visibility-driven fetches.
/// Network batching belongs to the source: a catalog can return every chapter
/// in one request instead of issuing duplicate catalog requests per UI card.
class ChapterMetadataSession {
  ChapterMetadataSession({required this.load, required this.onResult});

  final Future<Map<String, ChapterMetadata>> Function(List<String>) load;
  final void Function(Map<String, ChapterMetadata>) onResult;
  final Set<String> _requested = {};
  final Set<String> _pending = {};
  bool _running = false;
  bool _disposed = false;
  Future<void>? _flight;

  /// Immediately requests all unseen IDs, including collapsed/offscreen ones.
  /// Rebuilds and new detail objects only enqueue genuinely new chapters.
  Future<void> request(Iterable<String> ids) {
    if (_disposed) {
      return Future.value();
    }
    _pending.addAll(ids.where((id) => !_requested.contains(id)));
    if (_running) {
      return _flight!;
    }
    if (_pending.isEmpty) {
      return Future.value();
    }
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
      _requested.addAll(ids);
      // One bounded retry for a failed request, not a refresh timer. Missing
      // dates are never negatively cached; a new entry tries them again.
      for (var attempt = 0; attempt < 2 && !_disposed; attempt++) {
        try {
          final result = await load(ids);
          if (_disposed) {
            return;
          }
          _requested.addAll(result.keys);
          _pending.removeAll(result.keys);
          onResult(result);
          break;
        } catch (_) {
          // A failed enrichment must not block the chapter list or reader.
        }
      }
    }
  }

  void dispose() {
    _disposed = true;
    _pending.clear();
  }
}
