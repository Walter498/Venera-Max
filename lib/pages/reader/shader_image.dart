import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:venera/foundation/image_enhance_shader.dart';

typedef ReaderEnhanceParameters = (double, double, double, double);
typedef _EnhanceSignature = (ui.Image, ReaderEnhanceParameters);

/// Applies enhancement once per successful image/parameter signature.
/// In-flight requests are singleflight per State and globally bounded; newer
/// requests replace pending ones. RawImage fit/alignment/zoom stay unchanged.
/// The original remains drawable whenever enhancement is pending/unavailable.
class EnhancedComicImage extends StatefulWidget {
  // Test seams replace only the GPU boundary/settings, never scheduling.
  @visibleForTesting
  static Future<ui.Image?> Function(ui.Image)? debugRunShader;
  @visibleForTesting
  static bool Function()? debugEnabled;
  @visibleForTesting
  static ReaderEnhanceParameters Function()? debugParameters;
  @visibleForTesting
  static int get debugRunningCount => _EnhancedComicImageState._running;
  @visibleForTesting
  static int get debugQueuedCount => _EnhancedComicImageState._queue.length;

  static bool get _enabled =>
      debugEnabled?.call() ?? ImageEnhanceShader.instance.isEnabled;

  static ReaderEnhanceParameters get _parameters {
    final manager = ImageEnhanceShader.instance;
    return debugParameters?.call() ??
        (manager.strength, manager.clarity, manager.contrast, manager.vibrance);
  }

  const EnhancedComicImage({
    super.key,
    required this.image,
    this.debugImageLabel,
    this.width,
    this.height,
    this.scale = 1.0,
    this.color,
    this.opacity,
    this.colorBlendMode,
    this.fit,
    this.alignment = Alignment.center,
    this.repeat = ImageRepeat.noRepeat,
    this.centerSlice,
    this.matchTextDirection = false,
    this.invertColors = false,
    this.isAntiAlias = false,
    this.filterQuality = FilterQuality.medium,
  });

  final ui.Image image;
  final String? debugImageLabel;
  final double? width;
  final double? height;
  final double scale;
  final Color? color;
  final Animation<double>? opacity;
  final BlendMode? colorBlendMode;
  final BoxFit? fit;
  final AlignmentGeometry alignment;
  final ImageRepeat repeat;
  final Rect? centerSlice;
  final bool matchTextDirection;
  final bool invertColors;
  final bool isAntiAlias;
  final FilterQuality filterQuality;

  @override
  State<EnhancedComicImage> createState() => _EnhancedComicImageState();
}

class _EnhancedComicImageState extends State<EnhancedComicImage> {
  /// The processed image to display, or null until ready / when disabled.
  ui.Image? _enhanced;

  // Queue entries hold States only. Clone the source only after a slot is
  // granted, while it is still owned by the mounted widget's ImageInfo.
  static const _maxRunning = 2;
  static const _maxQueued = 32;
  static int _running = 0;
  static final _queue = <_EnhancedComicImageState>[];
  bool _queued = false;
  bool _active = false;
  int _generation = 0;
  _EnhanceSignature? _wanted;
  _EnhanceSignature? _builtSignature;

  _EnhanceSignature _signature() =>
      (widget.image, EnhancedComicImage._parameters);

  @override
  void initState() {
    super.initState();
    _maybeEnhance();
  }

  @override
  void didUpdateWidget(EnhancedComicImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeEnhance();
  }

  void _unqueue() {
    if (_queued) _queue.remove(this);
    _queued = false;
  }

  void _maybeEnhance() {
    if (!EnhancedComicImage._enabled) {
      ++_generation;
      _wanted = null;
      _unqueue();
      _disposeEnhanced();
      return;
    }
    final signature = _signature();
    if (_wanted != signature) {
      ++_generation;
      _wanted = signature;
      // Do not show a previous page/parameter result while waiting.
      _disposeEnhanced();
    }
    if (_builtSignature == signature || _active || _queued) return;
    _enqueue();
  }

  void _enqueue() {
    if (!mounted || _wanted == null || _active || _queued) return;
    if (_queue.length == _maxQueued) {
      // Under extreme churn, keep the newest visible requests. An evicted
      // State displays its original and may retry on its next widget update.
      _queue.removeAt(0)._queued = false;
    }
    _queued = true;
    _queue.add(this);
    _drain();
  }

  static void _drain() {
    while (_running < _maxRunning && _queue.isNotEmpty) {
      final state = _queue.removeAt(0);
      state._queued = false;
      if (!state.mounted || state._wanted == null) continue;
      if (!EnhancedComicImage._enabled ||
          state._wanted != state._signature()) {
        state._maybeEnhance();
        continue;
      }
      ++_running;
      state._active = true;
      state._produce();
    }
  }

  Future<void> _produce() async {
    final signature = _wanted!;
    final generation = _generation;
    ui.Image? source;
    ui.Image? result;
    try {
      source = widget.image.clone();
      final runner = EnhancedComicImage.debugRunShader;
      result = await (runner != null
          ? runner(source)
          : _runShader(source, ImageEnhanceShader.instance));
      if (mounted && generation == _generation &&
          EnhancedComicImage._enabled && _signature() == signature) {
        setState(() {
          _disposeEnhanced();
          _enhanced = result;
          _builtSignature = result == null ? null : signature;
          result = null; // Ownership transferred to this State.
        });
      }
    } catch (_) {
      // Optional enhancement failure must leave the original drawable and
      // permit a later rebuild to retry, without an automatic failure loop.
    } finally {
      result?.dispose();
      source?.dispose();
      _active = false;
      --_running;
      if (mounted) {
        if (generation != _generation) {
          _enqueue(); // Only the latest coalesced request survives.
        } else if (_builtSignature == null) {
          _wanted = null; // Failed/null result can retry on next update.
        }
      }
      _drain();
    }
  }

  Future<ui.Image?> _runShader(
    ui.Image source,
    ImageEnhanceShader shaderManager,
  ) async {
    ui.FragmentShader? shader;
    ui.Picture? picture;
    try {
      shader = shaderManager.shaderFor(source);
      if (shader == null) return null;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      // Draw at native origin/size: FlutterFragCoord() then matches the
      // sampler's texel grid exactly (uv = FlutterFragCoord / uSize).
      final paint = Paint()..shader = shader;
      canvas.drawRect(
        Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
        paint,
      );
      picture = recorder.endRecording();
      return await picture.toImage(source.width, source.height);
    } catch (_) {
      return null;
    } finally {
      // Both must be released even if toImage() throws, to avoid leaking
      // native resources.
      picture?.dispose();
      shader?.dispose();
    }
  }

  void _disposeEnhanced() {
    _enhanced?.dispose();
    _enhanced = null;
    _builtSignature = null;
  }

  @override
  void dispose() {
    ++_generation;
    _wanted = null;
    _unqueue();
    _disposeEnhanced();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RawImage(
      image: _enhanced ?? widget.image,
      debugImageLabel: widget.debugImageLabel,
      width: widget.width,
      height: widget.height,
      scale: widget.scale,
      color: widget.color,
      opacity: widget.opacity,
      colorBlendMode: widget.colorBlendMode,
      fit: widget.fit,
      alignment: widget.alignment,
      repeat: widget.repeat,
      centerSlice: widget.centerSlice,
      matchTextDirection: widget.matchTextDirection,
      invertColors: widget.invertColors,
      isAntiAlias: widget.isAntiAlias,
      filterQuality: widget.filterQuality,
    );
  }
}

