import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/translations.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

/// Blank home screen — intentionally empty placeholder. Hosts the first
/// bottom-nav tab. Real content gets built on top of this later.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: AppColors.background,
        title: Text(t.navHome, style: t.style(AppTextStyles.heading2)),
      ),
      body: Center(
        child: Text(
          t.navHome,
          style: t.style(AppTextStyles.body).copyWith(color: AppColors.textHint),
        ),
      ),
    );
  }
}
