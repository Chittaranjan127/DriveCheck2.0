import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';

/// DriveCheck wordmark — rounded icon tile + "DriveCheck" text.
/// Both render via [color] so it tints to white on dark backgrounds,
/// dark on light. Sized off [fontSize].
class Cars24Wordmark extends StatelessWidget {
  final double fontSize;
  final Color color;
  const Cars24Wordmark({super.key, this.fontSize = 28, this.color = AppColors.textPrimary});

  @override
  Widget build(BuildContext context) {
    final iconSize = fontSize * 1.4;
    // Pick a contrasting glyph color so the icon "punches out" of the tile.
    final glyphColor = ThemeData.estimateBrightnessForColor(color) == Brightness.light
        ? AppColors.primary
        : AppColors.onPrimary;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: iconSize,
          height: iconSize,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(iconSize * 0.22),
          ),
          child: Icon(Icons.autorenew_rounded, size: iconSize * 0.7, color: glyphColor),
        ),
        SizedBox(width: fontSize * 0.45),
        Text(
          'DriveCheck',
          style: GoogleFonts.inter(
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            letterSpacing: -fontSize * 0.03,
            color: color,
            height: 1.0,
          ),
        ),
      ],
    );
  }
}
