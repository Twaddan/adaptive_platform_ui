import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// One tab of a [SystemTabBar].
@immutable
class SystemTabBarItem {
  const SystemTabBarItem({
    required this.label,
    required this.symbol,
    this.selectedSymbol,
  });

  /// Shown under the icon while the bar is expanded, and read by VoiceOver.
  final String label;

  /// An SF Symbol name, or the name of an image in the app's asset catalog.
  final String symbol;

  /// The selected tab's own icon, shown with its own colours.
  final String? selectedSymbol;

  Map<String, Object?> toWire() => {
    'label': label,
    'symbol': symbol,
    if (selectedSymbol != null) 'selectedSymbol': selectedSymbol,
  };
}

/// iPhone Duo: Apple's own tab bar in the system's vertical bar (iOS 27.1),
/// as Liquid Glass with the lens that follows a finger along the tabs.
///
/// UIKit only moves a tab bar controller's bar into the vertical bar, never a
/// Flutter view, so while this widget is in the tree the native side keeps a
/// tab bar controller over the Flutter view and shows its bar there; Flutter
/// still draws every page. The widget itself draws nothing.
///
/// The bar shows only while [visible] is true and the system has a vertical
/// bar for the window (see `SystemVerticalBar`); it hides when the widget
/// leaves the tree. Use one at a time.
class SystemTabBar extends StatefulWidget {
  const SystemTabBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onTap,
    this.visible = true,
    this.tint,
    this.fontFamily,
    this.fontSize = 10,
    this.fontAssets = const [],
  });

  final List<SystemTabBarItem> items;
  final int selectedIndex;
  final ValueChanged<int> onTap;

  /// False hides the bar (with the system's animation) without removing it,
  /// e.g. while a sheet covers the page.
  final bool visible;

  /// Colour of the selected tab.
  final Color? tint;

  /// Font of the labels, by family name, and the Flutter font assets to
  /// register so UIKit can find it.
  final String? fontFamily;
  final double fontSize;
  final List<String> fontAssets;

  static const MethodChannel _channel = MethodChannel(
    'adaptive_platform_ui/system_tab_bar',
  );

  @override
  State<SystemTabBar> createState() => _SystemTabBarState();
}

class _SystemTabBarState extends State<SystemTabBar> {
  /// The mounted bar that gets the native taps.
  static _SystemTabBarState? _current;

  bool _isDark = false;

  @override
  void initState() {
    super.initState();
    _current = this;
    SystemTabBar._channel.setMethodCallHandler(_onCall);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _isDark = MediaQuery.maybePlatformBrightnessOf(context) == Brightness.dark;
    _send(visible: widget.visible);
  }

  @override
  void didUpdateWidget(SystemTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _send(visible: widget.visible);
  }

  @override
  void dispose() {
    if (_current == this) {
      _current = null;
      _send(visible: false);
    }
    super.dispose();
  }

  static Future<void> _onCall(MethodCall call) async {
    if (call.method != 'onTabSelected') return;
    final index = (call.arguments as Map?)?['index'] as int?;
    final bar = _current;
    if (bar != null &&
        index != null &&
        index >= 0 &&
        index < bar.widget.items.length) {
      bar.widget.onTap(index);
    }
  }

  String? _sent;

  Future<void> _send({required bool visible}) async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    final params = <String, Object?>{
      'visible': visible,
      'items': [for (final item in widget.items) item.toWire()],
      'selectedIndex': widget.selectedIndex,
      if (widget.tint != null) 'tint': widget.tint!.toARGB32(),
      if (widget.fontFamily != null) 'fontFamily': widget.fontFamily,
      'fontSize': widget.fontSize,
      'fontAssets': widget.fontAssets,
      'isDark': _isDark,
    };
    final key = params.toString();
    if (key == _sent) return;
    _sent = key;
    try {
      await SystemTabBar._channel.invokeMethod<void>('update', params);
    } on MissingPluginException {
      // Not on iOS, or a test.
    } on PlatformException {
      // Native side unavailable.
    }
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
