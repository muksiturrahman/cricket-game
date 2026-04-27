import 'package:flutter/material.dart';

/// ───────────────────────────────────────────────────────────────────────────
/// AppTheme — central palette, gradients, typography and panel recipes.
///
/// Anything visual that is shared between the Flame canvas and the Flutter
/// overlays should live here. Game components import `kPalette` / `kGradients`
/// directly; widget overlays use `AppTheme.of(context)`-style helpers that
/// just delegate to these constants.
/// ───────────────────────────────────────────────────────────────────────────

class AppPalette {
  const AppPalette();

  // Brand
  Color get primary => const Color(0xFFFFC93C); // Cricket gold
  Color get primaryDark => const Color(0xFFE5A91A);
  Color get accent => const Color(0xFFFF5252); // Match-red highlight
  Color get danger => const Color(0xFFE53935);

  // Surfaces
  Color get surface => const Color(0xFF0F2A1D); // Deep stadium green-black
  Color get surfaceLow => const Color(0xFF071A11);
  Color get panel => const Color(0xCC07120B);
  Color get panelLight => const Color(0x99183024);
  Color get divider => const Color(0x33FFFFFF);

  // Field
  Color get grassLight => const Color(0xFF4DA855);
  Color get grass => const Color(0xFF327D3A);
  Color get grassDark => const Color(0xFF1F5C2A);
  Color get pitchLight => const Color(0xFFC79767);
  Color get pitch => const Color(0xFFA37145);
  Color get pitchDark => const Color(0xFF704D2D);
  Color get pitchWear => const Color(0x331A0E04);

  // Sky
  Color get skyTop => const Color(0xFF173453);
  Color get skyMid => const Color(0xFF3A6FA0);
  Color get skyHorizon => const Color(0xFFE5B888);

  // Stadium / crowd
  Color get stand => const Color(0xFF243846);
  Color get standDark => const Color(0xFF15212A);
  Color get crowd => const Color(0xFF2C3E50);
  Color get crowdSpeck1 => const Color(0xFFC0382A);
  Color get crowdSpeck2 => const Color(0xFFE67E22);
  Color get crowdSpeck3 => const Color(0xFFECF0F1);
  Color get crowdSpeck4 => const Color(0xFFF1C40F);

  // Text
  Color get textHi => const Color(0xFFFFFFFF);
  Color get textMid => const Color(0xCCFFFFFF);
  Color get textLow => const Color(0x99FFFFFF);

  // Overlay (HUD)
  Color get hudPanel => const Color(0xCC07140A);
  Color get hudPanelStroke => const Color(0x33FFC93C);
}

const AppPalette kPalette = AppPalette();

/// Gradient recipes — declared at top-level so they're const & cheap to use
/// inside `paint(canvas, size)` calls without rebuilding.
class AppGradients {
  static LinearGradient sky() => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [kPalette.skyTop, kPalette.skyMid, kPalette.skyHorizon],
        stops: const [0.0, 0.55, 1.0],
      );

  static RadialGradient outfield() => RadialGradient(
        center: Alignment.center,
        radius: 0.85,
        colors: [kPalette.grassLight, kPalette.grass, kPalette.grassDark],
        stops: const [0.0, 0.55, 1.0],
      );

  static LinearGradient pitch() => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [kPalette.pitchLight, kPalette.pitch, kPalette.pitchDark],
        stops: const [0.0, 0.5, 1.0],
      );

  static LinearGradient menuBackdrop() => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          const Color(0xFF051F12),
          const Color(0xFF0E3520),
          const Color(0xFF1A2F4A),
        ],
        stops: const [0.0, 0.55, 1.0],
      );

  static LinearGradient panel() => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [const Color(0xEE0E2618), const Color(0xCC061309)],
      );

  static LinearGradient goldButton() => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [kPalette.primary, kPalette.primaryDark],
      );

  static LinearGradient redButton() => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFE53935), Color(0xFFAA1D1A)],
      );

  static LinearGradient slateButton() => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF334155), Color(0xFF1E293B)],
      );
}

/// Pre-baked TextStyles for menus / dialogs. The HUD draws via Flame's
/// TextPaint and uses these as a base.
class AppText {
  static const TextStyle hero = TextStyle(
    color: Colors.white,
    fontSize: 44,
    fontWeight: FontWeight.w900,
    letterSpacing: 4,
    height: 1.0,
    shadows: [
      Shadow(blurRadius: 14, color: Color(0x88FFC93C), offset: Offset(0, 0)),
      Shadow(blurRadius: 4, color: Colors.black, offset: Offset(0, 2)),
    ],
  );

  static const TextStyle h1 = TextStyle(
    color: Colors.white,
    fontSize: 28,
    fontWeight: FontWeight.w800,
    letterSpacing: 1.5,
  );

  static const TextStyle h2 = TextStyle(
    color: Colors.white,
    fontSize: 18,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.2,
  );

  static const TextStyle body = TextStyle(
    color: Colors.white70,
    fontSize: 14,
    height: 1.55,
  );

  static const TextStyle label = TextStyle(
    color: Color(0xCCFFFFFF),
    fontSize: 11,
    fontWeight: FontWeight.bold,
    letterSpacing: 2.4,
  );

  static const TextStyle scoreBig = TextStyle(
    color: Colors.white,
    fontSize: 64,
    fontWeight: FontWeight.w900,
    letterSpacing: 1,
    height: 1.0,
  );
}

/// Common BoxDecoration recipes used across overlays.
class AppPanels {
  static BoxDecoration card() => BoxDecoration(
        gradient: AppGradients.panel(),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x44FFC93C), width: 1.2),
        boxShadow: const [
          BoxShadow(
              blurRadius: 18, color: Color(0xAA000000), offset: Offset(0, 6)),
        ],
      );

  static BoxDecoration pill({required bool selected}) => BoxDecoration(
        gradient: selected ? AppGradients.goldButton() : null,
        color: selected ? null : const Color(0x22FFFFFF),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: selected
              ? const Color(0xFFFFD66B)
              : const Color(0x44FFFFFF),
          width: 1.4,
        ),
        boxShadow: selected
            ? const [
                BoxShadow(
                    blurRadius: 12,
                    color: Color(0x66FFC93C),
                    offset: Offset(0, 3))
              ]
            : null,
      );

  static BoxDecoration bigButton(LinearGradient g) => BoxDecoration(
        gradient: g,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
              blurRadius: 14, color: Color(0xCC000000), offset: Offset(0, 5)),
        ],
      );
}
