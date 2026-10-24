import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import 'cart.dart';
import 'screens/brand_boot.dart';
import 'screens/shell.dart';
import 'screens/signin.dart';
import 'screens/splash.dart';
import 'services/email.dart';
import 'services/native.dart';
import 'services/paths.dart';
import 'store.dart';
import 'ui/theme.dart';
import 'ui/theme_switcher.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.environment['SORA_TIMINGS'] == '1') _logSlowFrames();
  if (Platform.environment['SORA_MEMLOG'] == '1') _logMemory();
  FlutterError.onError = (details) {
    _logError(
      details.exception,
      details.stack,
      details.context?.toString() ?? 'Flutter error',
    );
    FlutterError.presentError(details);
  };
  ui.PlatformDispatcher.instance.onError = (error, stack) {
    _logError(error, stack, 'Uncaught platform error');
    return false;
  };
  final store = Store();
  try {
    await store.init();
  } catch (e, s) {
    _logError(e, s, 'Startup');
    runApp(_StartupError(error: '$e'));
    return;
  }
  runApp(SoraApp(store: store));
}

void _logSlowFrames() {
  final dir = soraDataDirectory()..createSync(recursive: true);
  final file = File(joinPath(dir.path, 'sora-timings.log'));
  final pending = <String>[];
  var lastFlush = DateTime.now();
  SchedulerBinding.instance.addTimingsCallback((timings) {
    for (final t in timings) {
      final total = t.totalSpan.inMilliseconds;
      if (total >= 32) {
        pending.add(
          '${DateTime.now().toIso8601String()} build=${t.buildDuration.inMilliseconds} '
          'raster=${t.rasterDuration.inMilliseconds} total=$total',
        );
      }
    }
    if (pending.isNotEmpty &&
        DateTime.now().difference(lastFlush).inMilliseconds > 500) {
      try {
        file.writeAsStringSync(
          '${pending.join('\n')}\n',
          mode: FileMode.append,
          flush: true,
        );
      } catch (_) {}
      pending.clear();
      lastFlush = DateTime.now();
    }
  });
}

void _logMemory() {
  final dir = soraDataDirectory()..createSync(recursive: true);
  final file = File(joinPath(dir.path, 'sora-memory.log'));
  Timer.periodic(const Duration(seconds: 5), (_) {
    final rss = ProcessInfo.currentRss;
    final maxRss = ProcessInfo.maxRss;
    try {
      file.writeAsStringSync(
        '${DateTime.now().toIso8601String()} rss=${(rss / 1048576).toStringAsFixed(0)}MB peak=${(maxRss / 1048576).toStringAsFixed(0)}MB\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {}
  });
}

void _logError(Object error, StackTrace? stack, String source) {
  try {
    final dir = soraDataDirectory()..createSync(recursive: true);
    File(joinPath(dir.path, 'sora-errors.log')).writeAsStringSync(
      '${DateTime.now().toIso8601String()} · $source\n$error\n${stack ?? ''}\n\n',
      mode: FileMode.append,
      flush: true,
    );
  } catch (_) {
    // The error log itself must never be the reason the app fails.
  }
}

class SoraApp extends StatefulWidget {
  final Store store;
  const SoraApp({super.key, required this.store});

  @override
  State<SoraApp> createState() => _SoraAppState();
}

class _SoraAppState extends State<SoraApp> with SingleTickerProviderStateMixin {
  final CartController _cart = CartController();
  final GlobalKey _captureKey = GlobalKey();
  late final AnimationController _spreadController;
  ui.Image? _spreadImage;
  Offset? _spreadOrigin;
  bool _spreading = false;
  Timer? _mailTimer;
  String? _chromeTheme;

  Store get store => widget.store;

  @override
  void initState() {
    super.initState();
    _spreadController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 680),
    );
    ThemeSwitcher.instance.register(_changeTheme);
    store.addListener(_applyWindowChrome);
    _mailTimer = Timer.periodic(const Duration(minutes: 1), (_) => _tick());
    Future<void>.delayed(const Duration(seconds: 20), _tick);
    Future<void>.delayed(const Duration(milliseconds: 900), _applyWindowChrome);
  }

  @override
  void dispose() {
    ThemeSwitcher.instance.register(null);
    store.removeListener(_applyWindowChrome);
    _mailTimer?.cancel();
    _spreadController.dispose();
    _spreadImage?.dispose();
    super.dispose();
  }

  Future<void> _tick() async {
    if (!mounted) return;
    store.checkAbandonedHolds();
    await EmailService.tick(store);
  }

  void _applyWindowChrome() {
    final palette = SoraPalette.fromAppearance(store.data.appearance);
    final key = '${palette.windowIcon}|${palette.captionColor.toARGB32()}';
    if (_chromeTheme == key) return;
    _chromeTheme = key;
    NativeCore.setWindowIcon(palette.windowIcon);
    NativeCore.setCaptionColor(palette.captionColor.toARGB32());
  }

  Future<void> _changeTheme(String themeId, Offset? globalOrigin) async {
    if (!mounted) return;
    if (store.data.appearance.themeId == themeId &&
        !themeId.startsWith('custom'))
      return;
    if (_spreading) {
      store.data.appearance.themeId = themeId;
      store.changed();
      return;
    }

    final captureContext = _captureKey.currentContext;
    final boundary = captureContext?.findRenderObject();
    ui.Image? image;
    if (boundary is RenderRepaintBoundary) {
      try {
        await WidgetsBinding.instance.endOfFrame;
        image = await boundary.toImage(pixelRatio: 0.7);
      } catch (_) {
        image = null;
      }
    }

    if (!mounted) {
      image?.dispose();
      return;
    }

    final reduced = captureContext == null
        ? false
        : (MediaQuery.maybeOf(captureContext)?.disableAnimations ?? false);
    if (image == null || reduced || boundary is! RenderBox) {
      image?.dispose();
      store.data.appearance.themeId = themeId;
      store.changed();
      return;
    }

    final localOrigin = globalOrigin == null
        ? boundary.size.center(Offset.zero)
        : boundary.globalToLocal(globalOrigin);

    setState(() {
      _spreadImage = image;
      _spreadOrigin = localOrigin;
      _spreading = true;
    });
    store.data.appearance.themeId = themeId;
    store.changed();

    try {
      await _spreadController.forward(from: 0);
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _spreading = false;
      _spreadImage?.dispose();
      _spreadImage = null;
      _spreadOrigin = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final appearance = store.data.appearance;
        final palette = SoraPalette.fromAppearance(appearance);
        final theme = buildSoraTheme(palette, appearance.fontIndex);
        return MaterialApp(
          title: 'Sora PoS',
          debugShowCheckedModeBanner: false,
          theme: theme,
          scrollBehavior: const _SoraScrollBehavior(),
          builder: (context, child) {
            final mq = MediaQuery.of(context);
            return MediaQuery(
              data: mq.copyWith(
                textScaler: TextScaler.linear(appearance.textScale),
                disableAnimations: mq.disableAnimations,
              ),
              child: ThemeSpreadLayer(
                controller: _spreadController,
                image: _spreadImage,
                origin: _spreadOrigin,
                palette: palette,
                child: RepaintBoundary(
                  key: _captureKey,
                  child: child ?? const SizedBox.shrink(),
                ),
              ),
            );
          },
          home: _SplashGate(store: store, cart: _cart, palette: palette),
        );
      },
    );
  }
}

class _SplashGate extends StatefulWidget {
  final Store store;
  final CartController cart;
  final SoraPalette palette;
  const _SplashGate({
    required this.store,
    required this.cart,
    required this.palette,
  });

  @override
  State<_SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<_SplashGate> {
  bool _splash = true;
  Timer? _timer;
  String? _lastStaffId;
  String? _bootedFor;

  @override
  void initState() {
    super.initState();
    _lastStaffId = widget.store.current?.id;
    widget.store.addListener(_onStoreChanged);
    _timer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _splash = false);
    });
  }

  void _onStoreChanged() {
    final id = widget.store.current?.id;
    if (id == _lastStaffId) return;
    _lastStaffId = id;
    if (id == null) _bootedFor = null;
    if (mounted) setState(() {});
  }

  void _finishBoot(String id) {
    if (!mounted || widget.store.current?.id != id) return;
    setState(() => _bootedFor = id);
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStoreChanged);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final staff = widget.store.current;
    final Widget child;
    if (_splash) {
      child = SplashScreen(
        key: const ValueKey('splash'),
        palette: widget.palette,
        animate: !reduced,
      );
    } else if (staff == null) {
      _bootedFor = null;
      child = SignInScreen(key: const ValueKey('signin'), store: widget.store);
    } else if (reduced) {
      // Reduced motion: the brand moment is a still frame, so skip it whole.
      _bootedFor = staff.id;
      child = AppShell(
        key: ValueKey('shell-${staff.id}'),
        store: widget.store,
        cart: widget.cart,
      );
    } else if (_bootedFor != staff.id) {
      child = BrandBootScreen(
        key: ValueKey('boot-${staff.id}'),
        palette: widget.palette,
        onDone: () => _finishBoot(staff.id),
      );
    } else {
      child = AppShell(
        key: ValueKey('shell-${staff.id}'),
        store: widget.store,
        cart: widget.cart,
      );
    }
    return AnimatedSwitcher(
      duration: reduced ? Duration.zero : const Duration(milliseconds: 420),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: child,
    );
  }
}

class _SoraScrollBehavior extends MaterialScrollBehavior {
  const _SoraScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
  };
}

class _StartupError extends StatelessWidget {
  final String error;
  const _StartupError({required this.error});

  @override
  Widget build(BuildContext context) {
    const night = Color(0xFF070B11);
    const accent = Color(0xFF2DD4BF);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: night,
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 42,
                    color: accent,
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Sora could not open',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      fontFamily: 'Inter',
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    error,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.5,
                      color: Color(0xB3E4E8F2),
                      fontFamily: 'Inter',
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Your data file has not been touched. Close the app and try again.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0x73DCE2EE),
                      fontFamily: 'Inter',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
