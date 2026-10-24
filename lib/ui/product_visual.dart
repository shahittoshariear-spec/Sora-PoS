import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'theme.dart';

/// A generated visual identity for a product.
///
/// Shops rarely have a photograph for every line, so the till grows one: a
/// category-derived colour, a soft specimen wash and the product's initial.
/// The same mark is used at tile size and at sheet size, which lets the two
/// share a hero transition. Everything is painted; no asset or image is
/// loaded, and the mark never animates on its own.
class ProductMark extends StatelessWidget {
  final String name;
  final String category;
  final double size;

  const ProductMark({
    super.key,
    required this.name,
    required this.category,
    this.size = 46,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final seed = category.trim().isEmpty ? name : category;
    final tint = productTint(p, seed);
    final initial = productInitial(name);
    final icon = iconForCategory(category);
    final ink = p.isLight
        ? Color.lerp(tint, const Color(0xFF0B0E14), 0.52)!
        : Color.lerp(tint, Colors.white, 0.62)!;
    final radius = size * 0.28;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(
            painter: _MarkPainter(
              palette: p,
              tint: tint,
              radius: radius,
              seed: _stableHash(seed),
            ),
          ),
          Center(
            child: Padding(
              padding: EdgeInsets.only(bottom: size >= 72 ? size * 0.04 : 0),
              child: Text(
                initial,
                style: TextStyle(
                  fontSize: size * (initial.length > 1 ? 0.30 : 0.44),
                  fontWeight: FontWeight.w700,
                  letterSpacing: -size * 0.025,
                  height: 1,
                  color: ink,
                ),
              ),
            ),
          ),
          if (size >= 72)
            Positioned(
              right: size * 0.09,
              bottom: size * 0.09,
              child: Container(
                width: size * 0.24,
                height: size * 0.24,
                decoration: BoxDecoration(
                  color: p.matte
                      ? p.surface.withValues(alpha: 0.88)
                      : Colors.black.withValues(alpha: p.isLight ? 0.05 : 0.22),
                  borderRadius: BorderRadius.circular(size * 0.075),
                  border: Border.all(
                    color: tint.withValues(alpha: p.matte ? 0.30 : 0.42),
                  ),
                ),
                child: Icon(icon, size: size * 0.14, color: ink),
              ),
            ),
        ],
      ),
    );
  }
}

/// A stable hue for a category or product name, pulled towards the active
/// theme so the grid still belongs to the rest of the app.
Color productTint(SoraPalette p, String seed) {
  final hue = (_stableHash(seed) % 360).toDouble();
  final raw = HSLColor.fromAHSL(
    1,
    hue,
    p.matte ? 0.32 : 0.54,
    p.isLight ? 0.56 : 0.52,
  ).toColor();
  final themed = Color.lerp(raw, p.accent, 0.24)!;
  return p.matte ? Color.lerp(themed, p.surface, 0.48)! : themed;
}

/// The two-character initials used when a name has several words, otherwise
/// the first letter. Kept short so the mark stays readable at 44 px.
String productInitial(String name) {
  final words = name
      .trim()
      .split(RegExp(r'[\s\-_/]+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return '?';
  if (words.length == 1) {
    return words.first.substring(0, 1).toUpperCase();
  }
  return '${words.first.substring(0, 1)}${words[1].substring(0, 1)}'
      .toUpperCase();
}

/// A category glyph for the larger sheet-sized mark. Falls back to a parcel,
/// which is honest for an unclassified line.
IconData iconForCategory(String category) {
  final c = category.toLowerCase();
  bool has(List<String> keys) => keys.any(c.contains);

  if (has(const [
    'drink',
    'beverage',
    'coffee',
    'tea',
    'juice',
    'soda',
    'water',
    'beer',
    'wine',
    'alcohol',
    'dairy',
  ])) {
    return Icons.local_cafe_rounded;
  }
  if (has(const [
    'snack',
    'sweet',
    'candy',
    'choc',
    'bakery',
    'cake',
    'bread',
  ])) {
    return Icons.cookie_outlined;
  }
  if (has(const [
    'food',
    'meal',
    'kitchen',
    'meat',
    'fruit',
    'veg',
    'grocery',
    'produce',
  ])) {
    return Icons.restaurant_rounded;
  }
  if (has(const ['clean', 'house', 'home', 'laundry', 'care'])) {
    return Icons.cleaning_services_outlined;
  }
  if (has(const ['electronic', 'tech', 'phone', 'cable', 'battery'])) {
    return Icons.devices_other_rounded;
  }
  if (has(const ['station', 'office', 'paper', 'print', 'book'])) {
    return Icons.edit_note_rounded;
  }
  if (has(const ['cloth', 'shirt', 'wear', 'fashion'])) {
    return Icons.checkroom_rounded;
  }
  if (has(const ['toy', 'game', 'kid'])) {
    return Icons.toys_outlined;
  }
  if (has(const ['health', 'pharm', 'med', 'first aid'])) {
    return Icons.healing_rounded;
  }
  return Icons.inventory_2_outlined;
}

int _stableHash(String value) {
  var hash = 0x811C9DC5;
  for (final unit in value.toLowerCase().codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0x7FFFFFFF;
  }
  return hash;
}

class _MarkPainter extends CustomPainter {
  final SoraPalette palette;
  final Color tint;
  final double radius;
  final int seed;

  _MarkPainter({
    required this.palette,
    required this.tint,
    required this.radius,
    required this.seed,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    final matte = palette.matte;
    final base = matte
        ? Color.lerp(palette.surfaceRaised, tint, 0.14)!
        : Color.lerp(palette.glassTint, tint, 0.20)!;

    canvas.save();
    canvas.clipRRect(rrect);
    canvas.drawRect(rect, Paint()..color = base);

    // A soft specimen wash from the top-left, then a darker foot so the mark
    // has weight without a shadow.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(size.width * 0.18, size.height * 0.06),
          size.width * 1.15,
          [
            tint.withValues(alpha: matte ? 0.20 : 0.42),
            tint.withValues(alpha: 0),
          ],
          const [0, 1],
        ),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, size.height * 0.30),
          Offset(0, size.height),
          [
            Colors.transparent,
            Colors.black.withValues(alpha: matte ? 0.10 : 0.26),
          ],
        ),
    );

    // One diagonal light pass. Matte keeps only a trace of it.
    final streak = Path()
      ..moveTo(-size.width * 0.22, size.height * 0.86)
      ..lineTo(size.width * 0.48, -size.height * 0.08)
      ..lineTo(size.width * 0.72, -size.height * 0.08)
      ..lineTo(size.width * 0.02, size.height * 0.96)
      ..close();
    canvas.drawPath(
      streak,
      Paint()..color = Colors.white.withValues(alpha: matte ? 0.012 : 0.055),
    );

    // A few fixed flecks make the surface feel printed rather than flat.
    final rnd = math.Random(seed);
    final fleck = Paint();
    for (var i = 0; i < 5; i++) {
      fleck.color = Colors.white.withValues(
        alpha: (matte ? 0.018 : 0.045) + rnd.nextDouble() * 0.03,
      );
      canvas.drawCircle(
        Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height),
        (0.35 + rnd.nextDouble() * 0.7) * (size.width / 46),
        fleck,
      );
    }
    canvas.restore();

    // The rim is what makes the mark sit in the glass card.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect.deflate(size.width * 0.008),
        Radius.circular(radius),
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = tint.withValues(alpha: matte ? 0.26 : 0.42),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * 0.12,
          size.width * 0.02,
          size.width * 0.76,
          size.height * 0.16,
        ),
        Radius.circular(radius),
      ),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, 0),
          Offset(0, size.height * 0.18),
          [
            Colors.white.withValues(alpha: matte ? 0.03 : 0.14),
            Colors.transparent,
          ],
        ),
    );
  }

  @override
  bool shouldRepaint(covariant _MarkPainter old) =>
      old.palette.id != palette.id ||
      old.palette.matte != palette.matte ||
      old.palette.accent != palette.accent ||
      old.tint != tint ||
      old.radius != radius ||
      old.seed != seed;
}
