import 'dart:async';
import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flex_seed_scheme/flex_seed_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:venera/foundation/log.dart';
import 'package:venera/pages/auth_page.dart';
import 'package:venera/pages/startup_page.dart';
import 'package:venera/utils/io.dart';
import 'package:venera/utils/translations.dart';
import 'package:window_manager/window_manager.dart';
import 'components/app_slider_theme.dart';
import 'components/components.dart';
import 'components/window_frame.dart';
import 'foundation/app.dart';
import 'foundation/appdata.dart';
import 'foundation/launcher_icon.dart';
import 'foundation/ohos_follow_worker.dart';
import 'foundation/download_keepalive.dart';
import 'foundation/shortcuts.dart';
import 'foundation/tray.dart';
import 'headless.dart';
import 'init.dart';

@pragma('vm:entry-point')
void followUpdatesBackgroundMain(List<String> args) => runOhosFollowWorker(args);

void main(List<String> args) {
  if (args.contains('--headless')) {
    runHeadlessMode(args);
    return;
  }
  if (runWebViewTitleBarWidget(args)) return;
  overrideIO(() {
    runZonedGuarded(() async {
      WidgetsFlutterBinding.ensureInitialized();
      try {
        await init();
      } on PlatformException catch (error) {
        if (error.code != 'FOLLOW_SCHEDULE_UNAVAILABLE') rethrow;
        await AppTranslation.init();
        // This screen must not initialize or read shared application stores.
        runApp(MaterialApp(
          theme: ThemeData.light(),
          darkTheme: ThemeData.dark(),
          home: Scaffold(body: SafeArea(child: Center(child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('Unable to access app data. Close and reopen VeneraX to retry.'.tl),
              TextButton(onPressed: SystemNavigator.pop, child: Text('Close'.tl)),
            ]),
          )))),
        ));
        return;
      }
      runApp(const MyApp());
      if (App.isDesktop) {
        await windowManager.ensureInitialized();
        AppShortcuts.install();
        windowManager.waitUntilReadyToShow().then((_) async {
          await windowManager.setTitleBarStyle(
            TitleBarStyle.hidden,
            windowButtonVisibility: App.isMacOS,
          );
          if (App.isLinux) {
            await windowManager.setBackgroundColor(Colors.transparent);
          }
          await windowManager.setMinimumSize(const Size(500, 600));
          var placement = await WindowPlacement.loadFromFile();
          if (App.isLinux) {
            await windowManager.show();
            await placement.applyToWindow();
          } else {
            await placement.applyToWindow();
            await windowManager.show();
          }

          WindowPlacement.loop();
          await TrayController.instance.init();
          await GlobalHotkeys.sync();
          // WM_SETICON is per-process; re-apply the stored icon each launch so
          // the window/taskbar icon follows the user's choice (issue #134).
          await LauncherIconService.applyForStartup();
        });
      }
    }, (error, stack) {
      Log.error("Unhandled Exception", error, stack);
    });
  });
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    App.registerForceRebuild(forceRebuild);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    WidgetsBinding.instance.addObserver(this);
    syncOhosStartupTheme();
    syncReaderNightModeWithSystem(rebuild: false);
    super.initState();
  }

  OverlayEntry? hideContentOverlay;
  String? _ohosThemeMode;

  void syncOhosStartupTheme() {
    if (!App.isOhos) return;
    final mode = switch (appdata.settings['theme_mode']) {
      'light' => 'light',
      'dark' => 'dark',
      _ => 'system',
    };
    if (_ohosThemeMode == mode) return;
    _ohosThemeMode = mode;
    unawaited(const MethodChannel('venera/method_channel')
        .invokeMethod<void>('setThemeMode', mode)
        .catchError((Object error) {
      if (_ohosThemeMode == mode) _ohosThemeMode = null;
      Log.warning('Theme', 'Unable to synchronize the startup theme.');
    }));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && App.isMobile) {
      DownloadKeepAlive.instance.onResume();
    }
    // Logs are buffered and flushed on a timer to avoid a disk write per
    // network request; push them out now, before the process can be suspended
    // or killed with lines still in memory. Must stay above the early return
    // below, which skips everything when app-lock is off.
    if (state != AppLifecycleState.resumed) {
      Log.flush();
      if (App.isOhos && App.local.isInitialized) {
        unawaited(App.local.saveCurrentDownloadingTasks());
      }
    }
    if (!App.isMobile || !appdata.settings['authorizationRequired']) {
      return;
    }
    if (state == AppLifecycleState.inactive && hideContentOverlay == null) {
      hideContentOverlay = OverlayEntry(
        builder: (context) {
          return Positioned.fill(
            child: Container(
              width: double.infinity,
              height: double.infinity,
              color: App.rootContext.colorScheme.surface,
            ),
          );
        },
      );
      Overlay.of(App.rootContext).insert(hideContentOverlay!);
    } else if (hideContentOverlay != null &&
        state == AppLifecycleState.resumed) {
      hideContentOverlay!.remove();
      hideContentOverlay = null;
    }
    if (state == AppLifecycleState.hidden &&
        !AuthPage.isActive &&
        !IO.isSelectingFiles) {
      AuthPage.isActive = true;
      App.rootContext.to(
        () => AuthPage(
          onSuccessfulAuth: () {
            App.rootContext.pop();
            AuthPage.isActive = false;
          },
        ),
      );
    }
    super.didChangeAppLifecycleState(state);
  }

  @override
  void didChangePlatformBrightness() {
    syncReaderNightModeWithSystem();
    super.didChangePlatformBrightness();
  }

  /// When "follow system" is enabled, keep the reader night mode in sync with
  /// the system dark/light setting: on in dark mode, off in light mode.
  ///
  /// [rebuild] must be false when called during `initState` (the first build
  /// hasn't happened yet, and forcing one then is illegal).
  void syncReaderNightModeWithSystem({bool rebuild = true}) {
    if (appdata.settings['readerNightModeFollowSystem'] != true) {
      return;
    }
    final isDark =
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
            Brightness.dark;
    if ((appdata.settings['readerNightMode'] == true) == isDark) {
      return;
    }
    appdata.settings['readerNightMode'] = isDark;
    appdata.saveData(deferredInitCompleter.isCompleted);
    if (rebuild) {
      App.forceRebuild();
    }
  }

  void forceRebuild() {
    syncOhosStartupTheme();
    void rebuild(Element el) {
      el.markNeedsBuild();
      el.visitChildren(rebuild);
    }

    (context as Element).visitChildren(rebuild);
    setState(() {});
  }

  Color translateColorSetting() {
    return switch (appdata.settings['color']) {
      'red' => Colors.red,
      'pink' => Colors.pink,
      'purple' => Colors.purple,
      'green' => Colors.green,
      'orange' => Colors.orange,
      'blue' => Colors.blue,
      'yellow' => Colors.yellow,
      'cyan' => Colors.cyan,
      _ => Colors.blue,
    };
  }

  ThemeData getTheme(
    Color primary,
    Color? secondary,
    Color? tertiary,
    Brightness brightness,
  ) {
    String? font;
    List<String>? fallback;
    if (App.isLinux || App.isWindows) {
      font = 'Noto Sans CJK';
      fallback = [
        'Segoe UI',
        'Noto Sans SC',
        'Noto Sans TC',
        'Noto Sans',
        'Microsoft YaHei',
        'PingFang SC',
        'Arial',
        'sans-serif'
      ];
    }
    final colors = SeedColorScheme.fromSeeds(
      primaryKey: primary,
      secondaryKey: secondary,
      tertiaryKey: tertiary,
      brightness: brightness,
      tones: FlexTones.vividBackground(brightness),
    );
    final tokens = VeneraDesignTokens.fromScheme(colors);
    final isDark = brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      colorScheme: colors,
      // iOS grouped surfaces are neutral and let the content carry the colour.
      // The accent remains available through ColorScheme for actions and state.
      scaffoldBackgroundColor: brightness == Brightness.light
          ? const Color(0xFFF2F2F7)
          : const Color(0xFF000000),
      textTheme: TextTheme(
        displayLarge: const TextStyle(fontSize: 34, fontWeight: FontWeight.w700),
        displayMedium: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700),
        headlineLarge: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
        headlineMedium: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        headlineSmall: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        titleLarge: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
        titleMedium: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        titleSmall: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        bodyLarge: const TextStyle(fontSize: 17, height: 1.35),
        bodyMedium: const TextStyle(fontSize: 16, height: 1.35),
        bodySmall: const TextStyle(fontSize: 15, height: 1.3),
        labelLarge: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        labelMedium: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        labelSmall: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        iconTheme: IconThemeData(color: colors.onSurfaceVariant),
      ),
      extensions: [tokens],
      dividerTheme: DividerThemeData(
        color: tokens.separator,
        thickness: VeneraDesignTokens.hairline,
        space: VeneraDesignTokens.hairline,
      ),
      splashFactory: App.isIOS ? NoSplash.splashFactory : null,
      // iOS-tuned filled buttons: 44pt-friendly height, control radius,
      // restrained elevation, no stretched Material look.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(
            horizontal: VeneraDesignTokens.space20,
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.controlRadius),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(0, 44),
          elevation: 0,
          padding: const EdgeInsets.symmetric(
            horizontal: VeneraDesignTokens.space20,
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.controlRadius),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(
            horizontal: VeneraDesignTokens.space20,
          ),
          side: BorderSide(
            color: tokens.borderStrong,
            width: VeneraDesignTokens.hairline,
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.controlRadius),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(
            horizontal: VeneraDesignTokens.space12,
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.controlRadius),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size.square(44),
          shape: const CircleBorder(),
        ),
      ),
      // Flat, hairline-bordered cards — no heavy Material drop shadows.
      cardTheme: CardThemeData(
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        color: tokens.controlSurface,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.cardRadius),
          side: BorderSide(
            color: tokens.borderSubtle,
            width: VeneraDesignTokens.hairline,
          ),
        ),
      ),
      listTileTheme: ListTileThemeData(
        minVerticalPadding: VeneraDesignTokens.space12,
        iconColor: tokens.mutedText,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.cardRadius),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.white
              : (isDark ? const Color(0xFFE5E5EA) : Colors.white),
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colors.primary
              : (isDark
                  ? const Color(0xFF39393D)
                  : const Color(0xFFE9E9EA)),
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
        trackOutlineWidth: const WidgetStatePropertyAll(0.0),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
        side: BorderSide(color: tokens.borderStrong, width: 1.5),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colors.primary
              : tokens.borderStrong,
        ),
      ),
      chipTheme: ChipThemeData(
        side: BorderSide(
          color: tokens.borderSubtle,
          width: VeneraDesignTokens.hairline,
        ),
        shape: const StadiumBorder(),
        backgroundColor: tokens.controlSurface,
        selectedColor: colors.primary,
        labelStyle: TextStyle(color: colors.onSurface),
        secondaryLabelStyle: TextStyle(color: colors.onPrimary),
        showCheckmark: false,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.controlRadius),
          ),
          side: BorderSide(
            color: tokens.borderSubtle,
            width: VeneraDesignTokens.hairline,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: tokens.controlSurface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: VeneraDesignTokens.space16,
          vertical: VeneraDesignTokens.space12,
        ),
        hintStyle: TextStyle(color: tokens.mutedText),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(tokens.controlRadius),
          borderSide: BorderSide(
            color: tokens.borderSubtle,
            width: VeneraDesignTokens.hairline,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(tokens.controlRadius),
          borderSide: BorderSide(
            color: tokens.borderSubtle,
            width: VeneraDesignTokens.hairline,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(tokens.controlRadius),
          borderSide: BorderSide(color: colors.primary, width: 1.2),
        ),
      ),
      dialogTheme: DialogThemeData(
        elevation: 0,
        backgroundColor: tokens.controlSurfacePressed,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.sectionRadius),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: tokens.controlSurfacePressed,
        elevation: 0,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(tokens.sectionRadius),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        backgroundColor: isDark
            ? const Color(0xFF2C2C2E)
            : const Color(0xFF323234),
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.controlRadius),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        elevation: 0,
        color: tokens.controlSurfacePressed,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.controlRadius),
          side: BorderSide(
            color: tokens.borderSubtle,
            width: VeneraDesignTokens.hairline,
          ),
        ),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          elevation: const WidgetStatePropertyAll(0),
          backgroundColor: WidgetStatePropertyAll(tokens.controlSurfacePressed),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(tokens.controlRadius),
              side: BorderSide(
                color: tokens.borderSubtle,
                width: VeneraDesignTokens.hairline,
              ),
            ),
          ),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark
              ? const Color(0xFF2C2C2E)
              : const Color(0xFF323234),
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 12),
      ),
      fontFamily: font,
      fontFamilyFallback: fallback,
      sliderTheme: appSliderTheme(colors),
      // ExpansionTile shows top/bottom divider lines when expanded by default.
      // Override globally with borderless shapes so no expandable tile (task
      // cards, reader settings groups, source dialogs, etc.) renders stray
      // lines at its top and bottom.
      expansionTileTheme: const ExpansionTileThemeData(
        shape: Border(),
        collapsedShape: Border(),
      ),
      // Covers the routes that aren't AppPageRoute (they read the same setting
      // themselves) so the back gesture behaves the same everywhere (#194).
      pageTransitionsTheme:
          App.isAndroid && appdata.settings['enablePredictiveBack'] == false
          ? const PageTransitionsTheme(
              builders: {
                TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
              },
            )
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(builder: (light, dark) {
      Color? primary, secondary, tertiary;
      if (appdata.settings['color'] != 'system' ||
          light == null ||
          dark == null) {
        primary = translateColorSetting();
      } else {
        primary = light.primary;
        secondary = light.secondary;
        tertiary = light.tertiary;
      }
      return MaterialApp(
        title: "VeneraX",
        home: const StartupPage(),
        debugShowCheckedModeBanner: false,
        theme: getTheme(primary, secondary, tertiary, Brightness.light),
        navigatorKey: App.rootNavigatorKey,
        navigatorObservers: [App.rootRouteObserver],
        darkTheme: getTheme(primary, secondary, tertiary, Brightness.dark),
        themeMode: switch (appdata.settings['theme_mode']) {
          'light' => ThemeMode.light,
          'dark' => ThemeMode.dark,
          _ => ThemeMode.system
        },
        color: Colors.transparent,
        localizationsDelegates: [
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        locale: () {
          var lang = appdata.settings['language'];
          if (lang == 'system') {
            return null;
          }
          return switch (lang) {
            'zh-CN' => const Locale('zh', 'CN'),
            'zh-TW' => const Locale('zh', 'TW'),
            'en-US' => const Locale('en'),
            _ => null
          };
        }(),
        supportedLocales: const [
          Locale('zh', 'CN'),
          Locale('zh', 'TW'),
          Locale('en'),
        ],
        builder: (context, widget) {
          ErrorWidget.builder = (details) {
            Log.error("Unhandled Exception",
                "${details.exception}\n${details.stack}");
            return Material(
              child: Center(
                child: Text(details.exception.toString()),
              ),
            );
          };
          if (widget != null) {
            /// 如果无法检测到状态栏高度设定指定高度
            /// https://github.com/flutter/flutter/issues/161086
            var viewPaddingTop = MediaQuery.viewPaddingOf(context).top;
            var isPaddingCheckError =
                viewPaddingTop <= 0 || viewPaddingTop > 200;

            if (isPaddingCheckError && Platform.isAndroid) {
              widget = MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    viewPadding: const EdgeInsets.only(
                      top: 15,
                      bottom: 15,
                    ),
                    padding: const EdgeInsets.only(
                      top: 15,
                      bottom: 15,
                    ),
                  ),
                  child: widget);
            }

            widget = OverlayWidget(widget);
            if (App.isDesktop) {
              widget = Shortcuts(
                shortcuts: {
                  LogicalKeySet(LogicalKeyboardKey.escape): VoidCallbackIntent(
                    App.pop,
                  ),
                },
                child: MouseBackDetector(
                  onTapDown: App.pop,
                  child: WindowFrame(widget),
                ),
              );
            }
            return _SystemUiProvider(Material(
              color: App.isLinux ? Colors.transparent : null,
              child: widget,
            ));
          }
          throw ('widget is null');
        },
      );
    });
  }
}

class _SystemUiProvider extends StatelessWidget {
  const _SystemUiProvider(this.child);

  final Widget child;

  @override
  Widget build(BuildContext context) {
    var brightness = Theme.of(context).brightness;
    SystemUiOverlayStyle systemUiStyle;
    if (brightness == Brightness.light) {
      systemUiStyle = SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarContrastEnforced: false,
      );
    } else {
      systemUiStyle = SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarContrastEnforced: false,
      );
    }
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: systemUiStyle,
      child: child,
    );
  }
}
