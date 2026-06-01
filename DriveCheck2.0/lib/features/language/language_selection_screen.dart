import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/i18n/translations.dart';
import '../../core/services/language_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/widgets/primary_button.dart';
import '../auth/post_auth_route.dart';

/// Language picker. Uses currently-selected language for instructions (default English).
class LanguageSelectionScreen extends ConsumerStatefulWidget {
  const LanguageSelectionScreen({super.key});

  @override
  ConsumerState<LanguageSelectionScreen> createState() => _LanguageSelectionScreenState();
}

class _LanguageSelectionScreenState extends ConsumerState<LanguageSelectionScreen> {
  AppLanguage? _selected;
  bool _saving = false;

  Future<void> _continue() async {
    if (_selected == null) return;
    setState(() => _saving = true);
    await ref.read(languageProvider.notifier).setLanguage(_selected!);
    if (!mounted) return;
    final dest = await resolvePostAuthRoute(ref);
    if (!mounted) return;
    context.go(dest);
  }

  @override
  Widget build(BuildContext context) {
    // Show in the preview-language so the user sees the change live.
    final preview = _selected != null ? Translations.forLanguage(_selected!) : ref.watch(translationsProvider);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              Text(preview.chooseLanguage, style: preview.style(AppTextStyles.heading1)),
              const SizedBox(height: 8),
              Text(
                preview.chooseLanguageSub,
                style: preview.style(AppTextStyles.bodyLarge).copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 28),
              Expanded(
                child: GridView.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  childAspectRatio: 0.92,
                  children: AppLanguage.values
                      .map((lang) => _LanguageCard(
                            language: lang,
                            selected: _selected == lang,
                            onTap: () => setState(() => _selected = lang),
                          ))
                      .toList(),
                ),
              ),
              const SizedBox(height: 16),
              PrimaryButton(
                label: preview.continueLabel,
                isLoading: _saving,
                onPressed: _selected == null ? null : _continue,
                trailingIcon: Icons.arrow_forward,
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _LanguageCard extends StatelessWidget {
  final AppLanguage language;
  final bool selected;
  final VoidCallback onTap;

  const _LanguageCard({required this.language, required this.selected, required this.onTap});

  TextStyle _nativeStyle() {
    switch (language) {
      case AppLanguage.hindi:
        return GoogleFonts.notoSansDevanagari(fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: -0.5);
      case AppLanguage.telugu:
        return GoogleFonts.notoSansTelugu(fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.5);
      case AppLanguage.bengali:
        return GoogleFonts.notoSansBengali(fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: -0.5);
      case AppLanguage.english:
        return GoogleFonts.inter(fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.8);
    }
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = selected ? AppColors.ctaDark : AppColors.border;
    final bg = selected ? AppColors.surface : AppColors.surfaceMuted;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: borderColor, width: selected ? 1.5 : 1),
          ),
          padding: const EdgeInsets.all(18),
          child: Stack(
            children: [
              Positioned(
                top: 0,
                right: 0,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 160),
                  opacity: selected ? 1 : 0,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: const BoxDecoration(color: AppColors.ctaDark, shape: BoxShape.circle),
                    child: const Icon(Icons.check, color: AppColors.onCtaDark, size: 16),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.bottomLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(language.nativeName, style: _nativeStyle().copyWith(color: AppColors.textPrimary)),
                    const SizedBox(height: 4),
                    Text(language.englishName, style: AppTextStyles.caption),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
