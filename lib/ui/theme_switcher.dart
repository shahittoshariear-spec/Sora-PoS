import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../store.dart';
import 'theme.dart';

typedef ThemeChangeHandler = Future<void> Function(String themeId, Offset? globalOrigin);

/// Lets any screen ask the app root to change theme with a spreading reveal.
class ThemeSwitcher {
  ThemeSwitcher._();
  static final ThemeSwitcher instance = ThemeSwitcher._();

  ThemeChangeHandler? _handler;

  void register(ThemeChangeHandler? handler) => _handler = handler;

  /// Returns true when the app root handled the change and will animate it.
  Future<bool> request(String themeId, Offset? globalOrigin) async {
    final handler = _handler;
    if (handler == null) return false;
    await handler(themeId, globalOrigin);
    return true;
  }
}

/// Use this from any theme picker. If the app root is not available (or the
/// transition falls back), the theme is still applied and saved.
Future<void> pickTheme(Store store, String themeId, Offset? origin) async {
  final handled = await ThemeSwitcher.instance.request(themeId, origin);
  if (!handled) {
    store.data.appearance.themeId = themeId;
    store.changed();
  }
}

/// Paints the old screen as a snapshot while the new theme is revealed from
/// the point the person tapped. The edge carries a soft accent glow so the
/// wipe reads as a material change, not a hard clip.
class ThemeSpreadLayer extends StatelessWidget {
  final AnimationController controller;
  final ui.Image? image;
  final Offset? origin;
  final SoraPalette palette;
  final Widget child;

  const ThemeSpreadLayer({
    super.key,
    required this.controller,
    required this.image,
    required this.origin,
    required this.palette,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (image == null) return child;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        return AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            if (controller.value >= 0.999) return child;
            final center = origin ?? size.center(Offset.zero);
            final maxRadius = _farthestCorner(center, size);
            final progress = Curves.easeOutQuint.transform(controller.value.clamp(0.0, 1.0));
            final radius = maxRadius * progress;
            return AbsorbPointer(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  RawImage(image: image, fit: BoxFit.fill, filterQuality: FilterQuality.medium),
                  ClipPath(
                    clipper: _RevealClipper(center: center, radius: radius),
                    child: child,
                  ),
                  IgnorePointer(
                    child: CustomPaint(
                      painter: _RevealEdgePainter(center: center, radius: radius, palette: palette, opacity: 1 - progress),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  static double _farthestCorner(Offset center, Size size) {
    final corners = [Offset.zero, Offset(size.width, 0), Offset(0, size.height), Offset(size.width, size.height)];
    var maxDistance = 0.0;
    for (final corner in corners) {
      maxDistance = math.max(maxDistance, (corner - center).distance);
    }
    return maxDistance + 2;
  }
}

class _RevealClipper extends CustomClipper<Path> {
  final Offset center;
  final double radius;
  _RevealClipper({required this.center, required this.radius});

  @override
  Path getClip(Size size) => Path()..addOval(Rect.fromCircle(center: center, radius: radius));

  @override
  bool shouldReclip(covariant _RevealClipper old) => old.center != center || old.radius != radius;
}

class _RevealEdgePainter extends CustomPainter {
  final Offset center;
  final double radius;
  final SoraPalette palette;
  final double opacity;

  _RevealEdgePainter({required this.center, required this.radius, required this.palette, required this.opacity});

  @override
  void paint(Canvas canvas, Size size) {
    if (radius <= 1 || opacity <= 0) return;
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = palette.accent.withValues(alpha: 0.55 * opacity)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 9);
    canvas.drawCircle(center, radius, glow);
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.32 * opacity);
    canvas.drawCircle(center, radius, edge);
  }

  @override
  bool shouldRepaint(covariant _RevealEdgePainter old) =>
      old.center != center || old.radius != radius || old.palette.id != palette.id || old.opacity != opacity;
}
