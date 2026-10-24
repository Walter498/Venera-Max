import 'dart:math';
import 'dart:ui';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/appdata.dart';

const double _kBackGestureWidth = 19.0; // 約 0.5cm：僅邊緣可觸發返回
const int _kMaxDroppedSwipePageForwardAnimationTime = 800;
const int _kMaxPageBackAnimationTime = 300;
const double _kMinFlingVelocity = 1.0;

/// Invisible marker wrapped around every swipeable tile. The iOS-style
/// back-swipe recognizer below hit-tests for this render object: a horizontal
/// drag starting on a swipeable tile (e.g. swiping a left-opened favorite pane
/// back closed) must NOT be stolen by the page back gesture, so over a swipe
/// region the back gesture is only allowed from the screen's left edge. This
/// lets left-swipe-to-favorite and right-swipe-to-go-back coexist.
class SwipeRegionMarker extends SingleChildRenderObjectWidget {
  const SwipeRegionMarker({
    super.key,
    this.active,
    required Widget super.child,
  });

  final bool Function()? active;

  @override
  RenderSwipeRegionMarker createRenderObject(BuildContext context) =>
      RenderSwipeRegionMarker(active: active);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderSwipeRegionMarker renderObject,
  ) {
    renderObject.active = active;
  }
}

class RenderSwipeRegionMarker extends RenderProxyBox {
  RenderSwipeRegionMarker({this.active});

  bool Function()? active;

  bool get isActive => active?.call() ?? true;
}

class AppPageRoute<T> extends PageRoute<T> with _AppRouteTransitionMixin {
  /// Construct a MaterialPageRoute whose contents are defined by [builder].
  AppPageRoute({
    required this.builder,
    super.settings,
    this.maintainState = true,
    super.fullscreenDialog,
    super.allowSnapshotting = true,
    super.barrierDismissible = false,
    bool? enableIOSGesture,
    this.preventRebuild = true,
  }) : _enableIOSGestureOverride = enableIOSGesture {
    assert(opaque);
  }

  /// Builds the primary contents of the route.
  final WidgetBuilder builder;

  String? label;

  @override
  toString() => "/$label";

  @override
  Widget buildContent(BuildContext context) {
    var widget = builder(context);
    label = widget.runtimeType.toString();
    return widget;
  }

  @override
  final bool maintainState;

  @override
  String get debugLabel => '${super.debugLabel}(${settings.name})';

  /// null 時跟隨全局設置 [enableIOSBackGesture]（默認關閉）
  bool? _enableIOSGestureOverride;

  @override
  bool get enableIOSGesture =>
      _enableIOSGestureOverride ??
      (appdata.settings['enableIOSEdgeBack'] == true);

  @override
  final bool preventRebuild;
}

mixin _AppRouteTransitionMixin<T> on PageRoute<T> {
  /// Builds the primary contents of the route.
  @protected
  Widget buildContent(BuildContext context);

  @override
  Duration get transitionDuration => const Duration(milliseconds: 240);

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool canTransitionTo(TransitionRoute<dynamic> nextRoute) {
    // Don't perform outgoing animation if the next route is a fullscreen dialog.
    return nextRoute is PageRoute && !nextRoute.fullscreenDialog;
  }

  bool get enableIOSGesture;

  bool get preventRebuild;

  /// Whether the system back gesture may pop this route.
  ///
  /// #101: A route living in a nested [Navigator] keeps a *live* predictive-back
  /// gesture observer (via [PredictiveBackPageTransitionsBuilder]) even while an
  /// opaque route on an ancestor navigator covers it. On Android that lets a
  /// single system back gesture pop both the covering route *and* this buried
  /// route at once (e.g. the reader sits on the root navigator above the
  /// comic-details page in the nested "main" navigator, so one back skipped the
  /// details page). 3-button navigation didn't hit this because it routes
  /// through the single-pop `rootNavigator.maybePop()` path instead.
  ///
  /// Opt a buried route out of the gesture so only the top route pops, matching
  /// the non-predictive behaviour. The check walks up the chain of
  /// (navigator → its hosting route → that route's navigator → …): if any
  /// hosting route is no longer current, an ancestor route is covering us.
  @override
  bool get popGestureEnabled {
    if (!super.popGestureEnabled) {
      return false;
    }
    return !_isCoveredByAncestorRoute();
  }

  bool _isCoveredByAncestorRoute() {
    NavigatorState? nav = navigator;
    while (nav != null) {
      final ModalRoute<dynamic>? host = ModalRoute.of(nav.context);
      if (host == null) {
        // Reached the root navigator (no enclosing route): nothing covers us.
        return false;
      }
      if (!host.isCurrent) {
        // An opaque route on an ancestor navigator is on top of this subtree.
        return true;
      }
      nav = host.navigator;
    }
    return false;
  }

  Widget? _child;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    Widget result;

    if (preventRebuild) {
      result = _child ?? (_child = buildContent(context));
    } else {
      result = buildContent(context);
    }

    return Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      child: result,
    );
  }

  static bool _isPopGestureEnabled<T>(PageRoute<T> route) {
    if (route.isFirst ||
        route.willHandlePopInternally ||
        route.popDisposition == RoutePopDisposition.doNotPop ||
        route.fullscreenDialog ||
        route.animation!.status != AnimationStatus.completed ||
        route.secondaryAnimation!.status != AnimationStatus.dismissed ||
        !route.popGestureEnabled ||
        route.navigator!.userGestureInProgress) {
      return false;
    }

    return true;
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    PageTransitionsBuilder builder;
    if (App.isAndroid) {
      // #194: some systems force the back gesture on with no animation of
      // their own, so a page that tracks the drag looks out of place. Off keeps
      // the same fade the predictive builder already uses for non-gesture pops,
      // leaving no observer to claim the gesture — the framework then falls
      // back to a plain pop on release.
      builder = appdata.settings['enablePredictiveBack'] == false
          ? const FadeForwardsPageTransitionsBuilder()
          : const PredictiveBackPageTransitionsBuilder();
    } else {
      builder = SlidePageTransitionBuilder();
    }

    final enableEdgeBackGesture = enableIOSGesture && App.isIOS;

    return builder.buildTransitions(
      this,
      context,
      animation,
      secondaryAnimation,
      enableEdgeBackGesture
          ? IOSBackGestureDetector(
              gestureWidth: _kBackGestureWidth,
              enabledCallback: () => _isPopGestureEnabled<T>(this),
              onStartPopGesture: () => _startPopGesture(this),
              child: child,
            )
          : child,
    );
  }

  IOSBackGestureController _startPopGesture(PageRoute<T> route) {
    return IOSBackGestureController(route.controller!, route.navigator!);
  }
}

class IOSBackGestureController {
  final AnimationController controller;

  final NavigatorState navigator;

  /// Whether this controller started the navigator user gesture and therefore
  /// owns the single matching [NavigatorState.didStopUserGesture] call.
  bool _ownsUserGesture = false;

  /// The gesture has been resolved (completed / dismissed / aborted). After
  /// this no further animation may be started for this controller.
  bool _finished = false;

  bool _disposed = false;

  /// Whether this gesture has already resolved. The detector keeps the
  /// reference around so an in-flight settle animation can still be disposed
  /// with the widget; a new swipe replaces a finished controller.
  bool get isFinished => _finished;

  IOSBackGestureController(this.controller, this.navigator) {
    // Never nest user gestures: the navigator's counter must stay balanced, or
    // `userGestureInProgress` latches on and every later back swipe is refused.
    if (!navigator.userGestureInProgress) {
      _ownsUserGesture = true;
      navigator.didStartUserGesture();
    }
  }

  /// Releases the navigator user gesture exactly once, whatever path (fling,
  /// cancel, route disposed mid-gesture) got us here.
  void _finish({bool deferNotification = false}) {
    if (_finished) return;
    _finished = true;
    controller.removeStatusListener(_handleAnimationStatus);
    if (_ownsUserGesture) {
      _ownsUserGesture = false;
      void releaseGesture() {
        if (navigator.mounted) navigator.didStopUserGesture();
      }

      if (deferNotification) {
        // Detector disposal runs while the widget tree is locked. The
        // navigator's notifier rebuilds listeners, so release after unmount.
        WidgetsBinding.instance.addPostFrameCallback((_) => releaseGesture());
      } else {
        releaseGesture();
      }
    }
  }

  void _handleAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed ||
        status == AnimationStatus.dismissed) {
      _finish();
    }
  }

  /// Keeps the navigator locked until the settle animation reaches a terminal
  /// status, then releases it. If nothing is animating (zero-length animation
  /// or the pop never started), release immediately so the lock cannot leak.
  void _releaseWhenSettled() {
    if (_finished) return;
    if (!controller.isAnimating) {
      _finish();
      return;
    }
    controller.removeStatusListener(_handleAnimationStatus);
    controller.addStatusListener(_handleAnimationStatus);
  }

  void dragEnd(double velocity) {
    if (_finished || _disposed) return;

    const Curve animationCurve = Curves.fastLinearToSlowEaseIn;
    final bool animateForward;

    if (velocity.abs() >= _kMinFlingVelocity) {
      animateForward = velocity <= 0;
    } else {
      animateForward = controller.value > 0.5;
    }

    if (animateForward) {
      // Snap the page back to its resting position without popping.
      _animateToRest(animationCurve);
    } else {
      navigator.pop();
      if (_finished) return;
      if (controller.isAnimating) {
        // The pop is reversing the route animation; release on dismissal.
        _releaseWhenSettled();
      } else if (controller.value > 0.0) {
        // The pop was vetoed (the route is still here) and no animation is
        // driving the transition: put the page back instead of leaving it
        // stranded at a partial offset.
        _animateToRest(animationCurve);
      } else {
        _finish();
      }
    }
  }

  /// Aborts an in-flight interactive pop (drag cancel, second finger landing on
  /// the screen, widget disposal) and animates the page back to fully visible.
  ///
  /// This must not pop: a cancelled gesture has to leave the user on the page
  /// they were already on, never halfway between two pages.
  void cancel() {
    if (_finished || _disposed) return;
    _animateToRest(Curves.fastLinearToSlowEaseIn);
  }

  void _animateToRest(Curve curve) {
    final droppedPageForwardAnimationTime = min(
      lerpDouble(_kMaxDroppedSwipePageForwardAnimationTime, 0, controller.value)!
          .floor(),
      _kMaxPageBackAnimationTime,
    );
    controller.animateTo(
      1.0,
      duration: Duration(milliseconds: droppedPageForwardAnimationTime),
      curve: curve,
    );
    _releaseWhenSettled();
  }

  void dragUpdate(double delta) {
    if (_finished || _disposed) return;
    // A fresh drag takes over from a running settle animation; the user gesture
    // lock stays held by this controller until the drag ends.
    if (controller.isAnimating) {
      controller.stop();
    }
    // Dragging to 0.0/1.0 must not fire the settle callback mid-gesture: that
    // would release the navigator lock while the finger is still down.
    controller.removeStatusListener(_handleAnimationStatus);
    controller.value -= delta;
  }

  /// Called when the owning detector is disposed. If the gesture never resolved
  /// (the route was removed while the user was still dragging) the navigator
  /// would otherwise stay in `userGestureInProgress` forever.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (!_finished) {
      if (controller.isAnimating) {
        controller.stop();
      }
      _finish(deferNotification: true);
    }
  }
}

class IOSBackGestureDetector extends StatefulWidget {
  const IOSBackGestureDetector({
    required this.enabledCallback,
    required this.child,
    required this.gestureWidth,
    required this.onStartPopGesture,
    super.key,
  });

  final double gestureWidth;
  final bool Function() enabledCallback;
  final IOSBackGestureController Function() onStartPopGesture;
  final Widget child;

  @override
  State<IOSBackGestureDetector> createState() => _IOSBackGestureDetectorState();
}

class _IOSBackGestureDetectorState extends State<IOSBackGestureDetector> {
  IOSBackGestureController? _backGestureController;
  late _BackSwipeRecognizer _recognizer;

  @override
  void initState() {
    super.initState();
    _recognizer = _BackSwipeRecognizer(
      debugOwner: this,
      gestureWidth: widget.gestureWidth,
      isPointerInHorizontal: _isPointerInHorizontalScrollable,
      onStart: _handleDragStart,
      onUpdate: _handleDragUpdate,
      onEnd: _handleDragEnd,
      onCancel: _handleDragCancel,
    );
  }

  @override
  void dispose() {
    _recognizer.dispose();
    // A gesture still running when this detector goes away (the route was
    // popped / replaced mid-swipe) must release the navigator user gesture,
    // otherwise `userGestureInProgress` stays true and every later back swipe
    // is ignored.
    final IOSBackGestureController? controller = _backGestureController;
    _backGestureController = null;
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: {
        _BackSwipeRecognizer:
            GestureRecognizerFactoryWithHandlers<_BackSwipeRecognizer>(
              () => _recognizer,
              (instance) {
                instance.gestureWidth = widget.gestureWidth;
              },
            ),
      },
      child: widget.child,
    );
  }

  bool _isPointerInHorizontalScrollable(Offset globalPosition) {
    final HitTestResult result = HitTestResult();
    final binding = WidgetsBinding.instance;
    binding.hitTestInView(
      result,
      globalPosition,
      binding.platformDispatcher.implicitView!.viewId,
    );

    for (final entry in result.path) {
      final target = entry.target;
      // A swipeable tile (left-swipe-to-favorite, etc.) owns horizontal drags;
      // treat it like a horizontal scrollable so the back gesture only fires
      // from the true left edge over it, instead of stealing the swipe-back-to-
      // close drag and popping the page.
      if (target is RenderSwipeRegionMarker) {
        if (target.isActive) {
          return true;
        }
      } else if (target is RenderViewport) {
        if (target.axisDirection == AxisDirection.left ||
            target.axisDirection == AxisDirection.right) {
          return true;
        }
      } else if (target is RenderSliver) {
        if (target.constraints.axisDirection == AxisDirection.left ||
            target.constraints.axisDirection == AxisDirection.right) {
          return true;
        }
      } else if (target.runtimeType.toString() ==
          '_RenderSingleChildViewport') {
        try {
          final dynamic renderObject = target;
          if (renderObject.axis == Axis.horizontal) {
            return true;
          }
        } catch (e) {
          // protected
        }
      } else if (target is RenderEditable) {
        return true;
      }
    }
    return false;
  }

  void _handleDragStart(DragStartDetails details) {
    if (!mounted || !widget.enabledCallback()) return;
    final IOSBackGestureController? existing = _backGestureController;
    if (existing != null) {
      // Reuse a gesture that is still settling (so the navigator lock stays
      // balanced); otherwise replace the finished one.
      if (!existing.isFinished) return;
      existing.dispose();
      _backGestureController = null;
    }
    _backGestureController = widget.onStartPopGesture();
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (mounted && _backGestureController != null) {
      _backGestureController!.dragUpdate(
        _convertToLogical(details.primaryDelta! / context.size!.width),
      );
    }
  }

  void _handleDragEnd(DragEndDetails details) {
    final IOSBackGestureController? controller = _backGestureController;
    if (!mounted || controller == null) return;
    controller.dragEnd(
      _convertToLogical(
        details.velocity.pixelsPerSecond.dx / context.size!.width,
      ),
    );
  }

  /// The drag was aborted (pointer cancel, or a second finger landed while the
  /// swipe was in flight). Restore the page instead of resolving the drag by
  /// position/velocity, which could pop it or freeze it midway.
  void _handleDragCancel() {
    final IOSBackGestureController? controller = _backGestureController;
    if (!mounted || controller == null) return;
    // Keep the reference: the restore animation still owns the navigator user
    // gesture and must be releasable from dispose().
    controller.cancel();
  }

  double _convertToLogical(double value) {
    switch (Directionality.of(context)) {
      case TextDirection.rtl:
        return -value;
      case TextDirection.ltr:
        return value;
    }
  }
}

class _BackSwipeRecognizer extends OneSequenceGestureRecognizer {
  _BackSwipeRecognizer({
    required this.isPointerInHorizontal,
    required this.gestureWidth,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    required this.onCancel,
    super.debugOwner,
  });

  final bool Function(Offset globalPosition) isPointerInHorizontal;
  double gestureWidth;
  final ValueSetter<DragStartDetails> onStart;
  final ValueSetter<DragUpdateDetails> onUpdate;
  final ValueSetter<DragEndDetails> onEnd;
  final VoidCallback onCancel;

  Offset? _startGlobal;

  /// The single pointer that owns the current back swipe. Extra fingers that
  /// land while a swipe is in flight are ignored (never tracked) so they cannot
  /// overwrite the drag origin, the accepted flag or the velocity tracker.
  int? _activePointer;

  bool _accepted = false;

  /// Set when the swipe was aborted mid-flight (second finger) — remaining
  /// events from [_activePointer] are swallowed until it is lifted.
  bool _suppressed = false;

  bool _startedNearLeftEdge = false;

  /// Whether the drag started on top of a horizontal scrollable / swipeable
  /// tile. Recorded for diagnostics; the edge requirement already gates the
  /// gesture for every surface.
  bool _startedOverHorizontal = false;

  VelocityTracker? _velocityTracker;

  // 必須真拖動（避免連點/輕觸被判成返回手勢）
  static const double _minDistance = 12.0;

  @override
  void addPointer(PointerDownEvent event) {
    // Second (or later) touch during an active back swipe.
    //
    // Previously this re-ran the init below: `_startGlobal` jumped to the new
    // finger and `_accepted` was cleared, so the ongoing drag lost its origin
    // and the following pointer-up ran `_reset()` (which stopped tracking
    // pointer 0, i.e. the wrong pointer). No dragEnd ever reached the
    // controller, leaving the page frozen at a partial offset and the
    // navigator stuck in `userGestureInProgress`.
    //
    // iOS cancels the interactive pop when another finger touches during the
    // transition; do the same — restore the page once and swallow the rest of
    // the gesture.
    if (_activePointer != null) {
      if (_accepted && !_suppressed) {
        _suppressed = true;
        onCancel();
      }
      return;
    }

    _activePointer = event.pointer;
    startTrackingPointer(event.pointer);
    _startGlobal = event.position;
    _accepted = false;
    _suppressed = false;

    _startedNearLeftEdge = event.position.dx <= gestureWidth;
    _startedOverHorizontal = isPointerInHorizontal(event.position);

    _velocityTracker = VelocityTracker.withKind(event.kind);
    _velocityTracker?.addPosition(event.timeStamp, event.position);
  }

  @override
  void handleEvent(PointerEvent event) {
    // Ignore stray events from pointers we do not own.
    if (event.pointer != _activePointer) return;

    if (event is PointerMoveEvent || event is PointerUpEvent) {
      _velocityTracker?.addPosition(event.timeStamp, event.position);
    }

    if (event is PointerMoveEvent) {
      if (_startGlobal == null || _suppressed) return;
      final delta = event.position - _startGlobal!;
      final dx = delta.dx;
      final dy = delta.dy.abs();

      if (!_accepted) {
        if (delta.distance < _minDistance) return;

        final isRight = dx > 0;
        final isHorizontal = dx.abs() > dy * 1.5;
        // The back gesture is deliberately edge-only. Do not let a normal
        // horizontal drag in the reader or any other page become a pop.
        final bool eligible = isRight && isHorizontal && _startedNearLeftEdge;

        if (eligible) {
          _accepted = true;
          resolve(GestureDisposition.accepted);
          onStart(
            DragStartDetails(
              globalPosition: _startGlobal!,
              localPosition: event.localPosition,
            ),
          );
        } else {
          resolve(GestureDisposition.rejected);
          _reset();
          return;
        }
      }

      if (_accepted) {
        onUpdate(
          DragUpdateDetails(
            globalPosition: event.position,
            localPosition: event.localPosition,
            primaryDelta: event.delta.dx,
            delta: Offset(event.delta.dx, 0),
          ),
        );
      }
    } else if (event is PointerUpEvent) {
      // Only a swipe that was not aborted resolves through a drag end.
      if (_accepted && !_suppressed) {
        final Velocity velocity =
            _velocityTracker?.getVelocity() ?? Velocity.zero;

        onEnd(
          DragEndDetails(
            velocity: velocity,
            primaryVelocity: velocity.pixelsPerSecond.dx,
          ),
        );
      }
      _reset();
    } else if (event is PointerCancelEvent) {
      if (_accepted && !_suppressed) {
        onCancel();
      }
      _reset();
    }
  }

  void _reset() {
    final int? pointer = _activePointer;
    _activePointer = null;
    _accepted = false;
    _suppressed = false;
    _startGlobal = null;
    _startedNearLeftEdge = false;
    _startedOverHorizontal = false;
    _velocityTracker = null;
    if (pointer != null) {
      stopTrackingPointer(pointer);
    }
  }

  @override
  String get debugDescription =>
      'IOSBackSwipe(overHorizontal=$_startedOverHorizontal, '
      'nearEdge=$_startedNearLeftEdge)';

  @override
  void didStopTrackingLastPointer(int pointer) {}
}

class SlidePageTransitionBuilder extends PageTransitionsBuilder {
  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final Animation<double> primaryAnimation = App.isIOS
        ? animation
        : CurvedAnimation(parent: animation, curve: Curves.ease);
    final Animation<double> secondaryCurve = App.isIOS
        ? secondaryAnimation
        : CurvedAnimation(parent: secondaryAnimation, curve: Curves.ease);

    final wrappedChild = PhysicalModel(
      color: Colors.transparent,
      borderRadius: BorderRadius.zero,
      clipBehavior: Clip.hardEdge,
      elevation: 6,
      child: Material(child: child),
    );

    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(1, 0),
        end: Offset.zero,
      ).animate(primaryAnimation),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: Offset.zero,
          end: const Offset(-0.4, 0),
        ).animate(secondaryCurve),
        child: wrappedChild,
      ),
    );
  }
}
