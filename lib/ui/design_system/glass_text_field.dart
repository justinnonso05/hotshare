import 'package:flutter/material.dart';
import 'hs_colors.dart';

/// A frosted-glass text input field styled for the Ember Glass design system.
class GlassTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String hint;
  final IconData? prefixIcon;
  final Widget? suffixWidget;
  final bool obscureText;
  final TextInputType keyboardType;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onTap;
  final bool readOnly;
  final FocusNode? focusNode;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final int? maxLines;

  const GlassTextField({
    super.key,
    this.controller,
    this.hint = '',
    this.prefixIcon,
    this.suffixWidget,
    this.obscureText = false,
    this.keyboardType = TextInputType.text,
    this.onChanged,
    this.onTap,
    this.readOnly = false,
    this.focusNode,
    this.textInputAction,
    this.onSubmitted,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      onChanged: onChanged,
      onTap: onTap,
      readOnly: readOnly,
      focusNode: focusNode,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      maxLines: maxLines,
      style: const TextStyle(color: HsColors.textPrimary, fontSize: 15),
      cursorColor: HsColors.accentPrimary,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: HsColors.textTertiary, fontSize: 15),
        filled: true,
        fillColor: HsColors.glassFillStrong,
        prefixIcon: prefixIcon != null
            ? Icon(prefixIcon, color: HsColors.textTertiary, size: 18)
            : null,
        suffix: suffixWidget,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(HsColors.radiusInput),
          borderSide: const BorderSide(color: HsColors.glassStroke, width: 0.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(HsColors.radiusInput),
          borderSide: const BorderSide(color: HsColors.glassStroke, width: 0.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(HsColors.radiusInput),
          borderSide:
              const BorderSide(color: HsColors.accentPrimary, width: 1.5),
        ),
      ),
    );
  }
}
