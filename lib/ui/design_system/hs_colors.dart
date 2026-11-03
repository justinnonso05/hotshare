import 'package:flutter/material.dart';

/// Ember Glass Design System — Color Tokens.
///
/// All colours are either fully opaque or carry an intentional alpha value.
/// DO NOT use raw [Colors] elsewhere in UI code; reference these tokens instead.
abstract final class HsColors {
  // ── Backgrounds ────────────────────────────────────────────────────────────
  static const Color bgBase = Color(0xFF0A0A0C);
  static const Color bgRaised = Color(0xFF141417);

  // ── Ember Glow Palette ─────────────────────────────────────────────────────
  static const Color glowDeep = Color(0xFF7A0A12); // deep crimson blob
  static const Color glowMid = Color(0xFFE5231B); // primary red accent
  static const Color glowHot = Color(0xFFFF7A1A); // warm orange accent

  // ── Semantic Accents ───────────────────────────────────────────────────────
  static const Color accentPrimary = glowMid;
  static const Color accentWarm = glowHot;
  static const Color success = Color(0xFF34D27B);
  static const Color online = success;
  static const Color warning = Color(0xFFFFC247);
  static const Color danger = Color(0xFFFF4D4F);

  // ── Text ───────────────────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xF2FFFFFF); // ~95 % white
  static const Color textSecondary = Color(0x9EFFFFFF); // ~62 % white
  static const Color textTertiary = Color(0x61FFFFFF); // ~38 % white

  // ── Glass Surfaces ─────────────────────────────────────────────────────────
  static const Color glassFill = Color(0x12FFFFFF); // 7 % white
  static const Color glassFillStrong = Color(0x1FFFFFFF); // 12 % white
  static const Color glassStroke = Color(0x29FFFFFF); // 16 % white

  // ── Gradients ──────────────────────────────────────────────────────────────
  static const LinearGradient emberGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [glowMid, glowHot],
  );

  static const LinearGradient glassBorderGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0x47FFFFFF), Color(0x14FFFFFF)],
  );

  // ── Radius ─────────────────────────────────────────────────────────────────
  static const double radiusCard = 28;
  static const double radiusInput = 20;
  static const double radiusPill = 100;
  static const double radiusSmall = 12;
}
