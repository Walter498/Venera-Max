import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:venera/foundation/cache_manager.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/image_translation/rate_limiter.dart';
import 'package:venera/foundation/js_engine.dart';
import 'package:venera/foundation/consts.dart';
import 'package:venera/utils/translations.dart';
import 'package:venera/utils/image.dart';
import 'package:venera/foundation/image_provider/avif_fallback.dart';

import 'app_dio.dart';

const _imageStreamIdleTimeout = Duration(seconds: 30);

abstract class ImageDownloader {
  /// Disk cache key for a thumbnail/cover. Callers that may need to evict a
  /// corrupted entry must build the key through this, not by hand: a key that
  /// differs from the one used to write makes eviction a no-op, and bad bytes
  /// then survive forever because [loadThumbnail] serves the cache first.
  static String thumbnailCacheKey(
    String url,
    String? sourceKey, [
    String? cid,
  ]) => "$url@$sourceKey${cid != null ? '@$cid' : ''}";

  /// Disk cache key for a comic page. Same contract as [thumbnailCacheKey].
  /// Deliberately excludes resize/translation state: those change the provider
  /// identity, not the bytes stored on disk.
  static String imageCacheKey(
    String imageKey,
    String? sourceKey,
    String cid,
    String eid,
  ) => "$imageKey@$sourceKey@$cid@$eid";

  static Stream<ImageDownloadProgress> loadThumbnail(
    String url,
    String? sourceKey, [
    String? cid,
  ]) async* {
    // A locally stored cover (a collection's custom cover, or one borrowed from
    // a downloaded member) can't go through the HTTP client: it rejects the
    // file scheme, which failed the whole download task (#206).
    if (url.startsWith('file://')) {
      var file = File(url.substring(7));
      if (!await file.exists()) {
        throw "Cover file not found".tl;
      }
      var data = await file.readAsBytes();
      yield ImageDownloadProgress(
        currentBytes: data.length,
        totalBytes: data.length,
        imageBytes: data,
      );
      return;
    }

    final cacheKey = thumbnailCacheKey(url, sourceKey, cid);
    final cache = await CacheManager().findCache(cacheKey);

    if (cache != null) {
      var data = await cache.readAsBytes();
      yield ImageDownloadProgress(
        currentBytes: data.length,
        totalBytes: data.length,
        imageBytes: data,
      );
    }

    var configs = <String, dynamic>{};
    if (sourceKey != null) {
      var comicSource = ComicSource.find(sourceKey);
      configs =
          (await comicSource?.getThumbnailLoadingConfig?.call(url, cid)) ?? {};
    }
    configs['headers'] ??= {};
    if (configs['headers']['user-agent'] == null &&
        configs['headers']['User-Agent'] == null) {
      configs['headers']['user-agent'] = webUA;
    }

    if (((configs['url'] as String?) ?? url).startsWith('cover.') &&
        sourceKey != null) {
      var comicSource = ComicSource.find(sourceKey);
      if (comicSource != null) {
        var comicInfo = await comicSource.loadComicInfo!(cid!);
        yield* loadThumbnail(comicInfo.data.cover, sourceKey);
        return;
      }
    }

    var dio = AppDio(
      BaseOptions(
        headers: Map<String, dynamic>.from(configs['headers']),
        method: configs['method'] ?? 'GET',
        responseType: ResponseType.stream,
      ),
    );

    String requestUrl = configs['url'] ?? url;
    if (requestUrl.startsWith('//')) {
      requestUrl = 'https:$requestUrl';
    }
    var req = await dio.request<ResponseBody>(
      requestUrl,
      data: configs['data'],
    );
    var stream = req.data?.stream ?? (throw "Error: Empty response body.");
    int? expectedBytes = req.data!.contentLength;
    if (expectedBytes == -1) {
      expectedBytes = null;
    }
    var buffer = <int>[];
    await for (var data in stream.timeout(_imageStreamIdleTimeout)) {
      buffer.addAll(data);
      if (expectedBytes != null) {
        yield ImageDownloadProgress(
          currentBytes: buffer.length,
          totalBytes: expectedBytes,
        );
      }
    }

    // Matches the comic-image path below: an async hook must be awaited, and an
    // unchecked return would cache a Future/JS object as if it were image bytes.
    if (configs['onResponse'] is JSInvokable) {
      dynamic result = (configs['onResponse'] as JSInvokable)([
        Uint8List.fromList(buffer),
      ]);
      if (result is Future) {
        result = await result;
      }
      if (result is List<int>) {
        buffer = result;
      } else {
        throw "Error: Invalid onResponse result.";
      }
      (configs['onResponse'] as JSInvokable).free();
    }

    await CacheManager().writeCache(cacheKey, buffer);
    yield ImageDownloadProgress(
      currentBytes: buffer.length,
      totalBytes: buffer.length,
      imageBytes: Uint8List.fromList(buffer),
    );
  }

  static final _loadingImages =
      <String, _StreamWrapper<ImageDownloadProgress>>{};

  /// Cancel all loading images.
  static void cancelAllLoadingImages() {
    for (var wrapper in _loadingImages.values) {
      wrapper.cancel();
    }
    _loadingImages.clear();
  }

  /// Load a comic image from the network or cache.
  /// The function will prevent multiple requests for the same image.
  static Stream<ImageDownloadProgress> loadComicImage(
    String imageKey,
    String? sourceKey,
    String cid,
    String eid, {
    void Function(Duration? retryAfter)? onRateLimited,
  }) {
    // AVIF 曾解碼失敗 → 自動改用 WebP
    imageKey = AvifFallbackRegistry.instance.applyFallback(imageKey);
    final cacheKey = imageCacheKey(imageKey, sourceKey, cid, eid);
    if (_loadingImages.containsKey(cacheKey)) {
      return _loadingImages[cacheKey]!.stream;
    }
    final stream = _StreamWrapper<ImageDownloadProgress>(
      _loadComicImage(imageKey, sourceKey, cid, eid, false, onRateLimited),
      (wrapper) {
        _loadingImages.remove(cacheKey);
      },
      isReplayable: (progress) => progress.imageBytes != null,
    );
    _loadingImages[cacheKey] = stream;
    return stream.stream;
  }

  static Stream<ImageDownloadProgress> loadComicImageUnwrapped(
    String imageKey,
    String? sourceKey,
    String cid,
    String eid, {
    bool forDownload = false,
  }) {
    return _loadComicImage(imageKey, sourceKey, cid, eid, forDownload);
  }

  static Stream<ImageDownloadProgress> _loadComicImage(
    String imageKey,
    String? sourceKey,
    String cid,
    String eid, [
    bool forDownload = false,
    void Function(Duration? retryAfter)? onRateLimited,
  ]) async* {
    // AVIF 曾解碼失敗 → 自動改用 WebP
    imageKey = AvifFallbackRegistry.instance.applyFallback(imageKey);
    final cacheKey = imageCacheKey(imageKey, sourceKey, cid, eid);
    final cache = await CacheManager().findCache(cacheKey);

    if (cache != null) {
      var data = await cache.readAsBytes();
      yield ImageDownloadProgress(
        currentBytes: data.length,
        totalBytes: data.length,
        imageBytes: data,
      );
      // A download reuses an already-cached image instead of re-fetching it,
      // and never re-caches (avoids double-writing the bytes to disk and
      // evicting the reader's prefetch cache) — see #4 / #17.
      if (forDownload) return;
    }

    Future<Map<String, dynamic>?> Function()? onLoadFailed;

    var configs = <String, dynamic>{};
    if (sourceKey != null) {
      var comicSource = ComicSource.find(sourceKey);
      configs =
          (await comicSource!.getImageLoadingConfig?.call(
            imageKey,
            cid,
            eid,
          )) ??
          {};
    }
    var retryLimit = 5;
    var netRetries = 3;
    // 泛用修復（栗子方案的推廣）：這次載入是否已經重新向源要過頁面清單。
    var refreshedPageList = false;
    while (true) {
      try {
        // 統一帶 UA：原本用 ??= ，只要源回傳的 headers 不是 null（例如回空 map
        // 或只帶自己的 header），UA 就補不上 → 下載內頁變成裸請求 → CDN 回
        // 403/404（閱讀走源 headers 所以正常）。這裡改成「缺 UA 就補」，
        // 讓閱讀與下載走完全相同的請求形狀。
        configs['headers'] ??= <String, dynamic>{};
        var headers = Map<String, dynamic>.from(configs['headers'] as Map);
        var hasUA = false;
        for (var key in headers.keys) {
          if (key.toString().toLowerCase() == 'user-agent') {
            hasUA = true;
            break;
          }
        }
        if (!hasUA) {
          headers['user-agent'] = webUA;
        }
        configs['headers'] = headers;

        if (configs['onLoadFailed'] is JSInvokable) {
          onLoadFailed = () async {
            dynamic result = (configs['onLoadFailed'] as JSInvokable)([]);
            if (result is Future) {
              result = await result;
            }
            if (result is! Map<String, dynamic>) return null;
            return result;
          };
        }

        var dio = AppDio(
          BaseOptions(
            headers: configs['headers'],
            method: configs['method'] ?? 'GET',
            responseType: ResponseType.stream,
          ),
        );

        var req = await dio.request<ResponseBody>(
          configs['url'] ?? imageKey,
          data: configs['data'],
        );
        var stream = req.data?.stream ?? (throw "Error: Empty response body.");
        int? expectedBytes = req.data!.contentLength;
        if (expectedBytes == -1) {
          expectedBytes = null;
        }
        var buffer = <int>[];
        await for (var data in stream.timeout(_imageStreamIdleTimeout)) {
          buffer.addAll(data);
          yield ImageDownloadProgress(
            currentBytes: buffer.length,
            totalBytes: expectedBytes,
          );
        }

        if (configs['onResponse'] is JSInvokable) {
          dynamic result = (configs['onResponse'] as JSInvokable)([
            Uint8List.fromList(buffer),
          ]);
          if (result is Future) {
            result = await result;
          }
          if (result is List<int>) {
            buffer = result;
          } else {
            throw "Error: Invalid onResponse result.";
          }
          (configs['onResponse'] as JSInvokable).free();
        }

        Uint8List data;
        if (buffer is Uint8List) {
          data = buffer;
        } else {
          data = Uint8List.fromList(buffer);
          buffer.clear();
        }

        if (configs['modifyImage'] != null) {
          var newData = await modifyImageWithScript(
            data,
            configs['modifyImage'],
          );
          data = newData;
        }

        if (!forDownload) {
          await CacheManager().writeCache(cacheKey, data);
        }
        yield ImageDownloadProgress(
          currentBytes: data.length,
          totalBytes: data.length,
          imageBytes: data,
        );
        return;
      } catch (e) {
        // The source's own recovery hook takes priority over the generic
        // net-retry below: onLoadFailed is how a source re-signs / refreshes an
        // expired image URL, which typically surfaces as a 403/401 (a
        // clientError). Letting the classifier fast-fail those before the hook
        // ran would silently break every source that relies on URL refresh, so
        // the hook gets first crack at ANY error — the original behavior.
        if (retryLimit >= 0 && onLoadFailed != null) {
          var newConfig = await onLoadFailed();
          (configs['onLoadFailed'] as JSInvokable).free();
          onLoadFailed = null;
          if (newConfig == null) {
            rethrow;
          }
          configs = newConfig;
          retryLimit--;
          continue;
        }
        // A hook exists but its retry budget is spent: rethrow, matching the
        // original behavior. (Falling through to net-retry here would re-free
        // and re-wrap the hook's JSInvokable across loops.)
        if (onLoadFailed != null) {
          rethrow;
        }
        // No source-provided recovery: retry transient/rate-limited errors a
        // bounded number of times with backoff (429/503/网络抖动/5xx). This is
        // the only retry chance for sources without an onLoadFailed hook.
        var status = e is DioException ? e.response?.statusCode : null;
        var cls = status != null
            ? classifyStatus(status)
            : HttpErrorClass.transient;
        if ((cls == HttpErrorClass.rateLimited ||
                cls == HttpErrorClass.transient) &&
            netRetries > 0) {
          netRetries--;
          Duration? ra;
          if (cls == HttpErrorClass.rateLimited) {
            ra = e is DioException
                ? parseRetryAfter(e.response?.headers.value('retry-after'))
                : null;
            onRateLimited?.call(ra);
          }
          await Future.delayed(backoff(2 - netRetries, retryAfter: ra));
          continue;
        }
        // 403/404 這類客戶端錯誤，多半是「源給的頁面清單過期」——例如舊版
        // 探測把 CDN 占位圖當真圖而高估頁數（栗子下載 404 的根因）。
        // 這裡給一次機會：重新向源要一次本章頁面清單，用新清單裡的同位置
        // URL 再試一次。只做一次，避免無限重試；不影響其他錯誤的快速失敗。
        if ((status == 403 || status == 404) &&
            !refreshedPageList &&
            sourceKey != null &&
            cid != null &&
            eid != null) {
          refreshedPageList = true;
          final refreshed = await _refreshComicPageUrl(
            sourceKey!,
            cid!,
            eid!,
            imageKey,
          );
          if (refreshed != null && refreshed != imageKey) {
            // 只換 URL，保留源原本的 headers / hooks
            configs = Map<String, dynamic>.from(configs)
              ..['url'] = refreshed;
            continue;
          }
        }
        // 4xx（非 429）或重试次数耗尽：重试无益，快速失败。
        rethrow;
      } finally {
        if (onLoadFailed != null) {
          (configs['onLoadFailed'] as JSInvokable).free();
        }
      }
    }
  }
}

/// A wrapper class for a stream that
/// allows multiple listeners to listen to the same stream.
class _StreamWrapper<T> {
  final Stream<T> _stream;

  final List<StreamController> controllers = [];

  final void Function(_StreamWrapper<T> wrapper) onClosed;

  final bool Function(T data)? isReplayable;

  bool isClosed = false;

  bool _hasReplayableData = false;

  late T _replayableData;

  _StreamWrapper(this._stream, this.onClosed, {this.isReplayable}) {
    _listen();
  }

  void _listen() async {
    try {
      await for (var data in _stream) {
        if (isClosed) {
          break;
        }
        if (isReplayable?.call(data) ?? false) {
          _replayableData = data;
          _hasReplayableData = true;
        }
        for (var controller in controllers) {
          if (!controller.isClosed) {
            controller.add(data);
          }
        }
      }
    } catch (e) {
      for (var controller in controllers) {
        if (!controller.isClosed) {
          controller.addError(e);
        }
      }
    } finally {
      for (var controller in controllers) {
        if (!controller.isClosed) {
          controller.close();
        }
      }
    }
    controllers.clear();
    isClosed = true;
    onClosed(this);
  }

  Stream<T> get stream {
    if (isClosed) {
      throw Exception('Stream is closed');
    }
    var controller = StreamController<T>();
    controllers.add(controller);
    controller.onCancel = () {
      controllers.remove(controller);
    };
    if (_hasReplayableData) {
      controller.add(_replayableData);
    }
    return controller.stream;
  }

  void cancel() {
    for (var controller in controllers) {
      controller.close();
    }
    controllers.clear();
    isClosed = true;
  }
}

class ImageDownloadProgress {
  final int currentBytes;

  final int? totalBytes;

  final Uint8List? imageBytes;

  const ImageDownloadProgress({
    required this.currentBytes,
    required this.totalBytes,
    this.imageBytes,
  });
}

/// 重新向漫畫源要一次「本章頁面清單」，回傳 [imageKey] 這一頁的新 URL。
///
/// 用途：圖片回 403/404 時，通常是源快取下來的頁面清單已經過期（頁數被高估、
/// 或圖片線路換了）。與其直接失敗，重新解析一次往往就能拿到正確 URL。
/// 找不到對應頁面時回傳 null，呼叫端照原本的錯誤處理走。
Future<String?> _refreshComicPageUrl(
  String sourceKey,
  String cid,
  String eid,
  String imageKey,
) async {
  try {
    final source = ComicSource.find(sourceKey);
    final loader = source?.loadComicPages;
    if (loader == null) return null;
    final res = await loader(cid, eid);
    if (!res.success) return null;
    final list = res.data;
    if (list.isEmpty) return null;
    // 先按原本的位置對應
    final index = list.indexOf(imageKey);
    if (index >= 0) return list[index];
    // 位置對不上（清單長度變了）：用檔名比對
    final name = imageKey.split('/').last;
    for (final url in list) {
      if (url.endsWith('/$name')) return url;
    }
    return null;
  } catch (_) {
    return null;
  }
}
