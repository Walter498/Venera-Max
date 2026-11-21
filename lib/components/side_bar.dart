part of 'components.dart';

class SideBarRoute<T> extends PopupRoute<T> {
  SideBarRoute(
    this.widget, {
    this.showBarrier = true,
    this.useSurfaceTintColor = false,
    this.dismissible = true,
    required this.width,
    this.addBottomPadding = true,
    this.addTopPadding = true,
  });

  final Widget widget;

  final bool showBarrier;

  final bool useSurfaceTintColor;

  final bool dismissible;

  final double width;

  final bool addTopPadding;

  final bool addBottomPadding;

  bool _barrierSawPointerDown = false;

  @override
  Color? get barrierColor =>
      showBarrier ? const Color(0x33000000) : Colors.transparent;

  @override
  bool get barrierDismissible => dismissible;

  @override
  String? get barrierLabel => "exit";

  @override
  TickerFuture didPush() {
    _barrierSawPointerDown = false;
    return super.didPush();
  }

  @override
  Widget buildModalBarrier() {
    if (!showBarrier) {
      return const SizedBox.shrink();
    }
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) {
        if (event.position == Offset.zero) {
          return;
        }
        _barrierSawPointerDown = true;
      },
      child: ModalBarrier(
        dismissible: dismissible,
        onDismiss: dismissible
            ? () {
                if (!_barrierSawPointerDown) {
                  return;
                }
                navigator?.maybePop();
              }
            : null,
        color: barrierColor,
        semanticsLabel: barrierLabel,
      ),
    );
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    bool showSideBar = MediaQuery.sizeOf(context).width > width;

    Widget body = widget;

    if (addTopPadding) {
      body = Padding(
        padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
        child: MediaQuery.removePadding(
          context: context,
          removeTop: true,
          child: body,
        ),
      );
    }

    final sideBarWidth = math.min(width, MediaQuery.sizeOf(context).width);

    final tokens = VeneraDesignTokens.of(context);
    body = Container(
      decoration: BoxDecoration(
        borderRadius: showSideBar
            ? BorderRadius.horizontal(left: Radius.circular(tokens.sectionRadius))
            : null,
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        border: showSideBar ? Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ) : null,
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.shadow.withValues(alpha: .14),
            blurRadius: 18,
            offset: const Offset(-2, 0),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      constraints: BoxConstraints(maxWidth: sideBarWidth),
      height: MediaQuery.sizeOf(context).height,
      child: GestureDetector(
        child: Material(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: ClipRect(
            clipBehavior: Clip.antiAlias,
            child: Container(
              padding: EdgeInsets.fromLTRB(
                0,
                0,
                MediaQuery.paddingOf(context).right,
                addBottomPadding
                    ? MediaQuery.paddingOf(context).bottom +
                          MediaQuery.viewInsetsOf(context).bottom
                    : 0,
              ),
              color: useSurfaceTintColor
                  ? Theme.of(context).colorScheme.surfaceTint.withAlpha(20)
                  : null,
              child: body,
            ),
          ),
        ),
      ),
    );

    if (App.isIOS) {
      body = IOSBackGestureDetector(
        enabledCallback: () => true,
        gestureWidth: 20.0,
        onStartPopGesture: () =>
            IOSBackGestureController(controller!, navigator!),
        child: body,
      );
    }

    return Align(alignment: Alignment.centerRight, child: body);
  }

  @override
  Duration get transitionDuration => const Duration(milliseconds: 220);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (VeneraMotion.reduce(context)) return RepaintBoundary(child: child);
    var offset = Tween<Offset>(
      begin: const Offset(1, 0),
      end: const Offset(0, 0),
    );
    return SlideTransition(
      position: offset.animate(
        animation.drive(CurveTween(
          curve: animation.status == AnimationStatus.reverse
              ? VeneraMotion.exit : VeneraMotion.enter,
        )),
      ),
      child: RepaintBoundary(child: child),
    );
  }
}

Future<void> showSideBar(
  BuildContext context,
  Widget widget, {
  bool showBarrier = true,
  bool useSurfaceTintColor = false,
  bool dismissible = true,
  double width = 500,
  bool addTopPadding = false,
}) {
  return Navigator.of(context).push(
    SideBarRoute(
      widget,
      showBarrier: showBarrier,
      useSurfaceTintColor: useSurfaceTintColor,
      dismissible: dismissible,
      width: width,
      addTopPadding: addTopPadding,
      addBottomPadding: true,
    ),
  );
}
