part of 'components.dart';

class HoverBox extends StatefulWidget {
  const HoverBox({
    super.key,
    required this.child,
    this.borderRadius = BorderRadius.zero,
  });

  final Widget child;

  final BorderRadius borderRadius;

  @override
  State<HoverBox> createState() => _HoverBoxState();
}

class _HoverBoxState extends State<HoverBox> {
  bool isHover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => isHover = true),
      onExit: (_) => setState(() => isHover = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: VeneraMotion.duration(context, const Duration(milliseconds: 200)),
        decoration: BoxDecoration(
          color: isHover
              ? Theme.of(context).colorScheme.surfaceContainerLow
              : null,
          borderRadius: widget.borderRadius,
        ),
        child: widget.child,
      ),
    );
  }
}

enum ButtonType { filled, outlined, text, normal }

class Button extends StatefulWidget {
  const Button({
    super.key,
    required this.type,
    required this.child,
    this.isLoading = false,
    this.width,
    this.height,
    this.padding,
    this.color,
    this.onPressedAt,
    required this.onPressed,
  });

  const Button.filled({
    super.key,
    required this.child,
    required this.onPressed,
    this.width,
    this.height,
    this.padding,
    this.color,
    this.onPressedAt,
    this.isLoading = false,
  }) : type = ButtonType.filled;

  const Button.outlined({
    super.key,
    required this.child,
    required this.onPressed,
    this.width,
    this.height,
    this.padding,
    this.color,
    this.onPressedAt,
    this.isLoading = false,
  }) : type = ButtonType.outlined;

  const Button.text({
    super.key,
    required this.child,
    required this.onPressed,
    this.width,
    this.height,
    this.padding,
    this.color,
    this.onPressedAt,
    this.isLoading = false,
  }) : type = ButtonType.text;

  const Button.normal({
    super.key,
    required this.child,
    required this.onPressed,
    this.width,
    this.height,
    this.padding,
    this.color,
    this.onPressedAt,
    this.isLoading = false,
  }) : type = ButtonType.normal;

  static Widget icon({
    Key? key,
    required Widget icon,
    required VoidCallback onPressed,
    double? size,
    Color? color,
    String? tooltip,
    bool isLoading = false,
    HitTestBehavior behavior = HitTestBehavior.deferToChild,
  }) {
    return _IconButton(
      key: key,
      icon: icon,
      onPressed: onPressed,
      size: size,
      color: color,
      tooltip: tooltip,
      behavior: behavior,
      isLoading: isLoading,
    );
  }

  final ButtonType type;

  final Widget child;

  final bool isLoading;

  final void Function() onPressed;

  final void Function(Offset location)? onPressedAt;

  final double? width;

  final double? height;

  final EdgeInsets? padding;

  final Color? color;

  @override
  State<Button> createState() => _ButtonState();
}

class _ButtonState extends State<Button> {
  bool isHover = false;

  bool isPressed = false;

  bool isLoading = false;
  bool isFocused = false;

  @override
  void initState() {
    isLoading = widget.isLoading;
    super.initState();
  }

  @override
  void didUpdateWidget(covariant Button oldWidget) {
    if (oldWidget.isLoading != widget.isLoading) {
      isLoading = widget.isLoading;
      if (isLoading) isPressed = false;
    }
    super.didUpdateWidget(oldWidget);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = VeneraDesignTokens.of(context);
    final radius = BorderRadius.circular(tokens.controlRadius);
    final raised = widget.type == ButtonType.filled || widget.type == ButtonType.normal;
    final pressed = isPressed && !isLoading;
    final duration = VeneraMotion.duration(context, VeneraDesignTokens.motionFast);
    final content = IconTheme(
      data: IconThemeData(color: textColor),
      child: DefaultTextStyle(
        style: (Theme.of(context).textTheme.labelLarge ?? const TextStyle(fontSize: 14))
            .copyWith(color: textColor, fontSize: 14),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (isLoading)
              _ButtonPlaceholder(child: ExcludeFocus(
                child: TickerMode(enabled: false, child: widget.child),
              ))
            else
              widget.child,
            if (isLoading)
              Positioned.fill(
                child: Center(
                  child: SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(
                      color: textColor, strokeWidth: 1.8,
                      value: VeneraMotion.reduce(context) ? .72 : null,
                      semanticsLabel: 'Loading'.tl,
                      semanticsValue: 'Loading'.tl,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    return Semantics(
      button: true,
      enabled: !isLoading,
      // The hidden label still identifies a busy text button to VoiceOver.
      label: isLoading && widget.child is Text ? (widget.child as Text).data : null,
      child: AnimatedContainer(
        duration: duration,
        curve: VeneraMotion.enter,
        width: widget.width,
        constraints: BoxConstraints(
          minWidth: 76,
          minHeight: math.max(44, widget.height ?? 44),
        ),
        transform: Matrix4.translationValues(
          0, pressed && !VeneraMotion.reduce(context) ? 1 : 0, 0,
        ),
        decoration: BoxDecoration(
          color: buttonColor,
          borderRadius: radius,
          boxShadow: raised && !pressed && !isLoading ? [
            BoxShadow(
              color: Colors.black.withValues(alpha: isHover ? .16 : .10),
              blurRadius: isHover ? 3 : 2,
              offset: const Offset(0, 1),
            ),
          ] : const [],
          border: widget.type == ButtonType.outlined || widget.type == ButtonType.normal
              ? Border.all(color: widget.color ?? tokens.borderStrong, width: 1)
              : null,
        ),
        foregroundDecoration: isFocused ? BoxDecoration(
          borderRadius: radius,
          border: Border.all(color: context.colorScheme.primary, width: 2),
        ) : null,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: isLoading ? null : _activate,
            onHover: (value) => setState(() => isHover = value),
            onFocusChange: (value) => setState(() => isFocused = value),
            onHighlightChanged: (value) {
              if (isPressed != value) setState(() => isPressed = value);
            },
            borderRadius: radius,
            // Filled backgrounds remain exact, including hover and focus.
            overlayColor: raised ? const WidgetStatePropertyAll(Colors.transparent) : null,
            mouseCursor: isLoading ? SystemMouseCursors.basic : SystemMouseCursors.click,
            child: CustomPaint(
              foregroundPainter: raised ? _VeneraControlEdgePainter(
                tokens.controlRadius,
                Theme.of(context).brightness == Brightness.dark,
                pressed || isLoading,
              ) : null,
              child: Padding(
                padding: widget.padding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Center(widthFactor: 1, heightFactor: 1, child: content),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _activate() {
    if (isLoading) return;
    // Capture the anchor before a callback can navigate or unmount this button.
    final box = context.findRenderObject() as RenderBox;
    final anchor = box.localToGlobal(Offset.zero);
    final onPressedAt = widget.onPressedAt;
    widget.onPressed();
    onPressedAt?.call(anchor);
  }

  Color get buttonColor {
    if (widget.type == ButtonType.filled) {
      return widget.color ?? context.colorScheme.primary;
    }
    if (widget.type == ButtonType.normal) {
      return widget.color ?? VeneraDesignTokens.of(context).controlSurface;
    }
    return Colors.transparent;
  }

  // A custom fill is not necessarily the theme primary (e.g. a pale
  // destructive/container colour). Choose its actual readable foreground.
  Color get fillForeground {
    final fill = widget.color ?? context.colorScheme.primary;
    final luminance = fill.computeLuminance();
    final blackContrast = (luminance + .05) / .05;
    final whiteContrast = 1.05 / (luminance + .05);
    return blackContrast >= whiteContrast ? Colors.black : Colors.white;
  }

  Color get textColor {
    if (widget.type == ButtonType.outlined) {
      return widget.color ?? context.colorScheme.primary;
    }
    if (widget.type == ButtonType.normal && widget.color != null) {
      return fillForeground;
    }
    return widget.type == ButtonType.filled
        ? fillForeground
        : (widget.type == ButtonType.text
              ? widget.color ?? context.colorScheme.primary
              : context.colorScheme.onSurface);
  }
}

/// Keep the original label's layout while removing it from paint, hit testing,
/// semantics and on-stage finders. This also works on the first loading frame;
/// there is no size cache or post-frame jump.
class _ButtonPlaceholder extends Offstage {
  const _ButtonPlaceholder({required Widget child}) : super(offstage: true, child: child);

  @override
  RenderOffstage createRenderObject(BuildContext context) => _RenderButtonPlaceholder();
}

class _RenderButtonPlaceholder extends RenderOffstage {
  _RenderButtonPlaceholder() : super(offstage: true);

  @override
  bool get sizedByParent => false;

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      constraints.constrain(child?.getDryLayout(constraints) ?? Size.zero);

  @override
  double computeMinIntrinsicWidth(double height) => child?.getMinIntrinsicWidth(height) ?? 0;

  @override
  double computeMaxIntrinsicWidth(double height) => child?.getMaxIntrinsicWidth(height) ?? 0;

  @override
  double computeMinIntrinsicHeight(double width) => child?.getMinIntrinsicHeight(width) ?? 0;

  @override
  double computeMaxIntrinsicHeight(double width) => child?.getMaxIntrinsicHeight(width) ?? 0;

  @override
  void performLayout() {
    child?.layout(constraints, parentUsesSize: true);
    size = constraints.constrain(child?.size ?? Size.zero);
  }
}

class _IconButton extends StatefulWidget {
  const _IconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.size,
    this.color,
    this.tooltip,
    this.isLoading = false,
    this.behavior = HitTestBehavior.deferToChild,
  });

  final Widget icon;

  final VoidCallback onPressed;

  final double? size;

  final String? tooltip;

  final Color? color;

  final HitTestBehavior behavior;

  final bool isLoading;

  @override
  State<_IconButton> createState() => _IconButtonState();
}

class _IconButtonState extends State<_IconButton> {
  bool isHover = false;

  @override
  Widget build(BuildContext context) {
    final iconSize = widget.size ?? 24;
    final foreground = widget.color ?? context.colorScheme.primary;
    return MouseRegion(
      onEnter: (_) => setState(() => isHover = true),
      onExit: (_) => setState(() => isHover = false),
      child: Tooltip(
        message: widget.tooltip ?? '',
        child: VeneraPressable(
          behavior: widget.behavior,
          onTap: widget.isLoading ? null : widget.onPressed,
          borderRadius: BorderRadius.circular((iconSize + 12) / 2),
          child: AnimatedContainer(
            duration: VeneraMotion.duration(context, VeneraDesignTokens.motionFast),
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            decoration: BoxDecoration(
              color: isHover && !widget.isLoading
                  ? Theme.of(context).colorScheme.outlineVariant.withValues(alpha: .24)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular((iconSize + 12) / 2),
            ),
            padding: const EdgeInsets.all(6),
            child: Center(
              widthFactor: 1,
              heightFactor: 1,
              child: SizedBox.square(
                dimension: iconSize,
                child: widget.isLoading
                    ? Padding(
                        padding: const EdgeInsets.all(2),
                        child: CircularProgressIndicator(
                          color: foreground, strokeWidth: 1.5,
                          value: VeneraMotion.reduce(context) ? .72 : null,
                          semanticsLabel: 'Loading'.tl,
                          semanticsValue: 'Loading'.tl,
                        ),
                      )
                    : IconTheme(
                        data: IconThemeData(size: iconSize, color: foreground),
                        child: widget.icon,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

}

class MenuButton extends StatefulWidget {
  const MenuButton({super.key, required this.entries});

  final List<MenuEntry> entries;

  @override
  State<MenuButton> createState() => _MenuButtonState();
}

class _MenuButtonState extends State<MenuButton> {
  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'more'.tl,
      icon: const Icon(Icons.more_horiz),
      style: IconButton.styleFrom(
        fixedSize: const Size.square(48),
        foregroundColor: context.colorScheme.onSurfaceVariant,
      ),
      onPressed: () {
        var renderBox = context.findRenderObject() as RenderBox;
        var offset = renderBox.localToGlobal(Offset.zero);
        showMenuX(context, offset, widget.entries);
      },
    );
  }
}
