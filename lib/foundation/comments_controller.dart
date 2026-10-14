import 'package:flutter/foundation.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/res.dart';

/// No global source setting mutation and no App-side stale page cache.
class CommentsController extends ChangeNotifier {
  CommentsController({required this.loader, this.sort, this.block});
  final Future<Res<List<Comment>>> Function(int page, String? sort) loader;
  final bool Function(Comment)? block;
  String? sort;
  List<Comment> comments = [];
  bool loading = false, loadingMore = false, loaded = false;
  String? error, pageError;
  int page = 0;
  int? maxPage, total;
  bool? available;
  bool get unavailable => loaded && error == null && available == false;
  int _generation = 0;
  bool _disposed = false;
  bool _rawEmpty = false;
  bool get confirmedEmpty => loaded && error == null && _rawEmpty &&
      (total == null || total == 0) && (maxPage == null || maxPage <= 1);
  bool get hasMore => loaded && !unavailable && (maxPage == null || page < maxPage!);

  Future<void> refresh({String? nextSort}) async {
    if (_disposed) return;
    if (nextSort != null) sort = nextSort;
    final generation = ++_generation;
    comments = []; page = 0; maxPage = null; total = null; available = null;
    error = null; pageError = null; loaded = false;
    loading = true; loadingMore = false; notifyListeners();
    await _request(1, generation);
  }

  Future<void> loadMore() async {
    if (_disposed || loading || loadingMore || !hasMore) return;
    loadingMore = true; pageError = null; notifyListeners();
    await _request(page + 1, _generation);
  }

  Future<void> _request(int requestedPage, int generation) async {
    try {
      final result = await loader(requestedPage, sort);
      if (_disposed || generation != _generation) return;
      if (result.error) throw StateError(result.errorMessage ?? 'Comments unavailable');
      available = result.available ?? available;
      if (available == false) {
        comments = []; page = requestedPage; maxPage = 0; total = 0;
        _rawEmpty = true; loaded = true; error = null; pageError = null;
        return;
      }
      final raw = result.data;
      if (requestedPage == 1) _rawEmpty = raw.isEmpty;
      final ids = comments.map((c) => c.id).whereType<String>().toSet();
      for (final comment in raw) {
        if (block?.call(comment) == true) continue;
        if (comment.id != null && !ids.add(comment.id!)) continue;
        comments.add(comment);
      }
      page = requestedPage;
      maxPage = result.subData is int && result.subData >= requestedPage
          ? result.subData as int : maxPage;
      // An unfiltered empty response ends unknown pagination; filtering alone never does.
      if (raw.isEmpty && (maxPage == null || result.subData == 0)) maxPage = page;
      total = result.total ?? total;
      loaded = true; error = null; pageError = null;
    } catch (e) {
      if (_disposed || generation != _generation) return;
      if (requestedPage == 1) { error = e.toString(); }
      else { pageError = e.toString(); }
    } finally {
      if (!_disposed && generation == _generation) {
        loading = false; loadingMore = false; notifyListeners();
      }
    }
  }

  @override
  void dispose() { _disposed = true; ++_generation; super.dispose(); }
}

/// New setting migration: old configurations have no key, so use 2.0x.
double chapterCommentsScale(dynamic value) => value is num && value.isFinite
    ? value.toDouble().clamp(0.5, 4.0).toDouble() : 2.0;

