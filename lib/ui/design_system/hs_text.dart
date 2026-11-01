import 'package:flutter/material.dart';
import 'hs_colors.dart';

/// Typography tokens for the Ember Glass design system.
abstract final class HsText {
  // ── Sizes ──────────────────────────────────────────────────────────────────
  static const double sizeDisplay = 34;
  static const double sizeHeadline = 22;
  static const double sizeTitle = 17;
  static const double sizeBody = 15;
  static const double sizeCaption = 13;
  static const double sizeMicro = 11;

  // ── Styles ─────────────────────────────────────────────────────────────────
  static const TextStyle display = TextStyle(
    fontSize: sizeDisplay,
    fontWeight: FontWeight.w700,
    color: HsColors.textPrimary,
    letterSpacing: -0.5,
    height: 1.15,
  );

  static const TextStyle headline = TextStyle(
    fontSize: sizeHeadline,
    fontWeight: FontWeight.w600,
    color: HsColors.textPrimary,
    letterSpacing: -0.3,
    height: 1.2,
  );

  static const TextStyle title = TextStyle(
    fontSize: sizeTitle,
    fontWeight: FontWeight.w600,
    color: HsColors.textPrimary,
    letterSpacing: -0.1,
    height: 1.25,
  );

  static const TextStyle body = TextStyle(
    fontSize: sizeBody,
    fontWeight: FontWeight.w400,
    color: HsColors.textSecondary,
    height: 1.4,
  );

  static const TextStyle caption = TextStyle(
    fontSize: sizeCaption,
    fontWeight: FontWeight.w400,
    color: HsColors.textTertiary,
    height: 1.35,
  );

  static const TextStyle micro = TextStyle(
    fontSize: sizeMicro,
    fontWeight: FontWeight.w500,
    color: HsColors.textTertiary,
    letterSpacing: 0.3,
  );

  static const TextStyle labelBold = TextStyle(
    fontSize: sizeBody,
    fontWeight: FontWeight.w700,
    color: HsColors.textPrimary,
  );
}
