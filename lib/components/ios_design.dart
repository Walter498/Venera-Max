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
    required this.glassSurface,
    required this.glassStrongSurface,
    required this.borderSubtle,
    required this.borderStrong,
    required this.mutedText,
    required this.controlRadius,
    required this.cardRadius,
    required this.sectionRadius,
    required this.blurSigma,
  });

  final Color contentSurface;
  final Color controlSurface;
  final Color glassSurface;
  final Color glassStrongSurface;
  final Color borderSubtle;
  final Color borderStrong;
  final Color mutedText;
  final double controlRadius;
  final double cardRadius;
  final double sectionRadius;
  final double blurSigma;

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
      glassSurface: surface.withValues(alpha: isDark ? .72 : .68),
      glassStrongSurface: surface.withValues(alpha: isDark ? .86 : .8),
      borderSubtle: scheme.outlineVariant.withValues(alpha: isDark ? .3 : .22),
      borderStrong: scheme.outline.withValues(alpha: isDark ? .46 : .34),
      mutedText: scheme.onSurfaceVariant,
      controlRadius: 16,
      cardRadius: 10,
      sectionRadius: 16,
      blurSigma: 18,
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
    Color? glassSurface,
    Color? glassStrongSurface,
    Color? borderSubtle,
    Color? borderStrong,
    Color? mutedText,
    double? controlRadius,
    double? cardRadius,
    double? sectionRadius,
    double? blurSigma,
  }) {
    return VeneraDesignTokens(
      contentSurface: contentSurface ?? this.contentSurface,
      controlSurface: controlSurface ?? this.controlSurface,
      glassSurface: glassSurface ?? this.glassSurface,
      glassStrongSurface: glassStrongSurface ?? this.glassStrongSurface,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      borderStrong: borderStrong ?? this.borderStrong,
      mutedText: mutedText ?? this.mutedText,
      controlRadius: controlRadius ?? this.controlRadius,
      cardRadius: cardRadius ?? this.cardRadius,
      sectionRadius: sectionRadius ?? this.sectionRadius,
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
      glassSurface: Color.lerp(glassSurface, other.glassSurface, t)!,
      glassStrongSurface: Color.lerp(
        glassStrongSurface,
        other.glassStrongSurface,
        t,
      )!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      mutedText: Color.lerp(mutedText, other.mutedText, t)!,
      controlRadius: ui.lerpDouble(controlRadius, other.controlRadius, t)!,
      cardRadius: ui.lerpDouble(cardRadius, other.cardRadius, t)!,
      sectionRadius: ui.lerpDouble(sectionRadius, other.sectionRadius, t)!,
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
                            ? scheme.primary.withValues(alpha: .16)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(13),
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
