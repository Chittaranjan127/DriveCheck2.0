import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Inter for Latin, Noto Sans for Indic scripts. Tight letter-spacing on headings.
class AppTextStyles {
  static TextStyle display   = GoogleFonts.inter(fontSize: 40, fontWeight: FontWeight.w700, height: 1.1, letterSpacing: -1.2, color: AppColors.textPrimary);
  static TextStyle heading1  = GoogleFonts.inter(fontSize: 32, fontWeight: FontWeight.w700, height: 1.15, letterSpacing: -0.8, color: AppColors.textPrimary);
  static TextStyle heading2  = GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w600, height: 1.2, letterSpacing: -0.4, color: AppColors.textPrimary);
  static TextStyle heading3  = GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.textPrimary);
  static TextStyle body      = GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w400, color: AppColors.textPrimary);
  static TextStyle bodyLarge = GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w400, color: AppColors.textPrimary);
  static TextStyle caption   = GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSecondary);
  static TextStyle button    = GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: -0.1, color: AppColors.onCtaDark);
  static TextStyle chip      = GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSecondary);

  // Indic scripts
  static TextStyle hindiLarge = GoogleFonts.notoSansDevanagari(fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.textPrimary);
  static TextStyle hindiBody  = GoogleFonts.notoSansDevanagari(fontSize: 16, fontWeight: FontWeight.w500, color: AppColors.textPrimary);
  static TextStyle hindiSmall = GoogleFonts.notoSansDevanagari(fontSize: 14, fontWeight: FontWeight.w400, color: AppColors.textSecondary);
}
