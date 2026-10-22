import 'package:flutter/material.dart';

import '../ui/kit.dart';
import '../ui/theme.dart';

class SplashScreen extends StatefulWidget {
  final SoraPalette palette;
  final bool animate;
  const SplashScreen({super.key, required this.palette, this.animate = true});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    return AuroraBackground(
      palette: p,
      animate: widget.animate,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, child) {
              final t = Curves.easeOutCubic.transform(_c.value.clamp(0.0, 1.0));
              return Opacity(
                opacity: t,
                child: Transform.translate(
                  offset: Offset(0, 18 * (1 - t)),
                  child: Transform.scale(scale: 0.94 + 0.06 * t, child: child),
                ),
              );
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ThemedMark(palette: p, size: 124),
                const SizedBox(height: 30),
                Text(
                  'SORA',
                  style: TextStyle(
                    fontSize: 42,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 16,
                    color: p.text,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 12),
                Text('POINT OF SALE', style: overlineStyle(p, color: p.accent)),
                const SizedBox(height: 38),
                SizedBox(
                  width: 160,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      minHeight: 2,
                      backgroundColor: p.raised,
                      color: p.accent,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Opening your shop',
                  style: TextStyle(fontSize: 11.5, color: p.faint, letterSpacing: 0.3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
