import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/kit.dart';
import '../ui/perf.dart';
import '../ui/theme.dart';

/// The short build-to-logo sequence shown once after a sign-in.
///
/// A goldfish is drawn as a constellation: stars appear along its outline and
/// the lines between them settle in. The fish then opens, the stars crossing
/// the screen to write **Sora PoS**, and a thin subtitle resolves underneath.
/// It is intentionally short, runs only when the signed-in person changes,
/// respects reduced motion at the call site and can be skipped with any key.
class BrandBootScreen extends StatefulWidget {
  final SoraPalette palette;
  final VoidCallback onDone;
  final Duration duration;

  const BrandBootScreen({
    super.key,
    required this.palette,
    required this.onDone,
    this.duration = const Duration(milliseconds: 1750),
  });

  @override
  State<BrandBootScreen> createState() => _BrandBootScreenState();
}

class _BrandBootScreenState extends State<BrandBootScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  final DateTime _startedAt = DateTime.now();
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: widget.duration)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _finish();
      })
      ..forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _finish() {
    if (_finished || !mounted) return;
    _finished = true;
    widget.onDone();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    // The Enter that submitted the password can still be on its way down. Do
    // not let it skip the moment before it has started.
    if (DateTime.now().difference(_startedAt) <
        const Duration(milliseconds: 260)) {
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      _finish();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  double _interval(double t, double begin, double end) =>
      ((t - begin) / (end - begin)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final reduced = MediaQuery.disableAnimationsOf(context);
    return AuroraBackground(
      palette: p,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Focus(
          autofocus: true,
          onKeyEvent: _onKey,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: Container(
                  width: 900,
                  height: 600,
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      colors: [
                        p.accent.withValues(alpha: p.matte ? 0.045 : 0.075),
                        Colors.transparent,
                      ],
                      stops: const [0, 1],
                    ),
                  ),
                ),
              ),
              Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: SizedBox(
                    width: 860,
                    height: 320,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: RepaintBoundary(
                            child: AnimatedBuilder(
                              animation: _c,
                              builder: (context, _) => CustomPaint(
                                painter: _ConstellationPainter(
                                  palette: p,
                                  time: reduced ? 1.0 : _c.value,
                                  lite: SoraPerf.lite,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          top: 238,
                          child: AnimatedBuilder(
                            animation: _c,
                            builder: (context, _) {
                              final t = reduced ? 1.0 : _c.value;
                              final settle = Curves.easeOutCubic.transform(
                                _interval(t, 0.82, 0.96),
                              );
                              return Opacity(
                                opacity: settle,
                                child: Transform.translate(
                                  offset: Offset(0, 6 * (1 - settle)),
                                  child: Text(
                                    'POINT OF SALE',
                                    textAlign: TextAlign.center,
                                    style: overlineStyle(
                                      p,
                                      color: p.accent.withValues(alpha: 0.88),
                                    ).copyWith(letterSpacing: 4.2),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 34,
                child: AnimatedBuilder(
                  animation: _c,
                  builder: (context, _) {
                    final t = reduced ? 1.0 : _c.value;
                    return Opacity(
                      opacity: _interval(t, 0.76, 0.98) * 0.65,
                      child: Text(
                        'PRESS ANY KEY',
                        textAlign: TextAlign.center,
                        style: overlineStyle(p).copyWith(letterSpacing: 2.6),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- geometry

class _FishLink {
  final int a;
  final int b;
  const _FishLink(this.a, this.b);
}

class _WordLink {
  final int a;
  final int b;
  const _WordLink(this.a, this.b);
}

class _Word {
  final List<Offset> points;
  final List<_WordLink> links;
  final Rect bounds;
  const _Word(this.points, this.links, this.bounds);
}

const List<Offset> _fish = [
  // Body, nose at the right.
  Offset(148, 8),
  Offset(128, -26),
  Offset(92, -50),
  Offset(44, -62),
  Offset(-8, -62),
  Offset(-58, -54),
  Offset(-98, -34),
  Offset(-116, -8),
  Offset(-116, 10),
  Offset(-98, 34),
  Offset(-58, 54),
  Offset(-8, 62),
  Offset(44, 62),
  Offset(92, 48),
  Offset(128, 26),
  // Tail fan.
  Offset(-190, -70),
  Offset(-170, -14),
  Offset(-208, 6),
  Offset(-170, 26),
  Offset(-190, 70),
  // Dorsal fin.
  Offset(0, -108),
  Offset(-40, -102),
  Offset(-66, -52),
  // Pectoral fin.
  Offset(72, 86),
  Offset(10, 60),
  // Eye.
  Offset(104, -18),
  // Ambient stars inside the body, so the fish has depth.
  Offset(18, -18),
  Offset(58, 12),
  Offset(-20, 22),
  Offset(-62, -12),
  Offset(84, -28),
  Offset(-2, 2),
  Offset(-82, 12),
  Offset(30, 34),
];

const List<_FishLink> _fishLinks = [
  _FishLink(0, 1),
  _FishLink(1, 2),
  _FishLink(2, 3),
  _FishLink(3, 4),
  _FishLink(4, 5),
  _FishLink(5, 6),
  _FishLink(6, 7),
  _FishLink(7, 8),
  _FishLink(8, 9),
  _FishLink(9, 10),
  _FishLink(10, 11),
  _FishLink(11, 12),
  _FishLink(12, 13),
  _FishLink(13, 14),
  _FishLink(14, 0),
  _FishLink(7, 15),
  _FishLink(15, 16),
  _FishLink(16, 17),
  _FishLink(17, 18),
  _FishLink(18, 19),
  _FishLink(19, 8),
  _FishLink(3, 20),
  _FishLink(20, 21),
  _FishLink(21, 22),
  _FishLink(22, 5),
  _FishLink(12, 23),
  _FishLink(23, 24),
  _FishLink(24, 11),
];

const int _fishEye = 25;
const int _fishOutline = 26;

final _Word _word = _buildWord();

_Word _buildWord() {
  final points = <Offset>[];
  final links = <_WordLink>[];
  var pen = 0.0;

  void glyph(List<Path> Function(double x) strokes, double advance) {
    for (final stroke in strokes(pen)) {
      final sampled = _sampleStroke(stroke, 8.2);
      final start = points.length;
      points.addAll(sampled);
      for (var i = start + 1; i < points.length; i++) {
        links.add(_WordLink(i - 1, i));
      }
    }
    pen += advance;
  }

  // S
  glyph(
    (x) => [
      Path()
        ..moveTo(x + 50, 18)
        ..cubicTo(x + 44, 6, x + 18, 2, x + 9, 16)
        ..cubicTo(x - 2, 34, x + 20, 44, x + 34, 52)
        ..cubicTo(x + 50, 61, x + 48, 84, x + 32, 92)
        ..cubicTo(x + 20, 98, x + 6, 94, x + 1, 84),
    ],
    70,
  );
  // o
  glyph((x) => [Path()..addOval(Rect.fromLTWH(x + 6, 34, 40, 62))], 58);
  // r
  glyph(
    (x) => [
      Path()
        ..moveTo(x + 8, 96)
        ..lineTo(x + 8, 35)
        ..cubicTo(x + 12, 26, x + 30, 24, x + 40, 32),
    ],
    50,
  );
  // a
  glyph(
    (x) => [
      Path()..addOval(Rect.fromLTWH(x + 4, 34, 36, 62)),
      Path()
        ..moveTo(x + 44, 35)
        ..lineTo(x + 44, 96),
    ],
    60,
  );
  // space
  pen += 30;
  // P
  glyph(
    (x) => [
      Path()
        ..moveTo(x + 8, 96)
        ..lineTo(x + 8, 4)
        ..lineTo(x + 32, 4)
        ..cubicTo(x + 56, 4, x + 56, 50, x + 32, 50)
        ..lineTo(x + 8, 50),
    ],
    66,
  );
  // o
  glyph((x) => [Path()..addOval(Rect.fromLTWH(x + 6, 34, 40, 62))], 58);
  // S
  glyph(
    (x) => [
      Path()
        ..moveTo(x + 50, 18)
        ..cubicTo(x + 44, 6, x + 18, 2, x + 9, 16)
        ..cubicTo(x - 2, 34, x + 20, 44, x + 34, 52)
        ..cubicTo(x + 50, 61, x + 48, 84, x + 32, 92)
        ..cubicTo(x + 20, 98, x + 6, 94, x + 1, 84),
    ],
    70,
  );

  var left = double.infinity;
  var top = double.infinity;
  var right = -double.infinity;
  var bottom = -double.infinity;
  for (final point in points) {
    left = math.min(left, point.dx);
    top = math.min(top, point.dy);
    right = math.max(right, point.dx);
    bottom = math.max(bottom, point.dy);
  }
  return _Word(points, links, Rect.fromLTRB(left, top, right, bottom));
}

List<Offset> _sampleStroke(Path path, double spacing) {
  final points = <Offset>[];
  for (final metric in path.computeMetrics()) {
    final length = metric.length;
    if (length < 0.5) continue;
    final count = math.max(3, (length / spacing).ceil());
    for (var i = 0; i < count; i++) {
      final tangent = metric.getTangentForOffset(length * i / count);
      if (tangent != null) points.add(tangent.position);
    }
  }
  return points;
}

double _noise(int seed) {
  var x = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
  x ^= x >> 15;
  x = (x * 2246822519) & 0x7FFFFFFF;
  return (x % 100000) / 100000;
}

double _span(double t, double begin, double end) =>
    ((t - begin) / (end - begin)).clamp(0.0, 1.0);

// ----------------------------------------------------------------- painter

class _StarFrame {
  final Offset position;
  final double opacity;
  final double radius;
  final Color color;
  final double settled;
  const _StarFrame(
    this.position,
    this.opacity,
    this.radius,
    this.color,
    this.settled,
  );
}

class _ConstellationPainter extends CustomPainter {
  final SoraPalette palette;
  final double time;
  final bool lite;

  _ConstellationPainter({
    required this.palette,
    required this.time,
    this.lite = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final p = palette;
    final t = time.clamp(0.0, 1.0);
    const center = Offset(430, 122);
    final wordScale = 690 / _word.bounds.width;
    final wordOrigin = Offset(
      center.dx - _word.bounds.center.dx * wordScale,
      center.dy - _word.bounds.center.dy * wordScale,
    );
    final fishCenter = Offset(430, 126);
    const fishScale = 1.12;

    Offset wordPoint(int i) => wordOrigin + _word.points[i] * wordScale;
    Offset fishPoint(int i) => fishCenter + _fish[i] * fishScale;

    final settle = Curves.easeOutCubic.transform(_span(t, 0.70, 0.94));
    if (settle > 0) {
      canvas.drawCircle(
        const Offset(430, 122),
        360,
        Paint()
          ..shader = ui.Gradient.radial(
            const Offset(430, 122),
            360,
            [p.accent.withValues(alpha: 0.060 * settle), Colors.transparent],
            const [0, 1],
          ),
      );
    }

    // The constellation lines fade as the fish opens.
    final lineFade = 1 - _span(t, 0.43, 0.57);
    if (lineFade > 0) {
      final line = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..strokeCap = StrokeCap.round
        ..color = p.accent.withValues(alpha: 0.32 * lineFade);
      for (var i = 0; i < _fishLinks.length; i++) {
        final link = _fishLinks[i];
        final start = 0.11 + 0.18 * (i / _fishLinks.length);
        final grow = Curves.easeOutCubic.transform(
          _span(t, start, start + 0.18),
        );
        if (grow <= 0) continue;
        final a = fishPoint(link.a);
        final b = fishPoint(link.b);
        canvas.drawLine(a, Offset.lerp(a, b, grow)!, line);
      }
    }

    final stars = List<_StarFrame?>.filled(_word.points.length, null);
    for (var i = 0; i < _word.points.length; i++) {
      final originIndex = i % _fish.length;
      final onFish = i < _fish.length;
      final delay = _noise(i + 11);
      final target = wordPoint(i);
      final source = fishPoint(originIndex);

      final Offset from;
      final double appear;
      final double radius;
      if (onFish) {
        from = source;
        final start = 0.015 + delay * 0.14;
        appear = _span(t, start, start + 0.16);
        radius = i == _fishEye
            ? 2.9
            : i < _fishOutline
            ? 1.55 + _noise(i + 3) * 0.6
            : 0.95 + _noise(i + 3) * 0.5;
      } else {
        final angle = _noise(i + 7) * math.pi * 2;
        final distance = 4 + _noise(i + 17) * 13;
        from = source + Offset(math.cos(angle), math.sin(angle)) * distance;
        appear = _span(t, 0.44 + delay * 0.10, 0.52 + delay * 0.10);
        radius = 1.05 + _noise(i + 5) * 0.8;
      }

      final moveStart = (onFish ? 0.46 : 0.47) + delay * 0.09;
      final settleAt = Curves.easeInOutCubic.transform(
        _span(t, moveStart, moveStart + 0.31),
      );
      if (appear <= 0) continue;
      stars[i] = _StarFrame(
        Offset.lerp(from, target, settleAt)!,
        appear,
        radius,
        i % 9 == 0 ? p.accent : p.text,
        settleAt,
      );
    }

    // Halo first, so the cores sit in a single light pass above them.
    if (!lite) {
      final halo = Paint();
      for (final star in stars) {
        if (star == null) continue;
        halo.color = p.accent.withValues(
          alpha: (p.matte ? 0.055 : 0.095) * star.opacity,
        );
        canvas.drawCircle(star.position, star.radius * 2.7, halo);
      }
    }
    for (final star in stars) {
      if (star == null) continue;
      canvas.drawCircle(
        star.position,
        star.radius,
        Paint()..color = star.color.withValues(alpha: 0.92 * star.opacity),
      );
    }

    // Fine joins between neighbouring letter stars, once they have landed.
    final joinAlpha = lite ? 0.0 : _span(t, 0.74, 0.92) * 0.13;
    if (joinAlpha > 0) {
      final join = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.7
        ..color = p.accent.withValues(alpha: joinAlpha);
      for (final link in _word.links) {
        final a = stars[link.a];
        final b = stars[link.b];
        if (a == null || b == null) continue;
        if (a.settled < 0.9 || b.settled < 0.9) continue;
        canvas.drawLine(a.position, b.position, join);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ConstellationPainter old) =>
      old.time != time ||
      old.lite != lite ||
      old.palette.id != palette.id ||
      old.palette.accent != palette.accent ||
      old.palette.text != palette.text ||
      old.palette.matte != palette.matte;
}
