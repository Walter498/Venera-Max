import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Slides inside the card's own clip, not toward the screen's safe-area edge.
/// Once closed, the complete subtree is offstage (including backdrop filters).
class ReaderChromeVisibility extends StatefulWidget {
  const ReaderChromeVisibility({
    required this.visible,
    required this.fromTop,
    required this.duration,
    required this.child,
    super.key,
  });

  final bool visible;
  final bool fromTop;
  final Duration duration;
  final Widget child;

  @override
  State<ReaderChromeVisibility> createState() => _ReaderChromeVisibilityState();
}

class _ReaderChromeVisibilityState extends State<ReaderChromeVisibility>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: widget.visible ? 1 : 0,
  );
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );

  @override
  void didUpdateWidget(ReaderChromeVisibility oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.duration = widget.duration;
    if (oldWidget.visible != widget.visible) {
      if (widget.visible) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) => Offstage(
        offstage: _controller.isDismissed,
        child: TickerMode(
          enabled: !_controller.isDismissed,
          child: IgnorePointer(
            // Stop stealing page taps as soon as closing starts.
            ignoring: !widget.visible,
            child: ExcludeFocus(
              excluding: !widget.visible,
              child: ExcludeSemantics(
                excluding: !widget.visible,
                child: ClipRect(
                  child: FadeTransition(
                    opacity: _curve,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: Offset(0, widget.fromTop ? -1 : 1),
                        end: Offset.zero,
                      ).animate(_curve),
                      child: child,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Clear at the top, progressively frosted through the middle, then stronger
/// blur and a restrained dark tint at the bottom. Everything stays inside the
/// floating card: no full-width scrim, opaque material or doubled page image.
class ReaderBottomGlass extends StatelessWidget {
  const ReaderBottomGlass({
    required this.borderRadius,
    required this.surfaceColor,
    required this.borderColor,
    required this.blurSigma,
    required this.child,
    super.key,
  });

  final BorderRadius borderRadius;
  final Color surfaceColor;
  final Color borderColor;
  final double blurSigma;
  final Widget child;

  static const blurBands = 16;

  @visibleForTesting
  static double sigmaAt(double progress, double maxSigma) {
    final t = ((progress - 0.2) / 0.8).clamp(0.0, 1.0);
    return maxSigma * t * t * (3 - 2 * t);
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          Positioned.fill(
            child: BackdropGroup(
              child: IgnorePointer(
                child: LayoutBuilder(
                  builder: (context, constraints) => Stack(
                    children: [
                      // Shared input and disjoint clips avoid compounding
                      // full-card filters or washing out the clear top edge.
                      for (var i = 0; i < blurBands; i++)
                        if (sigmaAt(i / (blurBands - 1), blurSigma) > 0)
                          Positioned(
                            top: constraints.maxHeight * i / blurBands,
                            height: constraints.maxHeight / blurBands,
                            left: 0,
                            right: 0,
                            child: ClipRect(
                              key: ValueKey('reader-bottom-blur-band-$i'),
                              child: BackdropFilter.grouped(
                                filter: ui.ImageFilter.blur(
                                  sigmaX: sigmaAt(i / (blurBands - 1), blurSigma),
                                  sigmaY: sigmaAt(i / (blurBands - 1), blurSigma),
                                ),
                                child: const SizedBox.expand(),
                              ),
                            ),
                          ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0, 0.25, 0.65, 1],
                colors: [
                  surfaceColor.withValues(alpha: 0),
                  surfaceColor.withValues(alpha: 0.04),
                  surfaceColor.withValues(alpha: 0.14),
                  surfaceColor.withValues(alpha: 0.30),
                ],
              ),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: borderRadius,
                border: Border.all(color: borderColor, width: 0.5),
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0, 0.4, 0.75, 1],
                  colors: [
                    Color(0x00000000),
                    Color(0x00000000),
                    Color(0x06000000),
                    Color(0x1A000000),
                  ],
                ),
              ),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}
