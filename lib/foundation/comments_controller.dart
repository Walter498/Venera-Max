import 'dart:async';

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
  Map<String, dynamic>? commentContext;

  void _mergeCommentContext(Map<String, dynamic>? value) {
    final incoming = Res.parseCommentContext(value);
    if (incoming == null) return; // Omitted later-page metadata is not a reset.
    commentContext = Map<String, dynamic>.unmodifiable({
      if (commentContext?['provider'] == incoming['provider']) ...?commentContext,
      ...incoming,
    });
  }
  bool? available;
  bool get unavailable => loaded && error == null && available == false;
  int _generation = 0;
  bool _disposed = false;
  bool _invalidated = false;
  bool _rawEmpty = false;
  bool get confirmedEmpty => loaded && error == null && _rawEmpty &&
      (total == null || total == 0) && (maxPage == null || maxPage! <= 1);
  bool get hasMore => loaded && !unavailable && (maxPage == null || page < maxPage!);

  Future<void>? _initialLoad;

  /// Probe and full-page consumers join the same first-page request.
  /// Explicit refresh still supersedes a request (e.g. a sort change).
  Future<void> ensureLoaded() {
    if (_disposed || _invalidated || loaded || error != null) return Future.value();
    return _initialLoad ??= refresh().whenComplete(() => _initialLoad = null);
  }

  Future<void> refresh({String? nextSort}) async {
    if (_disposed || _invalidated) return;
    if (nextSort != null) sort = nextSort;
    final generation = ++_generation;
    comments = []; page = 0; maxPage = null; total = null; available = null;
    commentContext = null;
    _rawEmpty = false;
    error = null; pageError = null; loaded = false;
    loading = true; loadingMore = false; notifyListeners();
    await _request(1, generation);
  }

  Future<void> loadMore() async {
    if (_disposed || _invalidated || loading || loadingMore || !hasMore) return;
    loadingMore = true; pageError = null; notifyListeners();
    await _request(page + 1, _generation);
  }

  Future<void> _request(int requestedPage, int generation) async {
    try {
      final result = await loader(requestedPage, sort);
      if (_disposed || _invalidated || generation != _generation) return;
      if (result.error) throw StateError(result.errorMessage ?? 'Comments unavailable');
      available = result.available ?? available;
      if (available == false) {
        commentContext = null;
        comments = []; page = requestedPage; maxPage = 0; total = 0;
        _rawEmpty = true; loaded = true; error = null; pageError = null;
        return;
      }
      final raw = result.data;
      _mergeCommentContext(result.commentContext);
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
      if (_disposed || _invalidated || generation != _generation) return;
      if (requestedPage == 1) { error = e.toString(); }
      else { pageError = e.toString(); }
    } finally {
      if (!_disposed && !_invalidated && generation == _generation) {
        loading = false; loadingMore = false; notifyListeners();
      }
    }
  }

  /// End a borrowed scope immediately, but notify outside build/dispose and
  /// outside an in-flight notification. The owner retains the notifier until
  /// every borrowed page has detached its listeners.
  void invalidate() {
    if (_disposed || _invalidated) return;
    _invalidated = true;
    ++_generation;
    comments = [];
    page = 0;
    maxPage = null;
    total = null;
    commentContext = null;
    available = null;
    error = null;
    pageError = null;
    loaded = false;
    loading = false;
    loadingMore = false;
    _rawEmpty = false;
    scheduleMicrotask(() {
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_generation;
    commentContext = null;
    super.dispose();
  }
}

/// New setting migration: old configurations have no key, so use 2.0x.
double chapterCommentsScale(dynamic value) => value is num && value.isFinite
    ? value.toDouble().clamp(0.5, 4.0).toDouble() : 2.0;


/// A detail-owned work discussion session, never shared with chapter/reply data.
/// A late response from an old scope cannot restore an entry in a new scope.
class DetailsCommentsSession implements Listenable {
  DetailsCommentsSession({required this.source, required this.cid,
    required this.subId, bool Function(Comment)? block})
      : revision = source.commentScopeRevision {
    controller = CommentsController(
      sort: source.preferredCommentSort(),
      block: block,
      loader: (page, sort) async {
        final result = await source.loadCommentPage(cid, subId, page, null, sort: sort);
        if (!isCurrent) return const Res.error('Source settings changed; refresh comments');
        return result;
      });
  }
  final ComicSource source;
  final String cid;
  final String? subId;
  final String revision;
  late final CommentsController controller;
  bool _disposed = false;
  bool get isCurrent => !_disposed && revision == source.commentScopeRevision;
  bool matches(ComicSource candidate, String id, String? sub) =>
      isCurrent && identical(source, candidate) && cid == id && subId == sub;

  // Pending/failed probes are not evidence of absence, but also not a reliable
  // entry point. Errors remain in the controller for diagnostics and retry.
  bool get showEntry => isCurrent && controller.loaded &&
      controller.error == null && !controller.unavailable && !controller.confirmedEmpty;
  Future<void> preload() => controller.ensureLoaded();

  int _borrowers = 0;
  bool _controllerDisposed = false;
  bool _disposeScheduled = false;

  /// Borrow before attaching widget listeners; an expired session can never
  /// reattach to a disposed notifier or silently start an old-scope request.
  bool borrow() {
    if (!isCurrent || _controllerDisposed) return false;
    ++_borrowers;
    return true;
  }

  void releaseBorrow() {
    assert(_borrowers > 0);
    --_borrowers;
    _finishDisposal();
  }

  @override
  void addListener(VoidCallback listener) => controller.addListener(listener);
  @override
  void removeListener(VoidCallback listener) => controller.removeListener(listener);

  /// Only the detail owner ends the lifetime. Borrowers merely detach.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    controller.invalidate();
    _finishDisposal();
  }

  void _finishDisposal() {
    if (!_disposed || _borrowers != 0 || _controllerDisposed || _disposeScheduled) return;
    _disposeScheduled = true;
    // Even a release from a listener must not dispose while notifying.
    scheduleMicrotask(() {
      _disposeScheduled = false;
      if (!_disposed || _borrowers != 0 || _controllerDisposed) return;
      _controllerDisposed = true;
      controller.dispose();
    });
  }
}
