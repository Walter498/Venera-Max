part of 'components.dart';

/// The iOS home shell uses a real UIKit UITabBar. Flutter only supplies the
/// page labels and receives selection callbacks; it does not paint a second
/// bar or a background over the page.
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
      child: UiKitView(
        key: ValueKey(labels.join('\u0000')),
        viewType: _viewType,
        creationParams: <String, Object>{
          'labels': labels,
          'selectedIndex': widget.selectedIndex,
        },
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _onPlatformViewCreated,
      ),
    );
  }
}
