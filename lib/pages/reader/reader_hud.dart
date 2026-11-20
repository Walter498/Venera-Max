import 'package:flutter/material.dart';

/// The 2.x resting reader HUD, independent of the application's body font size.
/// Stroke and fill must have identical metrics; inheriting bodyMedium for only
/// one layer caused the 14/16pt double image after the 3.x theme upgrade.
class ReaderHudText extends StatelessWidget {
  const ReaderHudText(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final family = theme.textTheme.bodyMedium;
    final metrics = TextStyle(
      inherit: false,
      fontFamily: family?.fontFamily,
      fontFamilyFallback: family?.fontFamilyFallback,
      fontSize: 14,
      fontWeight: FontWeight.w400,
      fontStyle: FontStyle.normal,
      letterSpacing: 0.25,
      wordSpacing: 0,
      height: 1.43,
      leadingDistribution: TextLeadingDistribution.even,
      textBaseline: family?.textBaseline ?? TextBaseline.alphabetic,
      decoration: TextDecoration.none,
    );
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final locale = Localizations.maybeLocaleOf(context);

    Widget layer(Key key, Paint paint) => Text(
      text,
      key: key,
      style: metrics.copyWith(foreground: paint),
      textScaler: scaler,
      textDirection: direction,
      locale: locale,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.start,
    );

    return Semantics(
      label: text,
      child: ExcludeSemantics(
        child: Stack(
          alignment: AlignmentDirectional.topStart,
          children: [
            layer(
              const ValueKey('reader-hud-stroke'),
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.4
                ..color = theme.colorScheme.onInverseSurface,
            ),
            layer(
              const ValueKey('reader-hud-fill'),
              Paint()
                ..style = PaintingStyle.fill
                ..color = theme.colorScheme.onSurface,
            ),
          ],
        ),
      ),
    );
  }
}

/// Restores the 2.x outlined battery icon as well as its outlined percentage.
/// The polling/state lifecycle remains in the reader; this is presentation only.
class ReaderHudBattery extends StatelessWidget {
  const ReaderHudBattery({
    required this.icon,
    required this.level,
    this.color,
    super.key,
  });

  final IconData icon;
  final int level;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 16,
          color: color ?? scheme.onSurface,
          shadows: [
            for (var y = -1; y <= 1; y++)
              for (var x = -1; x <= 1; x++)
                if (x != 0 || y != 0)
                  Shadow(
                    color: scheme.onInverseSurface,
                    offset: Offset(x * 0.8, y * 0.8),
                  ),
          ],
        ),
        ReaderHudText('$level%'),
      ],
    );
  }
}
