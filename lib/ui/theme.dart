import 'dart:math';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../models.dart';

/// The nine marks from the shop's icon pack, each with a night and an accent.
class SoraPalette {
  final String id;
  final String name;
  final Color night;
  final Color accent;
  final Color accent2;
  final String iconAsset;
  final String windowIcon; // which .ico the taskbar should wear
  final bool custom;
  final double iconHueShift; // degrees, for the three custom slots
  final bool matte; // opaque flat surfaces instead of aurora glass

  const SoraPalette({
    required this.id,
    required this.name,
    required this.night,
    required this.accent,
    required this.accent2,
    required this.iconAsset,
    required this.windowIcon,
    this.custom = false,
    this.iconHueShift = 0,
    this.matte = false,
  });

  static const named = <SoraPalette>[
    SoraPalette(
      id: 'teal',
      name: 'Teal Dust',
      night: Color(0xFF04100F),
      accent: Color(0xFF2DD4BF),
      accent2: Color(0xFF7BF1E4),
      iconAsset: 'assets/icons/icon_teal_512.png',
      windowIcon: 'teal',
    ),
    SoraPalette(
      id: 'blue',
      name: 'Aurora Blue',
      night: Color(0xFF050B18),
      accent: Color(0xFF5B8CFF),
      accent2: Color(0xFF9CBCFF),
      iconAsset: 'assets/icons/icon_blue_512.png',
      windowIcon: 'blue',
    ),
    SoraPalette(
      id: 'violet',
      name: 'Amethyst',
      night: Color(0xFF0B0716),
      accent: Color(0xFFA78BFA),
      accent2: Color(0xFFD8C7FF),
      iconAsset: 'assets/icons/icon_violet_512.png',
      windowIcon: 'violet',
    ),
    SoraPalette(
      id: 'magenta',
      name: 'Rose Quartz',
      night: Color(0xFF160711),
      accent: Color(0xFFF472B6),
      accent2: Color(0xFFFFB7D9),
      iconAsset: 'assets/icons/icon_magenta_512.png',
      windowIcon: 'magenta',
    ),
    SoraPalette(
      id: 'red',
      name: 'Ember',
      night: Color(0xFF160707),
      accent: Color(0xFFFF6B6B),
      accent2: Color(0xFFFFB6A8),
      iconAsset: 'assets/icons/icon_red_512.png',
      windowIcon: 'red',
    ),
    SoraPalette(
      id: 'orange',
      name: 'Sunset',
      night: Color(0xFF160D05),
      accent: Color(0xFFFF9F5A),
      accent2: Color(0xFFFFD2A6),
      iconAsset: 'assets/icons/icon_orange_512.png',
      windowIcon: 'orange',
    ),
    SoraPalette(
      id: 'amber',
      name: 'Honey',
      night: Color(0xFF141003),
      accent: Color(0xFFFBBF24),
      accent2: Color(0xFFFFE397),
      iconAsset: 'assets/icons/icon_amber_512.png',
      windowIcon: 'amber',
    ),
    SoraPalette(
      id: 'green',
      name: 'Meadow',
      night: Color(0xFF04120A),
      accent: Color(0xFF4ADE80),
      accent2: Color(0xFFA8F3C3),
      iconAsset: 'assets/icons/icon_green_512.png',
      windowIcon: 'green',
    ),
    SoraPalette(
      id: 'graphite',
      name: 'Graphite',
      night: Color(0xFF090B10),
      accent: Color(0xFFC3CAD6),
      accent2: Color(0xFFE8EDF5),
      iconAsset: 'assets/icons/icon_graphite_512.png',
      windowIcon: 'graphite',
    ),
  ];

  static SoraPalette byId(String id) {
    for (final p in named) {
      if (p.id == id) return p;
    }
    return named.first;
  }

  static SoraPalette fromAppearance(Appearance a) {
    final matte = a.surfaceStyle == 'matte';
    if (a.themeId.startsWith('custom')) {
      final index = int.tryParse(a.themeId.substring(6)) ?? 0;
      final slot = a.customs[index.clamp(0, 2)];
      final accent = Color(slot.accent);
      final night = Color(slot.night);
      final base = named.first;
      final shift = _hueOf(accent) - _hueOf(base.accent);
      return SoraPalette(
        id: a.themeId,
        name: slot.name,
        night: night,
        accent: accent,
        accent2: _mix(accent, Colors.white, 0.42),
        iconAsset: base.iconAsset,
        windowIcon: _nearestNamed(accent).windowIcon,
        custom: true,
        iconHueShift: shift,
        matte: matte,
      );
    }
    final base = byId(a.themeId);
    return matte ? base.withMatte(true) : base;
  }

  SoraPalette withMatte(bool value) => SoraPalette(
    id: id,
    name: name,
    night: night,
    accent: accent,
    accent2: accent2,
    iconAsset: iconAsset,
    windowIcon: windowIcon,
    custom: custom,
    iconHueShift: iconHueShift,
    matte: value,
  );

  static double _hueOf(Color c) {
    final h = HSLColor.fromColor(c).hue;
    return h;
  }

  static SoraPalette _nearestNamed(Color accent) {
    final h = _hueOf(accent);
    SoraPalette best = named.first;
    double bestDistance = 999;
    for (final p in named) {
      var d = (_hueOf(p.accent) - h).abs();
      if (d > 180) d = 360 - d;
      if (d < bestDistance) {
        bestDistance = d;
        best = p;
      }
    }
    return best;
  }

  static Color _mix(Color a, Color b, double t) => Color.lerp(a, b, t) ?? a;

  bool get isLight => night.computeLuminance() > 0.42;

  Color get text => isLight ? const Color(0xFF12151B) : const Color(0xFFF7F8FB);
  Color get muted =>
      isLight ? const Color(0x9912151B) : const Color(0xC7E4E8F2);
  Color get faint =>
      isLight ? const Color(0x6612151B) : const Color(0x8ADCE2EE);
  Color get hairline => matte
      ? (isLight
            ? _mix(surface, Colors.black, 0.10)
            : _mix(surface, Colors.white, 0.095))
      : (isLight ? const Color(0x1F000000) : const Color(0x1FFFFFFF));

  /// The flat, opaque panel colour used in matte mode.
  Color get surface => isLight
      ? const Color(0xFFF4F5F8)
      : _mix(_mix(night, Colors.black, 0.32), Colors.white, 0.028);

  /// A slightly lifted flat surface for fields, buttons and raised cards.
  Color get surfaceRaised => isLight
      ? const Color(0xFFFFFFFF)
      : _mix(_mix(night, Colors.black, 0.20), Colors.white, 0.058);

  Color get glassTint => matte
      ? surface
      : (isLight ? const Color(0x59FFFFFF) : const Color(0x0DFFFFFF));
  Color get raised => matte
      ? surfaceRaised
      : (isLight ? const Color(0x38FFFFFF) : const Color(0x14FFFFFF));
  Color get success =>
      isLight ? const Color(0xFF16794A) : const Color(0xFF5BE8A3);
  Color get danger =>
      isLight ? const Color(0xFFB42332) : const Color(0xFFFF7D8A);
  Color get warning =>
      isLight ? const Color(0xFF8A5A00) : const Color(0xFFFFC46B);
  Color get info => accent;

  LinearGradient get accentGradient => LinearGradient(
    colors: [accent, _mix(accent, accent2, 0.55)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  LinearGradient get nightGradient => matte
      ? LinearGradient(
          colors: [
            _mix(night, Colors.white, 0.014),
            night,
            _mix(night, Colors.black, 0.44),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        )
      : LinearGradient(
          colors: [
            _mix(night, accent, 0.045),
            night,
            _mix(night, Colors.black, 0.52),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );

  Color get captionColor => _mix(night, accent, 0.045);
}

class SoraThemeData extends ThemeExtension<SoraThemeData> {
  final SoraPalette palette;
  const SoraThemeData(this.palette);

  @override
  SoraThemeData copyWith({SoraPalette? palette}) =>
      SoraThemeData(palette ?? this.palette);

  @override
  SoraThemeData lerp(covariant SoraThemeData? other, double t) {
    if (other == null) return this;
    return t < 0.5 ? this : other;
  }
}

extension SoraContext on BuildContext {
  SoraPalette get palette =>
      Theme.of(this).extension<SoraThemeData>()?.palette ??
      SoraPalette.named.first;
}

class FontChoice {
  final String family;
  final String label;
  const FontChoice(this.family, this.label);
}

const fontChoices = <FontChoice>[
  FontChoice('Inter', 'Clean'),
  FontChoice('Manrope', 'Soft'),
  FontChoice('Outfit', 'Modern'),
  FontChoice('Space Grotesk', 'Technical'),
  FontChoice('DM Sans', 'Balanced'),
  FontChoice('Plus Jakarta Sans', 'Friendly'),
  FontChoice('Playfair Display', 'Editorial'),
  FontChoice('Lora', 'Classic'),
  FontChoice('JetBrains Mono', 'Mono'),
];

const textSizes = <double>[0.9, 1.0, 1.1, 1.22];
const textSizeLabels = <String>['Compact', 'Standard', 'Large', 'Extra large'];

ThemeData buildSoraTheme(SoraPalette palette, int fontIndex) {
  final font = fontChoices[fontIndex.clamp(0, fontChoices.length - 1)].family;
  final brightness = palette.isLight ? Brightness.light : Brightness.dark;
  final text = palette.text;
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    fontFamily: font,
    scaffoldBackgroundColor: Colors.transparent,
    canvasColor: palette.night,
    splashFactory: NoSplash.splashFactory,
    visualDensity: VisualDensity.standard,
    colorScheme: ColorScheme.fromSeed(
      seedColor: palette.accent,
      brightness: brightness,
      primary: palette.accent,
      secondary: palette.accent2,
      surface: palette.night,
      error: palette.danger,
    ),
  );

  final textTheme = base.textTheme
      .apply(fontFamily: font, bodyColor: text, displayColor: text)
      .copyWith(
        displayLarge: TextStyle(
          fontFamily: font,
          fontSize: 44,
          height: 1.05,
          fontWeight: FontWeight.w700,
          letterSpacing: -1.2,
          color: text,
        ),
        displayMedium: TextStyle(
          fontFamily: font,
          fontSize: 34,
          height: 1.08,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.9,
          color: text,
        ),
        headlineLarge: TextStyle(
          fontFamily: font,
          fontSize: 27,
          height: 1.15,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.6,
          color: text,
        ),
        headlineMedium: TextStyle(
          fontFamily: font,
          fontSize: 22,
          height: 1.2,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.4,
          color: text,
        ),
        titleLarge: TextStyle(
          fontFamily: font,
          fontSize: 18,
          height: 1.25,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.25,
          color: text,
        ),
        titleMedium: TextStyle(
          fontFamily: font,
          fontSize: 15,
          height: 1.3,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
          color: text,
        ),
        bodyLarge: TextStyle(
          fontFamily: font,
          fontSize: 15,
          height: 1.45,
          color: text,
        ),
        bodyMedium: TextStyle(
          fontFamily: font,
          fontSize: 13.5,
          height: 1.45,
          color: text,
        ),
        bodySmall: TextStyle(
          fontFamily: font,
          fontSize: 12,
          height: 1.4,
          color: palette.muted,
        ),
        labelLarge: TextStyle(
          fontFamily: font,
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
          color: text,
        ),
        labelMedium: TextStyle(
          fontFamily: font,
          fontSize: 12,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.1,
          color: palette.muted,
        ),
        labelSmall: TextStyle(
          fontFamily: font,
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
          color: palette.muted,
        ),
      );

  return base.copyWith(
    textTheme: textTheme,
    extensions: [SoraThemeData(palette)],
    dividerColor: palette.hairline,
    dividerTheme: DividerThemeData(
      color: palette.hairline,
      thickness: 1,
      space: 1,
    ),
    iconTheme: IconThemeData(color: palette.muted, size: 20),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: palette.matte
            ? palette.surfaceRaised
            : (palette.isLight
                  ? const Color(0xF2FFFFFF)
                  : const Color(0xF21A1F2B)),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.hairline),
      ),
      textStyle: TextStyle(fontFamily: font, color: text, fontSize: 12),
      waitDuration: const Duration(milliseconds: 450),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: palette.matte
          ? palette.surfaceRaised
          : (palette.isLight
                ? const Color(0xFFF8F9FC)
                : const Color(0xFF141A24)),
      elevation: 18,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: palette.hairline),
      ),
      textStyle: TextStyle(fontFamily: font, color: text, fontSize: 13.5),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: WidgetStateProperty.all(4),
      thumbColor: WidgetStateProperty.all(palette.faint),
      radius: const Radius.circular(3),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: palette.raised,
      hintStyle: TextStyle(
        fontFamily: font,
        color: palette.faint,
        fontSize: 13.5,
      ),
      labelStyle: TextStyle(
        fontFamily: font,
        color: palette.muted,
        fontSize: 13,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: palette.hairline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: palette.hairline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: palette.accent.withValues(alpha: 0.75),
          width: 1.4,
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.transparent,
      elevation: 0,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: palette.isLight
          ? const Color(0xFF1B2029)
          : const Color(0xFFF2F4F8),
      behavior: SnackBarBehavior.floating,
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: palette.accent,
        textStyle: TextStyle(
          fontFamily: font,
          fontWeight: FontWeight.w600,
          fontSize: 13.5,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return palette.accent;
        return Colors.transparent;
      }),
      checkColor: WidgetStatePropertyAll(
        palette.isLight ? Colors.white : const Color(0xFF07110E),
      ),
      side: BorderSide(color: palette.faint, width: 1.3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? (palette.isLight ? Colors.white : const Color(0xFF06110E))
            : palette.muted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) =>
            s.contains(WidgetState.selected) ? palette.accent : palette.raised,
      ),
      trackOutlineColor: WidgetStatePropertyAll(palette.hairline),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: palette.accent,
      inactiveTrackColor: palette.raised,
      thumbColor: palette.accent,
      overlayColor: palette.accent.withValues(alpha: 0.15),
      trackHeight: 3,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: palette.accent),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: palette.matte
          ? palette.surface
          : (palette.isLight
                ? const Color(0xFFF7F8FC)
                : const Color(0xFF11161F)),
      headerBackgroundColor: Colors.transparent,
      headerForegroundColor: palette.text,
      dayForegroundColor: WidgetStatePropertyAll(palette.text),
      yearForegroundColor: WidgetStatePropertyAll(palette.text),
    ),
    timePickerTheme: TimePickerThemeData(
      backgroundColor: palette.matte
          ? palette.surface
          : (palette.isLight
                ? const Color(0xFFF7F8FC)
                : const Color(0xFF11161F)),
      hourMinuteColor: palette.raised,
      hourMinuteTextColor: palette.text,
      dialBackgroundColor: palette.raised,
      dialHandColor: palette.accent,
      dialTextColor: palette.text,
      entryModeIconColor: palette.muted,
    ),
  );
}

List<double> hueRotationMatrix(double degrees) {
  final angle = degrees * pi / 180;
  final c = cos(angle);
  final s = sin(angle);
  return <double>[
    0.213 + c * 0.787 - s * 0.213,
    0.715 - c * 0.715 - s * 0.715,
    0.072 - c * 0.072 + s * 0.928,
    0,
    0,
    0.213 - c * 0.213 + s * 0.143,
    0.715 + c * 0.285 + s * 0.140,
    0.072 - c * 0.072 - s * 0.283,
    0,
    0,
    0.213 - c * 0.213 - s * 0.787,
    0.715 - c * 0.715 + s * 0.715,
    0.072 + c * 0.928 + s * 0.072,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ];
}

class ThemedMark extends StatelessWidget {
  final SoraPalette palette;
  final double size;
  final bool shadow;

  const ThemedMark({
    super.key,
    required this.palette,
    this.size = 52,
    this.shadow = true,
  });

  @override
  Widget build(BuildContext context) {
    Widget image = Image.asset(
      palette.iconAsset,
      width: size,
      height: size,
      fit: BoxFit.cover,
    );
    if (palette.custom && palette.iconHueShift.abs() > 1) {
      image = ColorFiltered(
        colorFilter: ColorFilter.matrix(
          hueRotationMatrix(palette.iconHueShift),
        ),
        child: image,
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.23),
        boxShadow: shadow
            ? (palette.matte
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: size * 0.3,
                        offset: Offset(0, size * 0.08),
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: palette.accent.withValues(alpha: 0.28),
                        blurRadius: size * 0.5,
                        spreadRadius: -size * 0.1,
                        offset: Offset(0, size * 0.12),
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: size * 0.3,
                        offset: Offset(0, size * 0.08),
                      ),
                    ])
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: image,
    );
  }
}

/// Small caps used for buttons and labels throughout the app.
TextStyle overlineStyle(SoraPalette p, {Color? color}) => TextStyle(
  fontSize: 10.5,
  fontWeight: FontWeight.w700,
  letterSpacing: 1.5,
  color: color ?? p.faint,
  fontFeatures: const [FontFeature.tabularFigures()],
);
