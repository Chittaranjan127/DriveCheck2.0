import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/audio_prompt_service.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/language_service.dart';
import '../../core/services/stt_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/widgets/primary_button.dart';
import '../auth/auth_provider.dart';
import 'profile_strings.dart';

/// Step 1 of profile completion. Plays a localized prompt, lets the user
/// speak or type their name, saves via PATCH /auth/me, then advances to selfie.
class ProfileSetupNameScreen extends ConsumerStatefulWidget {
  const ProfileSetupNameScreen({super.key});

  @override
  ConsumerState<ProfileSetupNameScreen> createState() => _ProfileSetupNameScreenState();
}

class _ProfileSetupNameScreenState extends ConsumerState<ProfileSetupNameScreen> {
  final _controller = TextEditingController();
  bool _isListening = false;
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _playPrompt());
  }

  @override
  void dispose() {
    _controller.dispose();
    SttService.instance.cancel();
    AudioPromptService.instance.stop();
    super.dispose();
  }

  AppLanguage get _lang =>
      ref.read(languageProvider).valueOrNull ?? AppLanguage.hindi;

  Future<void> _playPrompt() async {
    await AudioPromptService.instance.play(
      PromptIds.whatsYourName,
      _lang,
      onComplete: () {
        if (!mounted || _isListening) return;
        _startListening();
      },
    );
  }

  Future<void> _toggleListen() async {
    if (_isListening) {
      await SttService.instance.stop();
      return;
    }
    await AudioPromptService.instance.stop();
    await _startListening();
  }

  Future<void> _startListening() async {
    final s = ProfileStrings.of(_lang);
    final started = await SttService.instance.listen(
      language: _lang,
      onResult: (text, isFinal) {
        if (!mounted) return;
        final cleaned = _extractName(text);
        setState(() {
          _controller.text = cleaned;
          _controller.selection =
              TextSelection.collapsed(offset: cleaned.length);
        });
      },
      onError: (err) {
        if (!mounted) return;
        setState(() {
          _error = err == 'permission' ? s.permissionDenied : s.didntCatch;
        });
      },
      onDone: () {
        if (!mounted) return;
        setState(() => _isListening = false);
      },
    );
    setState(() {
      _isListening = started;
      _error = started ? null : s.permissionDenied;
    });
  }

  /// Best-effort extraction of just the name from a sentence like
  /// "My name is Vicky." or "Mera naam Vicky hai". Falls back to the trimmed
  /// transcript when no known pattern matches.
  static String _extractName(String raw) {
    var s = raw.trim();
    s = s.replaceAll(RegExp(r'[.!?,।]+$'), '').trim();
    const prefixPatterns = [
      r"^my\s+name\s+is\s+",
      r"^i\s*['’]?\s*am\s+",
      r"^i\s*['’]?\s*m\s+",
      r"^this\s+is\s+",
      r"^call\s+me\s+",
      r"^name\s+is\s+",
      r"^mera\s+naam\s+",
      r"^mera\s+nam\s+",
      r"^mere\s+naam\s+",
      r"^main\s+",
      r"^mai\s+",
      r"^mee\s+peru\s+",
      r"^naa\s+peru\s+",
      r"^amar\s+naam\s+",
      r"^ami\s+",
    ];
    for (final p in prefixPatterns) {
      s = s.replaceFirst(RegExp(p, caseSensitive: false), '');
    }
    const suffixPatterns = [
      r"\s+hai$",
      r"\s+hain$",
      r"\s+hoon$",
      r"\s+he$",
    ];
    for (final p in suffixPatterns) {
      s = s.replaceFirst(RegExp(p, caseSensitive: false), '');
    }
    s = s.trim();
    if (s.isEmpty) return raw.trim();
    return s
        .split(RegExp(r'\s+'))
        .map((w) =>
            w.isEmpty ? w : w[0].toUpperCase() + w.substring(1).toLowerCase())
        .join(' ');
  }

  Future<void> _save() async {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      await SttService.instance.cancel();
      await AuthService().updateMe(
        name: name,
        preferredLanguage: _lang.name,
      );
      await ref.read(authProvider.notifier).refreshMe();
      if (!mounted) return;
      context.go('/profile/setup/selfie');
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ProfileStrings.of(_lang);

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: AppColors.background,
        leading: const SizedBox.shrink(),
        actions: [
          TextButton.icon(
            onPressed: _playPrompt,
            icon: const Icon(Icons.volume_up_rounded, color: AppColors.primary),
            label: Text(s.replay,
                style: AppTextStyles.body.copyWith(color: AppColors.primary)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _StepDots(current: 1, total: 2),
              const SizedBox(height: 28),
              Text(s.whatsYourName, style: AppTextStyles.heading1),
              const SizedBox(height: 8),
              Text(s.nameHint,
                  style: AppTextStyles.body.copyWith(color: AppColors.textSecondary)),
              const SizedBox(height: 40),
              Center(child: _MicButton(active: _isListening, onTap: _toggleListen)),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  _isListening ? s.listening : s.tapMicToSpeak,
                  style: AppTextStyles.body.copyWith(
                    color: _isListening ? AppColors.primary : AppColors.textHint,
                    fontWeight: _isListening ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _controller,
                textCapitalization: TextCapitalization.words,
                style: AppTextStyles.heading3,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AppColors.surfaceMuted,
                  hintText: s.nameField,
                  hintStyle:
                      AppTextStyles.heading3.copyWith(color: AppColors.textHint),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: AppTextStyles.body.copyWith(color: AppColors.error)),
              ],
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: PrimaryButton(
                  label: s.continueLabel,
                  isLoading: _isSaving,
                  onPressed: _controller.text.trim().isEmpty ? null : _save,
                  trailingIcon: Icons.arrow_forward_rounded,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MicButton extends StatelessWidget {
  final bool active;
  final VoidCallback onTap;
  const _MicButton({required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 112,
        height: 112,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? AppColors.primary : AppColors.primaryLight,
          boxShadow: active
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.35),
                    blurRadius: 24,
                    spreadRadius: 6,
                  ),
                ]
              : [],
        ),
        child: Icon(
          active ? Icons.mic : Icons.mic_none_rounded,
          color: active ? AppColors.onPrimary : AppColors.primary,
          size: 52,
        ),
      ),
    );
  }
}

class _StepDots extends StatelessWidget {
  final int current;
  final int total;
  const _StepDots({required this.current, required this.total});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(total, (i) {
        final active = i < current;
        return Container(
          width: 28, height: 4,
          margin: const EdgeInsets.only(right: 6),
          decoration: BoxDecoration(
            color: active ? AppColors.primary : AppColors.border,
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }
}
