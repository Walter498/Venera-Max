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

/// Clear at the top, progressively frosted through the middle, then a broad
/// dark ramp behind the controls. Everything stays inside the floating card:
/// no full-width scrim, opaque material or doubled page image.
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
              // A subtle constant base keeps the auto-turn row readable even
              // at the clear edge of the transition. The gradient below still
              // carries the clear-to-dark hierarchy over that base.
              Positioned.fill(
                child: ColoredBox(color: Color(0x24000000)),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    // More, smaller steps keep the transition broad and slow
                    // instead of dropping the controls onto a hard black edge.
                    stops: const [0, 0.14, 0.30, 0.48, 0.66, 0.84, 1],
                    colors: [
                      surfaceColor.withValues(alpha: 0),
                      surfaceColor.withValues(alpha: 0.05),
                      surfaceColor.withValues(alpha: 0.10),
                      surfaceColor.withValues(alpha: 0.17),
                      surfaceColor.withValues(alpha: 0.25),
                      surfaceColor.withValues(alpha: 0.33),
                      surfaceColor.withValues(alpha: 0.40),
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
                      // The dark ramp starts earlier and has more intermediate
                      // stops so the speed row and progress remain legible.
                      stops: [0, 0.16, 0.38, 0.58, 0.76, 0.9, 1],
                      colors: [
                        Color(0x00000000),
                        Color(0x08000000),
                        Color(0x2E000000),
                        Color(0x66000000),
                        Color(0x85000000),
                        Color(0x9E000000),
                        Color(0xB8000000),
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

/// Dark, slow-gradient glass for the top reader controls. The top edge keeps
/// a translucent dark base rather than becoming fully clear, while the lower
/// edge settles into a denser tint behind the action buttons and title.
class ReaderTopGlass extends StatelessWidget {
  const ReaderTopGlass({
    required this.borderRadius,
    required this.borderColor,
    required this.blurSigma,
    required this.child,
    super.key,
  });

  final BorderRadius borderRadius;
  final Color borderColor;
  final double blurSigma;
  final Widget child;

  static const blurBands = 16;

  @visibleForTesting
  static double sigmaAt(double progress, double maxSigma) {
    final t = ((progress - 0.08) / 0.92).clamp(0.0, 1.0);
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
                      for (var i = 0; i < blurBands; i++)
                        if (sigmaAt(i / (blurBands - 1), blurSigma) > 0)
                          Positioned(
                            top: constraints.maxHeight * i / blurBands,
                            height: constraints.maxHeight / blurBands,
                            left: 0,
                            right: 0,
                            child: ClipRect(
                              key: ValueKey('reader-top-blur-band-$i'),
                              child: BackdropFilter.grouped(
                                filter: ui.ImageFilter.blur(
                                  sigmaX: sigmaAt(
                                    i / (blurBands - 1),
                                    blurSigma,
                                  ),
                                  sigmaY: sigmaAt(
                                    i / (blurBands - 1),
                                    blurSigma,
                                  ),
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
              borderRadius: borderRadius,
              border: Border.all(color: borderColor, width: 0.5),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                // Small steps deliberately slow the clear-to-dark change so
                // the title and every action remain readable across the card.
                stops: [0, 0.12, 0.28, 0.46, 0.64, 0.82, 1],
                colors: [
                  Color(0x26000000),
                  Color(0x32000000),
                  Color(0x45000000),
                  Color(0x5E000000),
                  Color(0x78000000),
                  Color(0x92000000),
                  Color(0xAD000000),
                ],
              ),
            ),
            child: IconTheme.merge(
              data: const IconThemeData(color: Colors.white),
              child: DefaultTextStyle.merge(
                style: const TextStyle(color: Colors.white),
                child: child,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
