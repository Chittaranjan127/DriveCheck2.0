import 'package:flutter/material.dart';

/// Cars24 brand palette. Indigo primary, monochrome surfaces, black CTAs.
class AppColors {
  // Brand
  static const primary       = Color(0xFF5B43F5); // Cars24 indigo
  static const primaryDark   = Color(0xFF4530C7);
  static const primaryLight  = Color(0xFFEEEBFE);
  static const onPrimary     = Color(0xFFFFFFFF);

  // CTA / monochrome
  static const ctaDark       = Color(0xFF0A0A0A);
  static const onCtaDark     = Color(0xFFFFFFFF);

  // Surfaces
  static const background    = Color(0xFFFFFFFF);
  static const surface       = Color(0xFFFFFFFF);
  static const surfaceMuted  = Color(0xFFF5F5F7);
  static const card          = Color(0xFFFAFAFA);
  static const chipBg        = Color(0xFFF2F2F4);

  // Text
  static const textPrimary   = Color(0xFF0A0A0A);
  static const textSecondary = Color(0xFF6B6B70);
  static const textHint      = Color(0xFFA0A0A6);
  static const textOnDark    = Color(0xFFFFFFFF);

  // Status accents
  static const success       = Color(0xFF10B981);
  static const warning       = Color(0xFFF59E0B);
  static const error         = Color(0xFFE11D48);
  static const info          = Color(0xFF3B82F6);

  // Step progress
  static const stepDone      = Color(0xFF10B981);
  static const stepActive    = Color(0xFF5B43F5);
  static const stepPending   = Color(0xFFE5E5E7);

  static const divider       = Color(0xFFEEEEF0);
  static const border        = Color(0xFFE5E5E7);
}
