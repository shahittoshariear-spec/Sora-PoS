import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// A tiny global gate for decorative motion. A screen holds it while the user
/// is resizing something (the till divider), so the S.S sweep stops competing
/// with the gesture for raster time. The aurora itself is static and does not
/// listen to this gate.
class SoraMotion {
  SoraMotion._();
  static int _holds = 0;
  static final ValueNotifier<bool> paused = ValueNotifier<bool>(false);

  static void hold() {
    _holds++;
    if (!paused.value) paused.value = true;
  }

  static void release() {
    if (_holds > 0) _holds--;
    if (_holds == 0) paused.value = false;
  }
}

/// The room behind the app: a layered night gradient, fixed aurora blobs, a
/// faint star field and a vignette. It is deliberately still. The old field
/// drifted and followed the pointer, which read as flicker on some screens and
/// kept the GPU awake between gestures. Nothing here starts a timer or listens
/// to the pointer; the layer repaints only when the palette changes.
class AuroraBackground extends StatelessWidget {
  final Widget child;
  final SoraPalette palette;

  /// Kept for call-site compatibility. The background is always still now.
  final bool animate;

  const AuroraBackground({
    super.key,
    required this.child,
    required this.palette,
    this.animate = true,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // The background lives in its own layer so a palette change never
        // touches the app above it.
        RepaintBoundary(child: CustomPaint(painter: _AuroraPainter(palette))),
        child,
      ],
    );
  }
}

class _AuroraPainter extends CustomPainter {
  final SoraPalette p;

  _AuroraPainter(this.p);

  static final List<Offset> _grainFine = _makeGrain(1300, 23);
  static final List<Offset> _grainCoarse = _makeGrain(460, 91);

  static List<Offset> _makeGrain(int count, int seed) {
    final rnd = math.Random(seed);
    return List<Offset>.generate(
      count,
      (_) => Offset(rnd.nextDouble(), rnd.nextDouble()),
      growable: false,
    );
  }

  List<Offset> _scaled(List<Offset> points, Size size) => [
    for (final point in points)
      Offset(point.dx * size.width, point.dy * size.height),
  ];

  /// Grain is one `drawPoints` call per layer. It keeps the large dark
  /// gradients from banding and makes the field read as a surface rather than
  /// a flat fill, without adding a texture lookup or a blur.
  void _grain(Canvas canvas, Size size) {
    final ink = p.isLight ? Colors.black : Colors.white;
    canvas.drawPoints(
      ui.PointMode.points,
      _scaled(_grainFine, size),
      Paint()
        ..color = ink.withValues(alpha: p.matte ? 0.012 : 0.020)
        ..strokeWidth = 0.8
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPoints(
      ui.PointMode.points,
      _scaled(_grainCoarse, size),
      Paint()
        ..color = ink.withValues(alpha: p.matte ? 0.018 : 0.042)
        ..strokeWidth = 1.15
        ..strokeCap = StrokeCap.round,
    );
  }

  /// A long, soft ellipse of light. Cheap: one radially shaded circle drawn
  /// through a scale transform, with no blur filter.
  void _caustic(
    Canvas canvas,
    Offset center,
    double radius,
    double angle,
    double stretch,
    Color color,
    double alpha,
  ) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);
    canvas.scale(stretch, 0.16);
    canvas.drawCircle(
      Offset.zero,
      radius,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset.zero,
          radius,
          [color.withValues(alpha: alpha), color.withValues(alpha: 0)],
          const [0, 1],
        ),
    );
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..shader = p.nightGradient.createShader(rect));

    final w = size.width;
    final h = size.height;
    final span = math.max(w, h);

    if (p.matte) {
      // Matte Flat: no stars, blobs or light bands. One barely-there tonal wash,
      // a deeper vignette and a trace of grain keep the dark field from looking
      // like dead grey or banding.
      canvas.drawRect(
        rect,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(w * 0.12, 0),
            Offset(w * 0.88, h),
            [
              p.accent.withValues(alpha: p.isLight ? 0.018 : 0.030),
              Colors.transparent,
            ],
          ),
      );
      _grain(canvas, size);
      final vignette = Paint()
        ..shader = ui.Gradient.radial(
          Offset(w * 0.5, h * 0.46),
          span * 0.82,
          [
            Colors.transparent,
            Colors.black.withValues(alpha: p.isLight ? 0.08 : 0.58),
          ],
          [0.48, 1],
        );
      canvas.drawRect(rect, vignette);
      return;
    }

    // Three slow caustic bands, painted before the blobs so they read as light
    // under the surface rather than haze on top of it.
    final cosmic = Color.lerp(p.accent, const Color(0xFF7C6BFF), 0.42)!;
    _caustic(
      canvas,
      Offset(w * 0.36, h * 0.22),
      span * 0.52,
      -0.40,
      2.7,
      p.accent,
      0.046,
    );
    _caustic(
      canvas,
      Offset(w * 0.72, h * 0.60),
      span * 0.48,
      0.34,
      3.1,
      cosmic,
      0.034,
    );
    _caustic(
      canvas,
      Offset(w * 0.18, h * 0.84),
      span * 0.42,
      -0.16,
      2.2,
      p.accent2,
      0.024,
    );

    void blob(Offset center, double radius, Color color, double alpha) {
      final shader = ui.Gradient.radial(
        center,
        radius,
        [color.withValues(alpha: alpha), color.withValues(alpha: 0)],
        [0, 1],
      );
      canvas.drawCircle(center, radius, Paint()..shader = shader);
    }

    blob(Offset(w * 0.24, h * 0.20), span * 0.54, p.accent, 0.135);
    blob(Offset(w * 0.84, h * 0.28), span * 0.44, cosmic, 0.08);
    blob(Offset(w * 0.66, h * 0.88), span * 0.50, p.accent, 0.08);
    blob(Offset(w * 0.10, h * 0.82), span * 0.40, cosmic, 0.05);

    // A quiet, fixed field of stars, because the shop is called Sora.
    final starPaint = Paint();
    final rnd = math.Random(48);
    final ink = p.isLight ? Colors.black : Colors.white;
    for (var i = 0; i < 60; i++) {
      final x = rnd.nextDouble() * w;
      final y = rnd.nextDouble() * h * 0.72;
      final bright = i % 17 == 0;
      starPaint.color = ink.withValues(
        alpha: bright ? 0.15 : 0.035 + 0.075 * rnd.nextDouble(),
      );
      canvas.drawCircle(
        Offset(x, y),
        bright ? 1.6 : rnd.nextDouble() * 1.25 + 0.3,
        starPaint,
      );
    }

    _grain(canvas, size);

    final vignette = Paint()
      ..shader = ui.Gradient.radial(
        Offset(w * 0.5, h * 0.48),
        span * 0.78,
        [
          Colors.transparent,
          Colors.black.withValues(alpha: p.isLight ? 0.10 : 0.56),
        ],
        [0.55, 1],
      );
    canvas.drawRect(rect, vignette);
  }

  @override
  bool shouldRepaint(covariant _AuroraPainter old) =>
      old.p.id != p.id ||
      old.p.matte != p.matte ||
      old.p.accent != p.accent ||
      old.p.night != p.night;
}

/// The S.S monogram: a small glass capsule whose lettering carries a slow
/// sweep of the current theme's colours. Placed wherever the app signs itself.
class SoraSignature extends StatefulWidget {
  final SoraPalette palette;
  final double height;
  const SoraSignature({super.key, required this.palette, this.height = 16});

  @override
  State<SoraSignature> createState() => _SoraSignatureState();
}

class _SoraSignatureState extends State<SoraSignature> {
  Timer? _timer;
  double _t = 0;
  bool _reduced = false;

  @override
  void initState() {
    super.initState();
    SoraMotion.paused.addListener(_syncMotion);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = MediaQuery.disableAnimationsOf(context);
    _syncMotion();
  }

  void _syncMotion() {
    if (!mounted) return;
    final shouldRun =
        !_reduced &&
        Platform.environment['SORA_STILL'] != '1' &&
        !SoraMotion.paused.value;
    if (shouldRun) {
      _timer ??= Timer.periodic(const Duration(milliseconds: 120), (_) {
        if (mounted) setState(() => _t = (_t + 0.12 / 9) % 1.0);
      });
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    SoraMotion.paused.removeListener(_syncMotion);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final t = _reduced ? 0.3 : _t;
    final cosmic = Color.lerp(p.accent, const Color(0xFF7C6BFF), 0.5)!;
    return RepaintBoundary(
      child: Container(
        height: widget.height,
        padding: EdgeInsets.symmetric(horizontal: widget.height * 0.42),
        decoration: BoxDecoration(
          color: p.isLight
              ? Colors.black.withValues(alpha: 0.045)
              : Colors.white.withValues(alpha: 0.055),
          borderRadius: BorderRadius.circular(widget.height / 2),
          border: Border.all(color: p.hairline),
        ),
        child: Center(
          widthFactor: 1,
          child: ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (bounds) => LinearGradient(
              begin: Alignment(-1.5 + 3 * t, -0.4),
              end: Alignment(-0.5 + 3 * t, 0.4),
              colors: [
                p.accent.withValues(alpha: 0.55),
                p.accent,
                cosmic,
                p.accent2,
                p.accent.withValues(alpha: 0.55),
              ],
              stops: const [0, 0.3, 0.5, 0.72, 1],
            ).createShader(bounds),
            child: Text(
              'S.S',
              style: TextStyle(
                fontSize: widget.height * 0.52,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
                height: 1.1,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A sheet of tinted glass. The aurora behind it is already soft, so the frost
/// is drawn as a translucent gradient rather than a live backdrop blur. Real
/// `BackdropFilter`s were removed: a full-screen UI with dozens of them forced
/// a new blurred texture per panel per frame, which is what made the old build
/// consume gigabytes of memory and fall behind the cursor while dragging.
/// The `blur` field is kept for call-site compatibility; it no longer rasterises.
class GlassPanel extends StatefulWidget {
  final Widget child;
  final double blur;
  final double radius;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final Color? tint;
  final Color? borderColor;
  final bool hoverable;
  final bool selected;
  final VoidCallback? onTap;
  final List<BoxShadow>? shadow;
  final Gradient? gradient;
  final double? width;
  final double? height;
  final AlignmentGeometry? alignment;

  const GlassPanel({
    super.key,
    required this.child,
    this.blur = 26,
    this.radius = 24,
    this.padding = const EdgeInsets.all(20),
    this.margin,
    this.tint,
    this.borderColor,
    this.hoverable = false,
    this.selected = false,
    this.onTap,
    this.shadow,
    this.gradient,
    this.width,
    this.height,
    this.alignment,
  });

  @override
  State<GlassPanel> createState() => _GlassPanelState();
}

class _GlassPanelState extends State<GlassPanel> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final radius = BorderRadius.circular(widget.radius);
    final matte = p.matte;
    final border = widget.selected
        ? p.accent.withValues(alpha: 0.55)
        : widget.borderColor ??
              (matte
                  ? p.hairline
                  : (p.isLight
                        ? p.hairline
                        : Colors.white.withValues(alpha: 0.13)));
    final matteHover = _hovered && (widget.hoverable || widget.onTap != null);
    Widget inner = Container(
      width: widget.width,
      height: widget.height,
      alignment: widget.alignment,
      padding: widget.padding,
      decoration: BoxDecoration(
        borderRadius: radius,
        color: matte
            ? (matteHover
                  ? Color.lerp(p.surface, Colors.white, 0.035)
                  : p.surface)
            : (widget.tint ??
                  (p.isLight
                      ? null
                      : Color.lerp(
                          p.night,
                          Colors.black,
                          0.18,
                        )!.withValues(alpha: 0.46))),
        gradient: matte
            ? null
            : (widget.gradient ??
                  LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: p.isLight
                        ? [
                            Colors.white.withValues(alpha: 0.55),
                            Colors.white.withValues(alpha: 0.26),
                          ]
                        : [
                            Colors.white.withValues(
                              alpha: _hovered ? 0.105 : 0.075,
                            ),
                            Colors.white.withValues(alpha: 0.018),
                            p.accent.withValues(alpha: 0.022),
                          ],
                    stops: p.isLight ? null : const [0, 0.58, 1],
                  )),
        border: Border.all(color: border, width: 1),
        boxShadow: matte
            ? (matteHover
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: p.isLight ? 0.08 : 0.26,
                        ),
                        blurRadius: 22,
                        offset: const Offset(0, 10),
                      ),
                    ]
                  : null)
            : (widget.shadow ??
                  (widget.hoverable && _hovered
                      ? [
                          BoxShadow(
                            color: p.accent.withValues(alpha: 0.12),
                            blurRadius: 30,
                            offset: const Offset(0, 12),
                          ),
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: p.isLight ? 0.08 : 0.28,
                            ),
                            blurRadius: 24,
                            offset: const Offset(0, 10),
                          ),
                        ]
                      : (p.isLight
                            ? null
                            : [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.22),
                                  blurRadius: 34,
                                  offset: const Offset(0, 16),
                                ),
                              ]))),
      ),
      child: widget.child,
    );

    inner = ClipRRect(borderRadius: radius, child: inner);

    if (widget.onTap != null) {
      inner = Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: radius,
          onTap: widget.onTap,
          hoverColor: Colors.transparent,
          highlightColor: Colors.transparent,
          splashColor: Colors.transparent,
          child: inner,
        ),
      );
    }

    if (widget.hoverable || widget.onTap != null) {
      return MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: widget.onTap != null
            ? SystemMouseCursors.click
            : MouseCursor.defer,
        child: AnimatedScale(
          scale: _hovered && widget.hoverable ? 1.006 : 1,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: inner,
        ),
      );
    }
    return inner;
  }
}

class GlassButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool primary;
  final bool danger;
  final bool ghost;
  final bool expand;
  final bool dense;
  final bool loading;
  final Widget? trailing;

  const GlassButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.primary = false,
    this.danger = false,
    this.ghost = false,
    this.expand = false,
    this.dense = false,
    this.loading = false,
    this.trailing,
  });

  @override
  State<GlassButton> createState() => _GlassButtonState();
}

class _GlassButtonState extends State<GlassButton> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final enabled = widget.onPressed != null && !widget.loading;
    final onAccent = p.accent.computeLuminance() > 0.47
        ? const Color(0xFF07120F)
        : Colors.white;
    final Color fg = widget.primary
        ? onAccent
        : widget.danger
        ? p.danger
        : p.text;
    final base = BoxDecoration(
      borderRadius: BorderRadius.circular(widget.dense ? 11 : 14),
      color: widget.primary
          ? (p.matte ? p.accent : null)
          : widget.danger
          ? p.danger.withValues(alpha: _hover ? 0.16 : 0.10)
          : widget.ghost
          ? Colors.transparent
          : p.raised,
      gradient: widget.primary && !p.matte ? p.accentGradient : null,
      border: Border.all(
        color: widget.primary
            ? Colors.white.withValues(alpha: p.matte ? 0.06 : 0.16)
            : widget.danger
            ? p.danger.withValues(alpha: 0.35)
            : p.hairline,
      ),
      boxShadow: widget.primary && !p.matte
          ? [
              BoxShadow(
                color: p.accent.withValues(
                  alpha: enabled ? (_hover ? 0.42 : 0.30) : 0.12,
                ),
                blurRadius: _hover ? 28 : 18,
                spreadRadius: 0,
                offset: const Offset(0, 8),
              ),
            ]
          : null,
    );
    final child = Row(
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.loading)
          SizedBox(
            width: 15,
            height: 15,
            child: CircularProgressIndicator(strokeWidth: 1.8, color: fg),
          )
        else if (widget.icon != null)
          Icon(widget.icon, size: widget.dense ? 16 : 18, color: fg),
        if (widget.loading || widget.icon != null) const SizedBox(width: 9),
        Text(
          widget.label,
          style: TextStyle(
            color: fg,
            fontWeight: FontWeight.w600,
            fontSize: widget.dense ? 12.5 : 13.5,
            letterSpacing: -0.1,
          ),
        ),
        if (widget.trailing != null) ...[
          const SizedBox(width: 10),
          widget.trailing!,
        ],
      ],
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: () => setState(() => _down = false),
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTap: enabled ? widget.onPressed : null,
        child: AnimatedScale(
          scale: _down ? 0.972 : 1,
          duration: const Duration(milliseconds: 90),
          child: AnimatedOpacity(
            opacity: enabled ? 1 : 0.45,
            duration: const Duration(milliseconds: 150),
            child: Container(
              height: widget.dense ? 38 : 46,
              padding: EdgeInsets.symmetric(horizontal: widget.dense ? 14 : 19),
              decoration: base,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool selected;
  final double size;

  const GlassIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.selected = false,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget button = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.34),
        color: selected ? p.accent.withValues(alpha: 0.16) : p.raised,
        border: Border.all(
          color: selected ? p.accent.withValues(alpha: 0.45) : p.hairline,
        ),
      ),
      child: Icon(
        icon,
        size: size * 0.45,
        color: selected ? p.accent : p.muted,
      ),
    );
    if (onPressed != null) {
      button = GestureDetector(
        onTap: onPressed,
        child: MouseRegion(cursor: SystemMouseCursors.click, child: button),
      );
    }
    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: button);
    }
    return button;
  }
}

class SoraField extends StatefulWidget {
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? label;
  final String? hint;
  final IconData? icon;
  final Widget? suffix;
  final bool obscure;
  final bool autofocus;
  final bool enabled;
  final int maxLines;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? formatters;
  final String? error;
  final bool dense;
  final double? width;
  final Widget? prefix;
  final TextAlign textAlign;

  const SoraField({
    super.key,
    this.controller,
    this.focusNode,
    this.label,
    this.hint,
    this.icon,
    this.suffix,
    this.obscure = false,
    this.autofocus = false,
    this.enabled = true,
    this.maxLines = 1,
    this.keyboardType,
    this.onChanged,
    this.onSubmitted,
    this.textCapitalization = TextCapitalization.none,
    this.formatters,
    this.error,
    this.dense = false,
    this.width,
    this.prefix,
    this.textAlign = TextAlign.start,
  });

  @override
  State<SoraField> createState() => _SoraFieldState();
}

class _SoraFieldState extends State<SoraField> {
  late bool _hidden = widget.obscure;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final field = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: widget.width,
      decoration: BoxDecoration(
        color: p.raised,
        borderRadius: BorderRadius.circular(widget.dense ? 12 : 14),
        border: Border.all(
          color: widget.error != null
              ? p.danger.withValues(alpha: 0.7)
              : _focus
              ? p.accent.withValues(alpha: 0.7)
              : p.hairline,
          width: _focus ? 1.3 : 1,
        ),
        boxShadow: _focus && !p.matte
            ? [
                BoxShadow(
                  color: p.accent.withValues(alpha: 0.12),
                  blurRadius: 20,
                  spreadRadius: -4,
                ),
              ]
            : null,
      ),
      child: TextField(
        controller: widget.controller,
        focusNode: widget.focusNode,
        obscureText: _hidden,
        autofocus: widget.autofocus,
        enabled: widget.enabled,
        maxLines: widget.obscure ? 1 : widget.maxLines,
        keyboardType: widget.keyboardType,
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
        textCapitalization: widget.textCapitalization,
        inputFormatters: widget.formatters,
        textAlign: widget.textAlign,
        cursorColor: p.accent,
        cursorWidth: 1.6,
        style: TextStyle(
          color: p.text,
          fontSize: widget.dense ? 13 : 14,
          height: 1.35,
        ),
        onTap: () => setState(() => _focus = true),
        onTapOutside: (_) {
          FocusScope.of(context).unfocus();
          setState(() => _focus = false);
        },
        decoration: InputDecoration(
          isDense: true,
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          suffixIconConstraints: const BoxConstraints(
            minWidth: 0,
            minHeight: 0,
          ),
          contentPadding: EdgeInsets.symmetric(
            horizontal: widget.icon != null ? 0 : (widget.dense ? 13 : 15),
            vertical: widget.dense ? 12 : 14,
          ),
          hintText: widget.hint,
          hintStyle: TextStyle(
            color: p.faint,
            fontSize: widget.dense ? 12.5 : 13.5,
          ),
          prefixIcon: widget.icon == null
              ? null
              : Icon(
                  widget.icon,
                  size: widget.dense ? 16 : 18,
                  color: _focus ? p.accent : p.muted,
                ),
          suffixIcon: widget.obscure
              ? IconButton(
                  icon: Icon(
                    _hidden
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_rounded,
                    size: 18,
                    color: p.muted,
                  ),
                  onPressed: () => setState(() => _hidden = !_hidden),
                )
              : widget.suffix,
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null) ...[
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 7),
            child: Text(widget.label!, style: overlineStyle(p)),
          ),
        ],
        Row(
          children: [
            if (widget.prefix != null) ...[
              widget.prefix!,
              const SizedBox(width: 10),
            ],
            Expanded(child: field),
          ],
        ),
        if (widget.error != null)
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 5),
            child: Text(
              widget.error!,
              style: TextStyle(color: p.danger, fontSize: 11.5),
            ),
          ),
      ],
    );
  }
}

class SoraSegmented<T> extends StatelessWidget {
  final List<T> values;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onChanged;
  final bool dense;

  const SoraSegmented({
    super.key,
    required this.values,
    required this.selected,
    required this.label,
    required this.onChanged,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final index = values.indexOf(selected);
    final height = dense ? 36.0 : 42.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final segment = constraints.maxWidth / values.length;
        return Container(
          height: height,
          decoration: BoxDecoration(
            color: p.raised,
            borderRadius: BorderRadius.circular(height / 2),
            border: Border.all(color: p.hairline),
          ),
          child: Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                left: index * segment + 3,
                top: 3,
                bottom: 3,
                width: segment - 6,
                child: Container(
                  decoration: BoxDecoration(
                    color: p.matte ? p.accent : null,
                    gradient: p.matte ? null : p.accentGradient,
                    borderRadius: BorderRadius.circular(height / 2),
                    boxShadow: p.matte
                        ? null
                        : [
                            BoxShadow(
                              color: p.accent.withValues(alpha: 0.25),
                              blurRadius: 14,
                              offset: const Offset(0, 4),
                            ),
                          ],
                  ),
                ),
              ),
              Row(
                children: values.map((v) {
                  final active = v == selected;
                  final onAccent = p.accent.computeLuminance() > 0.47
                      ? const Color(0xFF08120F)
                      : Colors.white;
                  return Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onChanged(v),
                      child: Center(
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 200),
                          style: TextStyle(
                            color: active ? onAccent : p.muted,
                            fontWeight: FontWeight.w600,
                            fontSize: dense ? 12 : 13,
                          ),
                          child: Text(label(v)),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        );
      },
    );
  }
}

class FilterPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final int? count;

  const FilterPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.count,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final onAccent = p.accent.computeLuminance() > 0.47
        ? const Color(0xFF08120F)
        : Colors.white;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: selected ? (p.matte ? p.accent : null) : p.raised,
            gradient: selected && !p.matte ? p.accentGradient : null,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
              color: selected
                  ? Colors.white.withValues(alpha: p.matte ? 0.06 : 0.14)
                  : p.hairline,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: selected ? onAccent : p.muted),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: selected ? onAccent : p.muted,
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 6),
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: selected ? onAccent.withValues(alpha: 0.7) : p.faint,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  final String label;
  final Color? color;
  final IconData? icon;
  final bool dot;

  const StatusPill({
    super.key,
    required this.label,
    this.color,
    this.icon,
    this.dot = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = color ?? p.accent;
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.withValues(alpha: 0.26)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(color: c, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ],
          if (icon != null) ...[
            Icon(icon, size: 12, color: c),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: c,
            ),
          ),
        ],
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionLabel(this.text, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      children: [
        Text(text.toUpperCase(), style: overlineStyle(p)),
        const Spacer(),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// A small, static keepsake orb for empty panes. It carries the active theme's
/// colours in layers — glow, orbit rings, a lit sphere and a specular highlight
/// — without any running animation, so it costs nothing at rest.
class SoraOrb extends StatelessWidget {
  final SoraPalette palette;
  final double size;
  final IconData icon;

  const SoraOrb({
    super.key,
    required this.palette,
    this.size = 108,
    this.icon = Icons.shopping_bag_outlined,
  });

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final cosmic = Color.lerp(p.accent, const Color(0xFF7C6BFF), 0.46)!;
    final sphere = size * 0.62;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: size * 0.96,
            height: size * 0.96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: p.matte
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: p.isLight ? 0.06 : 0.22,
                        ),
                        blurRadius: size * 0.24,
                        offset: Offset(0, size * 0.08),
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: p.accent.withValues(alpha: 0.16),
                        blurRadius: size * 0.55,
                        spreadRadius: -size * 0.08,
                      ),
                    ],
            ),
          ),
          Transform.rotate(
            angle: -0.55,
            child: Container(
              width: size * 0.94,
              height: size * 0.94,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: p.accent.withValues(alpha: 0.20),
                  width: 1,
                ),
              ),
            ),
          ),
          Transform.rotate(
            angle: 0.62,
            child: Container(
              width: size * 0.78,
              height: size * 0.78,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: p.accent2.withValues(alpha: 0.14),
                  width: 1,
                ),
              ),
            ),
          ),
          Container(
            width: sphere,
            height: sphere,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                center: const Alignment(-0.36, -0.42),
                radius: 1.15,
                colors: p.matte
                    ? [
                        Color.lerp(p.surfaceRaised, p.accent, 0.16)!,
                        Color.lerp(p.night, p.accent, 0.10)!,
                        Color.lerp(p.night, Colors.black, 0.24)!,
                      ]
                    : [
                        Colors.white.withValues(alpha: p.isLight ? 0.92 : 0.18),
                        p.accent.withValues(alpha: 0.84),
                        cosmic.withValues(alpha: 0.94),
                      ],
                stops: const [0, 0.52, 1],
              ),
              border: Border.all(
                color: p.matte
                    ? p.hairline
                    : Colors.white.withValues(alpha: 0.24),
              ),
              boxShadow: p.matte
                  ? null
                  : [
                      BoxShadow(
                        color: cosmic.withValues(alpha: 0.34),
                        blurRadius: size * 0.24,
                        spreadRadius: size * 0.02,
                      ),
                    ],
            ),
            child: Icon(
              icon,
              size: size * 0.25,
              color: p.matte ? p.accent : Colors.white.withValues(alpha: 0.92),
            ),
          ),
          if (!p.matte)
            Positioned(
              left: size * 0.33,
              top: size * 0.24,
              child: Container(
                width: size * 0.15,
                height: size * 0.075,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.34),
                  borderRadius: BorderRadius.circular(size),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A compact "today" sparkline in the page header. One pass over today's sales;
/// no timers and no animated controllers.
class SoraPulse extends StatelessWidget {
  final List<double> values;
  final String amount;
  final String caption;

  const SoraPulse({
    super.key,
    required this.values,
    required this.amount,
    required this.caption,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: p.matte
            ? p.raised
            : (p.isLight
                  ? Colors.white.withValues(alpha: 0.46)
                  : Colors.white.withValues(alpha: 0.045)),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: p.hairline),
        gradient: p.matte
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [p.accent.withValues(alpha: 0.075), Colors.transparent],
              ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 60,
            height: 26,
            child: CustomPaint(painter: _PulsePainter(values, p)),
          ),
          const SizedBox(width: 10),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                caption.toUpperCase(),
                style: overlineStyle(p, color: p.faint),
              ),
              const SizedBox(height: 2),
              Text(
                amount,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                  color: p.text,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  height: 1.1,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PulsePainter extends CustomPainter {
  final List<double> values;
  final SoraPalette p;
  _PulsePainter(this.values, this.p);

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty || size.width <= 0 || size.height <= 0) return;
    var maxV = 0.0;
    for (final value in values) {
      if (value > maxV) maxV = value;
    }
    final n = values.length;
    final step = n <= 1 ? 0.0 : size.width / (n - 1);
    final points = <Offset>[];
    for (var i = 0; i < n; i++) {
      final v = maxV <= 0 ? 0.5 : values[i] / maxV;
      points.add(Offset(i * step, size.height - 2 - v * (size.height - 4)));
    }
    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final prev = points[i - 1];
      final cur = points[i];
      final mid = Offset((prev.dx + cur.dx) / 2, (prev.dy + cur.dy) / 2);
      line.quadraticBezierTo(prev.dx, prev.dy, mid.dx, mid.dy);
    }
    line.lineTo(points.last.dx, points.last.dy);
    final area = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = ui.Gradient.linear(Offset.zero, Offset(0, size.height), [
          p.accent.withValues(alpha: 0.26),
          p.accent.withValues(alpha: 0),
        ]),
    );
    canvas.drawPath(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round
        ..shader = ui.Gradient.linear(Offset.zero, Offset(size.width, 0), [
          p.accent,
          p.accent2,
        ]),
    );
    final last = points.last;
    canvas.drawCircle(
      last,
      3.2,
      Paint()
        ..color = p.accent.withValues(alpha: 0.24)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 4),
    );
    canvas.drawCircle(last, 2.0, Paint()..color = p.accent);
  }

  @override
  bool shouldRepaint(covariant _PulsePainter old) => true;
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  final Widget? art;
  final double iconSize;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message = '',
    this.action,
    this.art,
    this.iconSize = 44,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (art != null)
              art!
            else
              Container(
                width: iconSize * 1.8,
                height: iconSize * 1.8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: p.raised,
                  border: Border.all(color: p.hairline),
                ),
                child: Icon(icon, size: iconSize * 0.72, color: p.faint),
              ),
            const SizedBox(height: 18),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: p.text,
              ),
              textAlign: TextAlign.center,
            ),
            if (message.isNotEmpty) ...[
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Text(
                  message,
                  style: TextStyle(fontSize: 12.5, color: p.muted, height: 1.5),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 18), action!],
          ],
        ),
      ),
    );
  }
}

/// Dialogs sit in a single piece of glass over a dimmed, blurred room.
Future<T?> showSoraDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  double maxWidth = 520,
  bool dismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: dismissible,
    barrierLabel: 'Close',
    barrierColor: Colors.black.withValues(alpha: 0.48),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, animation, secondaryAnimation) {
      return SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxWidth,
              maxHeight: MediaQuery.sizeOf(context).height * 0.86,
            ),
            child: builder(context),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curve = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curve,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.965, end: 1).animate(curve),
          alignment: Alignment.center,
          child: child,
        ),
      );
    },
  );
}

class SoraDialog extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget child;
  final List<Widget> actions;
  final double width;
  final bool showClose;
  final Color? accent;

  const SoraDialog({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    required this.child,
    this.actions = const [],
    this.width = 520,
    this.showClose = true,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final tint = accent ?? p.accent;
    return DefaultTextStyle(
      style: (Theme.of(context).textTheme.bodyMedium ?? const TextStyle())
          .copyWith(
            decoration: TextDecoration.none,
            decorationColor: Colors.transparent,
            color: p.text,
          ),
      child: Material(
        color: Colors.transparent,
        child: GlassPanel(
          blur: 0,
          radius: 26,
          padding: EdgeInsets.zero,
          width: width,
          tint: p.isLight ? const Color(0xF2F7F8FB) : const Color(0xF20C1119),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: p.isLight
                ? [
                    Colors.white.withValues(alpha: 0.95),
                    Colors.white.withValues(alpha: 0.82),
                  ]
                : [
                    Color(0xFF1A2130).withValues(alpha: 0.96),
                    Color(0xFF0A0E15).withValues(alpha: 0.97),
                  ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(26, 24, 20, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (icon != null) ...[
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: tint.withValues(alpha: 0.13),
                          borderRadius: BorderRadius.circular(13),
                          border: Border.all(
                            color: tint.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Icon(icon, size: 20, color: tint),
                      ),
                      const SizedBox(width: 14),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.4,
                              color: p.text,
                            ),
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              subtitle!,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: p.muted,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (showClose)
                      IconButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: Icon(
                          Icons.close_rounded,
                          size: 19,
                          color: p.muted,
                        ),
                        splashRadius: 20,
                      ),
                  ],
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  physics: const ClampingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(26, 20, 26, 24),
                  children: [child],
                ),
              ),
              if (actions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(26, 0, 26, 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      for (var i = 0; i < actions.length; i++) ...[
                        if (i > 0) const SizedBox(width: 10),
                        Flexible(child: actions[i]),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

void showToast(
  BuildContext context,
  String message, {
  bool error = false,
  IconData? icon,
}) {
  final overlay = Overlay.of(context, rootOverlay: true);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => _Toast(
      message: message,
      error: error,
      icon: icon,
      onDone: () => entry.remove(),
    ),
  );
  overlay.insert(entry);
}

class _Toast extends StatefulWidget {
  final String message;
  final bool error;
  final IconData? icon;
  final VoidCallback onDone;
  const _Toast({
    required this.message,
    required this.error,
    this.icon,
    required this.onDone,
  });

  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  Timer? _timer;
  bool _out = false;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    )..forward();
    _timer = Timer(const Duration(milliseconds: 3200), () async {
      if (!mounted) return;
      setState(() => _out = true);
      await _c.reverse();
      widget.onDone();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = widget.error ? p.danger : p.success;
    final size = MediaQuery.sizeOf(context);
    return Positioned(
      right: 26,
      bottom: 26,
      child: SafeArea(
        child: FadeTransition(
          opacity: _c,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.14),
              end: Offset.zero,
            ).animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic)),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: math.min(420, size.width * 0.7),
              ),
              child: GlassPanel(
                blur: 22,
                radius: 16,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 13,
                ),
                tint: p.isLight
                    ? const Color(0xF5FFFFFF)
                    : const Color(0xF20F141D),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.16),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        widget.icon ??
                            (widget.error
                                ? Icons.error_outline_rounded
                                : Icons.check_rounded),
                        size: 15,
                        color: color,
                      ),
                    ),
                    const SizedBox(width: 11),
                    Flexible(
                      child: Text(
                        widget.message,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: p.text,
                          height: 1.35,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SoraSelectOption<T> {
  final T value;
  final String label;
  final IconData? icon;
  const SoraSelectOption(this.value, this.label, {this.icon});
}

class SoraSelect<T> extends StatelessWidget {
  final String? label;
  final T value;
  final List<SoraSelectOption<T>> options;
  final ValueChanged<T> onChanged;
  final IconData? icon;
  final double? width;
  final bool dense;

  const SoraSelect({
    super.key,
    this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.icon,
    this.width,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    SoraSelectOption<T> selected = options.first;
    for (final o in options) {
      if (o.value == value) selected = o;
    }
    final menu = MenuAnchor(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(
          p.matte
              ? p.surfaceRaised
              : (p.isLight ? const Color(0xFFF8F9FC) : const Color(0xFF161C27)),
        ),
        elevation: WidgetStatePropertyAll(20),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: p.hairline),
          ),
        ),
        padding: WidgetStatePropertyAll(const EdgeInsets.all(6)),
      ),
      menuChildren: options
          .map(
            (o) => MenuItemButton(
              style: MenuItemButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9),
                ),
                foregroundColor: o.value == value ? p.accent : p.text,
              ),
              onPressed: () => onChanged(o.value),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (o.icon != null) ...[
                    Icon(
                      o.icon,
                      size: 16,
                      color: o.value == value ? p.accent : p.muted,
                    ),
                    const SizedBox(width: 8),
                  ],
                  Text(o.label, style: const TextStyle(fontSize: 12.5)),
                  if (o.value == value) ...[
                    const SizedBox(width: 10),
                    Icon(Icons.check_rounded, size: 15, color: p.accent),
                  ],
                ],
              ),
            ),
          )
          .toList(),
      builder: (context, controller, child) {
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () =>
                controller.isOpen ? controller.close() : controller.open(),
            child: Container(
              width: width,
              height: dense ? 38 : 46,
              padding: EdgeInsets.symmetric(horizontal: dense ? 12 : 14),
              decoration: BoxDecoration(
                color: p.raised,
                borderRadius: BorderRadius.circular(dense ? 12 : 14),
                border: Border.all(color: p.hairline),
              ),
              child: Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 16, color: p.muted),
                    const SizedBox(width: 8),
                  ],
                  if (selected.icon != null) ...[
                    Icon(selected.icon, size: 16, color: p.accent),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      selected.label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: dense ? 12.5 : 13.5,
                        color: p.text,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: p.muted,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (label == null) return menu;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 7),
          child: Text(label!, style: overlineStyle(p)),
        ),
        menu,
      ],
    );
  }
}

class SwitchRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const SwitchRow({
    super.key,
    required this.title,
    this.subtitle = '',
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: p.text,
                ),
              ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 12, color: p.muted, height: 1.4),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 16),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}

class AnimatedMoney extends StatelessWidget {
  final double value;
  final String symbol;
  final TextStyle style;
  final Duration duration;
  const AnimatedMoney({
    super.key,
    required this.value,
    required this.symbol,
    required this.style,
    this.duration = const Duration(milliseconds: 700),
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : duration,
      curve: Curves.easeOutCubic,
      builder: (context, v, child) {
        final body = v
            .abs()
            .toStringAsFixed(2)
            .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
        return Text('${v < 0 ? '-' : ''}$symbol$body', style: style);
      },
    );
  }
}

class LoadingBar extends StatelessWidget {
  const LoadingBar({super.key});
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SizedBox(
      height: 2,
      child: LinearProgressIndicator(
        backgroundColor: p.raised,
        color: p.accent,
        minHeight: 2,
      ),
    );
  }
}
