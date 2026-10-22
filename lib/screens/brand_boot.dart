import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/kit.dart';
import '../ui/theme.dart';

/// The short build-to-logo sequence shown once after a sign-in.
///
/// The S.S monogram settles inside a thin accent ring, `SORA` tightens into
/// place, then the shell crossfades in. It is intentionally short, runs only
/// when the signed-in person changes, respects reduced motion at the call site
/// and can be skipped with any key.
class BrandBootScreen extends StatefulWidget {
  final SoraPalette palette;
  final VoidCallback onDone;
  final Duration duration;

  const BrandBootScreen({
    super.key,
    required this.palette,
    required this.onDone,
    this.duration = const Duration(milliseconds: 1450),
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
                  width: 640,
                  height: 640,
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      colors: [
                        p.accent.withValues(alpha: p.matte ? 0.05 : 0.075),
                        Colors.transparent,
                      ],
                      stops: const [0, 1],
                    ),
                  ),
                ),
              ),
              Center(
                child: AnimatedBuilder(
                  animation: _c,
                  builder: (context, _) {
                    final t = reduced ? 1.0 : _c.value;
                    final mark = Curves.easeOutCubic.transform(
                      _interval(t, 0, 0.50),
                    );
                    final ring = Curves.easeInOutCubic.transform(
                      _interval(t, 0.16, 0.86),
                    );
                    final word = Curves.easeOutCubic.transform(
                      _interval(t, 0.24, 0.72),
                    );
                    final sub = Curves.easeOutCubic.transform(
                      _interval(t, 0.52, 0.88),
                    );

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 196,
                          height: 196,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              CustomPaint(
                                size: const Size.square(196),
                                painter: _BootRingPainter(p: p, progress: ring),
                              ),
                              Opacity(
                                opacity: mark,
                                child: Transform.scale(
                                  scale: 0.86 + 0.14 * mark,
                                  child: _BootMonogram(p: p, progress: mark),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 30),
                        Opacity(
                          opacity: word,
                          child: Transform.translate(
                            offset: Offset(0, 10 * (1 - word)),
                            child: Text(
                              'SORA',
                              style: TextStyle(
                                fontSize: 40,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 30 - 14 * word,
                                height: 1,
                                color: p.text,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 13),
                        Opacity(
                          opacity: sub,
                          child: Transform.translate(
                            offset: Offset(0, 5 * (1 - sub)),
                            child: Text(
                              'POINT OF SALE',
                              style: overlineStyle(
                                p,
                                color: p.accent.withValues(alpha: 0.85),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
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
                      opacity: _interval(t, 0.70, 1.0) * 0.65,
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

/// A large, flat S.S monogram. It is the same signature the side nav wears,
/// scaled up for the one moment after sign-in.
class _BootMonogram extends StatelessWidget {
  final SoraPalette p;
  final double progress;

  const _BootMonogram({required this.p, required this.progress});

  @override
  Widget build(BuildContext context) {
    final cosmic = Color.lerp(p.accent, const Color(0xFF7C6BFF), 0.5)!;
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => LinearGradient(
        begin: Alignment(-1.2 + 1.4 * progress, -0.5),
        end: Alignment(0.2 + 1.4 * progress, 0.5),
        colors: [p.accent.withValues(alpha: 0.82), p.accent, cosmic, p.accent2],
        stops: const [0, 0.42, 0.72, 1],
      ).createShader(bounds),
      child: Text(
        'S.S',
        style: TextStyle(
          fontSize: 62,
          fontWeight: FontWeight.w700,
          letterSpacing: 2.4 - 1.2 * progress,
          height: 1,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _BootRingPainter extends CustomPainter {
  final SoraPalette p;
  final double progress;

  _BootRingPainter({required this.p, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 2;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = p.hairline;
    canvas.drawCircle(center, radius, track);

    if (progress <= 0) return;
    const start = -math.pi / 2;
    final sweep = 2 * math.pi * Curves.easeOutCubic.transform(progress);
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 5
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6)
      ..color = p.accent.withValues(alpha: p.matte ? 0.16 : 0.26);
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.7
      ..shader = SweepGradient(
        startAngle: start,
        endAngle: start + 2 * math.pi,
        colors: [p.accent, p.accent2, p.accent],
        transform: const GradientRotation(-math.pi / 2),
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawArc(rect, start, sweep, false, glow);
    canvas.drawArc(rect, start, sweep, false, arc);
  }

  @override
  bool shouldRepaint(covariant _BootRingPainter old) =>
      old.progress != progress ||
      old.p.id != p.id ||
      old.p.matte != p.matte ||
      old.p.accent != p.accent;
}
