part of 'components.dart';

/// The iOS home shell uses a real UIKit UITabBar for items and interaction.
/// The shared backdrop is painted below it in Flutter so the blur can sample
/// the page texture; the platform view itself has no opaque background.
class _NativeIosTabBar extends StatefulWidget {
  const _NativeIosTabBar({
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<PaneItemEntry> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  State<_NativeIosTabBar> createState() => _NativeIosTabBarState();
}

class _NativeIosTabBarState extends State<_NativeIosTabBar> {
  MethodChannel? _channel;

  String get _viewType => 'venera/native_tab_bar';

  @override
  void didUpdateWidget(covariant _NativeIosTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      _setSelectedIndex(widget.selectedIndex);
    }
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    _channel = null;
    super.dispose();
  }

  void _setSelectedIndex(int index) {
    _channel?.invokeMethod<void>('setSelectedIndex', index);
  }

  void _onPlatformViewCreated(int viewId) {
    final channel = MethodChannel('venera/native_tab_bar/$viewId');
    _channel = channel;
    channel.setMethodCallHandler((call) async {
      if (call.method != 'onTabSelected') return;
      final index = call.arguments is int ? call.arguments as int : -1;
      if (index < 0 || index >= widget.items.length) return;
      widget.onSelected(index);
    });
    _setSelectedIndex(widget.selectedIndex);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final labels = widget.items.map((item) => item.label).toList(growable: false);
    return SizedBox(
      height: NaviPaneState._kBottomBarHeight + bottomInset,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // UIKit effects cannot reliably sample Flutter's composited
            // texture. Paint the backdrop in Flutter, below the real UITabBar.
            // Masking the material (not the content) keeps the upper edge clear.
            IgnorePointer(
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (bounds) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Color(0x55000000),
                    Color(0xD9000000),
                    Colors.black,
                  ],
                  stops: [0, .34, .74, 1],
                ).createShader(bounds),
                child: BackdropFilter(
                  // ShaderMask creates a saveLayer; src prevents the filtered
                  // backdrop from being blended twice into that layer.
                  blendMode: BlendMode.src,
                  filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Theme.of(context).colorScheme.surface.withValues(alpha: 0),
                          Theme.of(context).colorScheme.surface.withValues(alpha: .20),
                          Colors.black.withValues(alpha: .26),
                          Colors.black.withValues(alpha: .40),
                        ],
                        stops: const [0, .34, .72, 1],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            UiKitView(
              key: ValueKey(labels.join('\u0000')),
              viewType: _viewType,
              creationParams: <String, Object>{
                'labels': labels,
                'selectedIndex': widget.selectedIndex,
              },
              creationParamsCodec: const StandardMessageCodec(),
              onPlatformViewCreated: _onPlatformViewCreated,
            ),
          ],
        ),
      ),
    );
  }
}
