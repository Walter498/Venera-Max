part of "components.dart";

const minFlyoutWidth = 256.0;
const minFlyoutHeight = 128.0;

class FlyoutController {
  Function? _show;

  void show() {
    if (_show == null) {
      throw "FlyoutController is not attached to a Flyout";
    }
    _show!();
  }
}

class Flyout extends StatefulWidget {
  const Flyout({
    super.key,
    required this.flyoutBuilder,
    required this.child,
    this.enableTap = false,
    this.enableDoubleTap = false,
    this.enableLongPress = false,
    this.enableSecondaryTap = false,
    this.withInkWell = false,
    this.borderRadius = 0,
    this.controller,
    this.navigator,
  });

  final WidgetBuilder flyoutBuilder;

  final Widget child;

  final bool enableTap;

  final bool enableDoubleTap;

  final bool enableLongPress;

  final bool enableSecondaryTap;

  final bool withInkWell;

  final double borderRadius;

  final NavigatorState? navigator;

  final FlyoutController? controller;

  @override
  State<Flyout> createState() => FlyoutState();

  static FlyoutState of(BuildContext context) {
    return context.findAncestorStateOfType<FlyoutState>()!;
  }
}

class FlyoutState extends State<Flyout> {
  @override
  void initState() {
    if (widget.controller != null) {
      widget.controller?._show = show;
    }
    super.initState();
  }

  @override
  void didChangeDependencies() {
    if (widget.controller != null) {
      widget.controller?._show = show;
    }
    super.didChangeDependencies();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.withInkWell) {
      return InkWell(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        onTap: widget.enableTap ? show : null,
        onDoubleTap: widget.enableDoubleTap ? show : null,
        onLongPress: widget.enableLongPress ? show : null,
        onSecondaryTap: widget.enableSecondaryTap ? show : null,
        child: widget.child,
      );
    }
    return GestureDetector(
      onTap: widget.enableTap ? show : null,
      onDoubleTap: widget.enableDoubleTap ? show : null,
      onLongPress: widget.enableLongPress ? show : null,
      onSecondaryTap: widget.enableSecondaryTap ? show : null,
      child: widget.child,
    );
  }

  void show() {
    var renderBox = context.findRenderObject() as RenderBox;
    var rect = renderBox.localToGlobal(Offset.zero) & renderBox.size;
    var navigator = widget.navigator ??
        Navigator.of(
          context,
          rootNavigator: true,
        );
    navigator.push(PageRouteBuilder(
        fullscreenDialog: true,
        barrierDismissible: true,
        opaque: false,
        transitionDuration: VeneraMotion.duration(context, _fastAnimationDuration),
        reverseTransitionDuration: VeneraMotion.duration(context, _fastAnimationDuration),
        pageBuilder: (context, animation, secondaryAnimation) {
          final media = MediaQuery.of(context);
          final bottomInset = math.max(media.viewInsets.bottom, media.padding.bottom);
          final availableBottom = media.size.height - bottomInset - 8;
          final left = rect.left.clamp(
            8.0, math.max(8.0, media.size.width - minFlyoutWidth - 8),
          );
          final top = rect.bottom.clamp(
            media.padding.top + 8,
            math.max(media.padding.top + 8, availableBottom - minFlyoutHeight),
          );

          Widget transition(BuildContext context, Animation<double> animation,
              Animation<double> secondaryAnimation, Widget flyout) {
            if (VeneraMotion.reduce(context)) return flyout;
            final curved = CurvedAnimation(
              parent: animation,
              curve: VeneraMotion.enter,
              reverseCurve: VeneraMotion.exit,
            );
            return FadeTransition(
              opacity: curved,
              child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, -0.025),
                end: Offset.zero,
              ).animate(curved),
              child: flyout,
              ),
            );
          }

          return Stack(
            children: [
              Positioned.fill(
                child: Semantics(
                  label: MaterialLocalizations.of(context).modalBarrierDismissLabel,
                  button: true,
                  child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: navigator.pop,
                  child: AnimatedBuilder(
                    animation: animation,
                    builder: (context, builder) {
                      return ColoredBox(
                        color: Colors.black.toOpacity(0.3 * animation.value),
                      );
                    },
                  ),
                ),
                ),
              ),
              Positioned(
                left: left,
                right: 8,
                top: top,
                bottom: bottomInset + 8,
                child: transition(
                    context,
                    animation,
                    secondaryAnimation,
                    Align(
                      alignment: Alignment.topLeft,
                      child: widget.flyoutBuilder(context),
                    )),
              )
            ],
          );
        }));
  }
}

class FlyoutContent extends StatelessWidget {
  const FlyoutContent(
      {super.key, required this.title, required this.actions, this.content});

  final String title;

  final Widget? content;

  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final tokens = VeneraDesignTokens.of(context);
    final scheme = Theme.of(context).colorScheme;
    return IntrinsicWidth(
      child: Material(
        elevation: 4,
        shadowColor: scheme.shadow.withValues(alpha: 0.18),
        surfaceTintColor: Colors.transparent,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.sectionRadius),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        ),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: math.max(0, math.min(minFlyoutWidth - 32,
                  MediaQuery.sizeOf(context).width - 64)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 16)),
                ),
                if (content != null) ...[
                  const SizedBox(height: 8),
                  content!,
                ],
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OverflowBar(
                    alignment: MainAxisAlignment.end,
                    spacing: 8,
                    overflowSpacing: 8,
                    overflowAlignment: OverflowBarAlignment.end,
                    children: actions,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
