part of 'components.dart';

/// Shared visual tokens for the modern iOS-oriented surface system.
///
/// These tokens deliberately separate the content layer from the functional
/// layer: comic covers and reading content stay clear, while search, filters,
/// segmented controls, and navigation can use a restrained material surface.
@immutable
class VeneraDesignTokens extends ThemeExtension<VeneraDesignTokens> {
  const VeneraDesignTokens({
    required this.contentSurface,
    required this.controlSurface,
    required this.controlSurfacePressed,
    required this.glassSurface,
    required this.glassStrongSurface,
    required this.selectedSurface,
    required this.borderSubtle,
    required this.borderStrong,
    required this.separator,
    required this.mutedText,
    required this.accent,
    required this.destructive,
    required this.success,
    required this.warning,
    required this.controlRadius,
    required this.cardRadius,
    required this.sectionRadius,
    required this.pillRadius,
    required this.blurSigma,
  });

  final Color contentSurface;
  final Color controlSurface;
  final Color controlSurfacePressed;
  final Color glassSurface;
  final Color glassStrongSurface;
  final Color selectedSurface;
  final Color borderSubtle;
  final Color borderStrong;
  final Color separator;
  final Color mutedText;
  final Color accent;
  final Color destructive;
  final Color success;
  final Color warning;
  final double controlRadius;
  final double cardRadius;
  final double sectionRadius;
  final double pillRadius;
  final double blurSigma;

  // --- Static scale tokens (independent of color scheme) ---

  /// 8pt spacing grid. Use these instead of ad-hoc magic numbers so padding,
  /// gaps and insets stay consistent across every surface.
  static const double space2 = 2;
  static const double space4 = 4;
  static const double space6 = 6;
  static const double space8 = 8;
  static const double space12 = 12;
  static const double space16 = 16;
  static const double space20 = 20;
  static const double space24 = 24;
  static const double space32 = 32;

  /// Minimum HIG touch target (44x44 pt on iOS/iPadOS).
  static const double minTouchTarget = 44;

  /// Standard hairline separator thickness.
  static const double hairline = 0.5;

  /// Motion durations tuned for iOS-style transitions.
  static const Duration motionFast = Duration(milliseconds: 140);
  static const Duration motionBase = Duration(milliseconds: 220);
  static const Duration motionSlow = Duration(milliseconds: 320);
  static const Curve motionCurve = Curves.easeOutCubic;

  factory VeneraDesignTokens.fromScheme(ColorScheme scheme) {
    final isDark = scheme.brightness == Brightness.dark;
    final surface = scheme.surface;
    return VeneraDesignTokens(
      contentSurface: Color.alphaBlend(
        scheme.surfaceContainerLow.withValues(alpha: isDark ? .72 : .86),
        surface,
      ),
      controlSurface: Color.alphaBlend(
        scheme.surfaceContainerHigh.withValues(alpha: isDark ? .78 : .9),
        surface,
      ),
      controlSurfacePressed: Color.alphaBlend(
        scheme.surfaceContainerHighest.withValues(alpha: isDark ? .9 : 1),
        surface,
      ),
      glassSurface: surface.withValues(alpha: isDark ? .72 : .68),
      glassStrongSurface: surface.withValues(alpha: isDark ? .86 : .8),
      selectedSurface: scheme.primary.withValues(alpha: isDark ? .22 : .14),
      borderSubtle: scheme.outlineVariant.withValues(alpha: isDark ? .3 : .22),
      borderStrong: scheme.outline.withValues(alpha: isDark ? .46 : .34),
      separator: scheme.outlineVariant.withValues(alpha: isDark ? .28 : .2),
      mutedText: scheme.onSurfaceVariant,
      accent: scheme.primary,
      destructive: isDark
          ? const Color(0xFFFF6961)
          : const Color(0xFFD70015),
      success: isDark ? const Color(0xFF30D158) : const Color(0xFF248A3D),
      warning: isDark ? const Color(0xFFFFD60A) : const Color(0xFFB25000),
      controlRadius: 14,
      cardRadius: 12,
      sectionRadius: 18,
      pillRadius: 999,
      blurSigma: 24,
    );
  }

  static VeneraDesignTokens of(BuildContext context) {
    return Theme.of(context).extension<VeneraDesignTokens>() ??
        VeneraDesignTokens.fromScheme(Theme.of(context).colorScheme);
  }

  @override
  VeneraDesignTokens copyWith({
    Color? contentSurface,
    Color? controlSurface,
    Color? controlSurfacePressed,
    Color? glassSurface,
    Color? glassStrongSurface,
    Color? selectedSurface,
    Color? borderSubtle,
    Color? borderStrong,
    Color? separator,
    Color? mutedText,
    Color? accent,
    Color? destructive,
    Color? success,
    Color? warning,
    double? controlRadius,
    double? cardRadius,
    double? sectionRadius,
    double? pillRadius,
    double? blurSigma,
  }) {
    return VeneraDesignTokens(
      contentSurface: contentSurface ?? this.contentSurface,
      controlSurface: controlSurface ?? this.controlSurface,
      controlSurfacePressed:
          controlSurfacePressed ?? this.controlSurfacePressed,
      glassSurface: glassSurface ?? this.glassSurface,
      glassStrongSurface: glassStrongSurface ?? this.glassStrongSurface,
      selectedSurface: selectedSurface ?? this.selectedSurface,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      borderStrong: borderStrong ?? this.borderStrong,
      separator: separator ?? this.separator,
      mutedText: mutedText ?? this.mutedText,
      accent: accent ?? this.accent,
      destructive: destructive ?? this.destructive,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      controlRadius: controlRadius ?? this.controlRadius,
      cardRadius: cardRadius ?? this.cardRadius,
      sectionRadius: sectionRadius ?? this.sectionRadius,
      pillRadius: pillRadius ?? this.pillRadius,
      blurSigma: blurSigma ?? this.blurSigma,
    );
  }

  @override
  VeneraDesignTokens lerp(
    covariant ThemeExtension<VeneraDesignTokens>? other,
    double t,
  ) {
    if (other is! VeneraDesignTokens) return this;
    return VeneraDesignTokens(
      contentSurface: Color.lerp(contentSurface, other.contentSurface, t)!,
      controlSurface: Color.lerp(controlSurface, other.controlSurface, t)!,
      controlSurfacePressed: Color.lerp(
        controlSurfacePressed,
        other.controlSurfacePressed,
        t,
      )!,
      glassSurface: Color.lerp(glassSurface, other.glassSurface, t)!,
      glassStrongSurface: Color.lerp(
        glassStrongSurface,
        other.glassStrongSurface,
        t,
      )!,
      selectedSurface: Color.lerp(selectedSurface, other.selectedSurface, t)!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      separator: Color.lerp(separator, other.separator, t)!,
      mutedText: Color.lerp(mutedText, other.mutedText, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      destructive: Color.lerp(destructive, other.destructive, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      controlRadius: ui.lerpDouble(controlRadius, other.controlRadius, t)!,
      cardRadius: ui.lerpDouble(cardRadius, other.cardRadius, t)!,
      sectionRadius: ui.lerpDouble(sectionRadius, other.sectionRadius, t)!,
      pillRadius: ui.lerpDouble(pillRadius, other.pillRadius, t)!,
      blurSigma: ui.lerpDouble(blurSigma, other.blurSigma, t)!,
    );
  }
}

class VeneraSegmentedControl extends StatelessWidget {
  const VeneraSegmentedControl({
    required this.labels,
    required this.selectedIndex,
    required this.onChanged,
    super.key,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = VeneraDesignTokens.of(context);
    final scheme = Theme.of(context).colorScheme;
    final selected = selectedIndex.clamp(0, labels.length - 1);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.controlSurface,
        borderRadius: BorderRadius.circular(tokens.controlRadius),
        border: Border.all(color: tokens.borderSubtle, width: .7),
      ),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Row(
          children: [
            for (var i = 0; i < labels.length; i++)
              Expanded(
                child: Semantics(
                  button: true,
                  selected: i == selected,
                  label: labels[i],
                  child: InkWell(
                    borderRadius: BorderRadius.circular(13),
                    onTap: () => onChanged(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: i == selected
                            ? scheme.surface
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(13),
                        boxShadow: i == selected
                            ? [
                                BoxShadow(
                                  color: scheme.shadow.withValues(alpha: .12),
                                  blurRadius: 3,
                                  offset: const Offset(0, 1),
                                ),
                              ]
                            : null,
                      ),
                      child: Text(
                        labels[i],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: i == selected
                              ? scheme.primary
                              : tokens.mutedText,
                          fontWeight: i == selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class VeneraIconButton extends StatelessWidget {
  const VeneraIconButton({
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.size = 44,
    super.key,
  });

  final Widget icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tokens = VeneraDesignTokens.of(context);
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: tokens.controlSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.controlRadius),
          side: BorderSide(color: tokens.borderSubtle, width: .7),
        ),
        clipBehavior: Clip.antiAlias,
        child: SizedBox.square(
          dimension: size,
          child: IconButton(
            onPressed: onPressed,
            icon: icon,
            padding: EdgeInsets.zero,
            tooltip: tooltip,
            style: IconButton.styleFrom(
              minimumSize: Size.square(size),
              foregroundColor: tokens.mutedText,
            ),
          ),
        ),
      ),
    );
  }
}

/// A press-feedback wrapper that applies a subtle iOS-style scale + opacity dip
/// while held. Use it to wrap custom tappable surfaces that aren't buttons so
/// they feel responsive without a Material ripple.
class VeneraPressable extends StatefulWidget {
  const VeneraPressable({
    required this.child,
    required this.onTap,
    this.onLongPress,
    this.scale = .97,
    this.behavior = HitTestBehavior.opaque,
    this.borderRadius,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final HitTestBehavior behavior;
  final BorderRadius? borderRadius;

  @override
  State<VeneraPressable> createState() => _VeneraPressableState();
}

class _VeneraPressableState extends State<VeneraPressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    Widget child = AnimatedScale(
      scale: _down && enabled ? widget.scale : 1,
      duration: VeneraDesignTokens.motionFast,
      curve: VeneraDesignTokens.motionCurve,
      child: AnimatedOpacity(
        opacity: _down && enabled ? .72 : 1,
        duration: VeneraDesignTokens.motionFast,
        child: widget.child,
      ),
    );
    if (widget.borderRadius != null) {
      child = ClipRRect(borderRadius: widget.borderRadius!, child: child);
    }
    return GestureDetector(
      behavior: widget.behavior,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onTapDown: enabled ? (_) => _set(true) : null,
      onTapUp: enabled ? (_) => _set(false) : null,
      onTapCancel: enabled ? () => _set(false) : null,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        child: child,
      ),
    );
  }
}

/// A grouped-list section container in the style of iOS Settings: a single
/// rounded surface with hairline-separated rows, an optional header and footer.
class VeneraSection extends StatelessWidget {
  const VeneraSection({
    required this.children,
    this.header,
    this.footer,
    this.margin = const EdgeInsets.symmetric(
      horizontal: VeneraDesignTokens.space16,
      vertical: VeneraDesignTokens.space8,
    ),
    super.key,
  });

  final List<Widget> children;
  final Widget? header;
  final Widget? footer;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    final tokens = VeneraDesignTokens.of(context);
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(
          Padding(
            padding: const EdgeInsets.only(left: VeneraDesignTokens.space16),
            child: Divider(
              height: VeneraDesignTokens.hairline,
              thickness: VeneraDesignTokens.hairline,
              color: tokens.separator,
            ),
          ),
        );
      }
      rows.add(children[i]);
    }
    return Padding(
      padding: margin,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (header != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                VeneraDesignTokens.space16,
                0,
                VeneraDesignTokens.space16,
                VeneraDesignTokens.space6,
              ),
              child: DefaultTextStyle.merge(
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: tokens.mutedText,
                      letterSpacing: .2,
                    ) ??
                    TextStyle(color: tokens.mutedText),
                child: header!,
              ),
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: tokens.controlSurface,
              borderRadius: BorderRadius.circular(tokens.sectionRadius),
              border: Border.all(
                color: tokens.borderSubtle,
                width: VeneraDesignTokens.hairline,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(tokens.sectionRadius),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: rows,
              ),
            ),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                VeneraDesignTokens.space16,
                VeneraDesignTokens.space6,
                VeneraDesignTokens.space16,
                0,
              ),
              child: DefaultTextStyle.merge(
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: tokens.mutedText,
                    ) ??
                    TextStyle(color: tokens.mutedText),
                child: footer!,
              ),
            ),
        ],
      ),
    );
  }
}

/// A pill-shaped filter/selection chip with the three-channel selected state
/// the HIG recommends: fill + label color + weight (not color alone).
class VeneraChip extends StatelessWidget {
  const VeneraChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.leading,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final tokens = VeneraDesignTokens.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: VeneraPressable(
        onTap: onTap,
        borderRadius: BorderRadius.circular(tokens.pillRadius),
        child: AnimatedContainer(
          duration: VeneraDesignTokens.motionFast,
          curve: VeneraDesignTokens.motionCurve,
          constraints: const BoxConstraints(minHeight: 34),
          padding: const EdgeInsets.symmetric(
            horizontal: VeneraDesignTokens.space16,
            vertical: VeneraDesignTokens.space6,
          ),
          decoration: BoxDecoration(
            color: selected ? scheme.primary : tokens.controlSurface,
            borderRadius: BorderRadius.circular(tokens.pillRadius),
            border: Border.all(
              color: selected ? scheme.primary : tokens.borderSubtle,
              width: VeneraDesignTokens.hairline,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leading != null) ...[
                IconTheme.merge(
                  data: IconThemeData(
                    size: 16,
                    color: selected ? scheme.onPrimary : tokens.mutedText,
                  ),
                  child: leading!,
                ),
                const SizedBox(width: VeneraDesignTokens.space6),
              ],
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: selected ? scheme.onPrimary : tokens.mutedText,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Wraps content in an iOS material surface. On iOS this is a real blurred
/// Liquid-Glass-style layer; elsewhere it falls back to an opaque control
/// surface so the look stays consistent without the blur cost.
class VeneraGlass extends StatelessWidget {
  const VeneraGlass({
    required this.child,
    this.borderRadius,
    this.strong = false,
    this.border = true,
    super.key,
  });

  final Widget child;
  final BorderRadius? borderRadius;
  final bool strong;
  final bool border;

  @override
  Widget build(BuildContext context) {
    final tokens = VeneraDesignTokens.of(context);
    final radius =
        borderRadius ?? BorderRadius.circular(tokens.controlRadius);
    final surface = DecoratedBox(
      decoration: BoxDecoration(
        color: App.isIOS
            ? (strong ? tokens.glassStrongSurface : tokens.glassSurface)
            : (strong ? tokens.controlSurfacePressed : tokens.controlSurface),
        borderRadius: radius,
        border: border
            ? Border.all(
                color: tokens.borderSubtle,
                width: VeneraDesignTokens.hairline,
              )
            : null,
      ),
      child: child,
    );
    if (!App.isIOS) {
      return ClipRRect(borderRadius: radius, child: surface);
    }
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(
          sigmaX: tokens.blurSigma,
          sigmaY: tokens.blurSigma,
        ),
        child: surface,
      ),
    );
  }
}
