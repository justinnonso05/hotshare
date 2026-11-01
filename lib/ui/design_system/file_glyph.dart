import 'package:flutter/material.dart';

import 'hs_colors.dart';
import 'hs_text.dart';

/// A folded-corner file icon with kind-specific colour coding.
///
/// Supported [kind] values: `pdf`, `docx`, `xlsx`, `pptx`, `zip`, plus any
/// unknown value which falls back to a generic glass tile showing [ext].
class FileGlyph extends StatelessWidget {
  final String kind; // classifyFileKind result or explicit doc type
  final String ext;  // raw extension for fallback label
  final double size;

  const FileGlyph({
    super.key,
    required this.kind,
    required this.ext,
    this.size = 48,
  });

  static Color colorForKind(String kind) {
    switch (kind.toLowerCase()) {
      case 'pdf':
        return HsColors.glowMid;
      case 'docx':
      case 'doc':
      case 'document':
        return const Color(0xFF185ABC);
      case 'xlsx':
      case 'xls':
        return const Color(0xFF1D6F3C);
      case 'pptx':
      case 'ppt':
        return const Color(0xFFB7472A);
      case 'zip':
      case 'archive':
        return HsColors.warning;
      case 'image':
        return const Color(0xFF8B5CF6);
      case 'video':
        return const Color(0xFF0EA5E9);
      case 'audio':
        return const Color(0xFFEC4899);
      default:
        return HsColors.textTertiary;
    }
  }

  static IconData iconForKind(String kind) {
    switch (kind.toLowerCase()) {
      case 'image':
        return Icons.image_rounded;
      case 'video':
        return Icons.videocam_rounded;
      case 'audio':
        return Icons.music_note_rounded;
      case 'archive':
      case 'zip':
        return Icons.folder_zip_rounded;
      default:
        return Icons.description_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = colorForKind(kind);
    final label = ext.toUpperCase().length > 4
        ? ext.toUpperCase().substring(0, 4)
        : ext.toUpperCase();

    return SizedBox(
      width: size,
      height: size * 1.2,
      child: CustomPaint(
        painter: _GlyphPainter(color: color),
        child: Center(
          child: Padding(
            padding: EdgeInsets.only(top: size * 0.18),
            child: Text(
              label,
              style: HsText.micro.copyWith(
                fontSize: size * 0.19,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: -0.3,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}

class _GlyphPainter extends CustomPainter {
  final Color color;
  const _GlyphPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final fold = w * 0.28; // fold triangle size
    final r = w * 0.12; // corner radius for body

    final bodyPath = Path()
      ..moveTo(r, 0)
      ..lineTo(w - fold, 0)
      ..lineTo(w, fold)
      ..lineTo(w, h - r)
      ..quadraticBezierTo(w, h, w - r, h)
      ..lineTo(r, h)
      ..quadraticBezierTo(0, h, 0, h - r)
      ..lineTo(0, r)
      ..quadraticBezierTo(0, 0, r, 0)
      ..close();

    // Drop shadow
    canvas.drawShadow(bodyPath, Colors.black.withAlpha(100), 4, true);

    // Body fill with vertical gradient
    final bodyPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          color,
          Color.lerp(color, Colors.black, 0.35)!,
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawPath(bodyPath, bodyPaint);

    // Fold triangle
    final foldPath = Path()
      ..moveTo(w - fold, 0)
      ..lineTo(w, fold)
      ..lineTo(w - fold, fold)
      ..close();

    final foldPaint = Paint()
      ..color = Colors.white.withAlpha(51);
    canvas.drawPath(foldPath, foldPaint);

    // Fold crease border
    final creasePaint = Paint()
      ..color = Colors.white.withAlpha(30)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    canvas.drawPath(foldPath, creasePaint);
  }

  @override
  bool shouldRepaint(_GlyphPainter old) => old.color != color;
}
