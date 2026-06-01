import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/translations.dart';
import '../../core/services/language_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/widgets/cars24_wordmark.dart';
import '../../shared/widgets/primary_button.dart';
import 'auth_provider.dart';
import 'auth_state.dart';
import 'post_auth_route.dart';

/// Phone entry. Editorial-style heading, pill input, dark CTA.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _phoneController = TextEditingController();
  final _phoneFocus = FocusNode();
  String? _localError;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _phoneFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _phoneFocus.dispose();
    super.dispose();
  }

  Future<void> _sendOtp(Translations t) async {
    if (_isSending) return;
    final phone = _phoneController.text.trim();
    if (phone.length != 10) {
      setState(() => _localError = t.invalidPhone);
      return;
    }
    setState(() {
      _localError = null;
      _isSending = true;
    });
    FocusScope.of(context).unfocus();
    // Guarantee the spinner is visible long enough to register, even on a
    // fast network.
    final minVisible = Future.delayed(const Duration(milliseconds: 400));
    await ref.read(authProvider.notifier).sendOtp(phone);
    await minVisible;
    if (!mounted) return;
    final state = ref.read(authProvider);
    if (state is AuthOtpSent) {
      context.go('/otp', extra: phone);
      return;
    }
    setState(() {
      _isSending = false;
      if (state is AuthError) _localError = t.numberNotRegistered;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider);
    final auth = ref.watch(authProvider);
    final isLoading = _isSending || auth is AuthOtpSending;

    // If splash bailed to /login before /auth/me finished and the user
    // turns out to be authenticated, route them away here.
    ref.listen<AuthState>(authProvider, (prev, next) async {
      if (next is AuthAuthenticated) {
        final dest = await resolvePostAuthRoute(ref);
        if (!context.mounted) return;
        context.go(dest);
      }
    });

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              const Align(alignment: Alignment.centerLeft, child: Cars24Wordmark(fontSize: 22)),
              const SizedBox(height: 56),
              Text(t.signIn, style: t.style(AppTextStyles.heading1)),
              const SizedBox(height: 8),
              Text(t.otpHint, style: t.style(AppTextStyles.bodyLarge).copyWith(color: AppColors.textSecondary)),
              const SizedBox(height: 36),
              Text(t.mobileNumber, style: t.style(AppTextStyles.caption).copyWith(letterSpacing: 0.4)),
              const SizedBox(height: 8),
              TextField(
                controller: _phoneController,
                focusNode: _phoneFocus,
                autofocus: true,
                keyboardType: TextInputType.phone,
                maxLength: 10,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: AppTextStyles.heading3.copyWith(fontSize: 18, letterSpacing: 0.5),
                cursorColor: AppColors.primary,
                decoration: InputDecoration(
                  prefixIcon: Padding(
                    padding: const EdgeInsets.only(left: 20, right: 8),
                    child: Text('+91',
                        style: AppTextStyles.heading3.copyWith(fontSize: 18, color: AppColors.textPrimary)),
                  ),
                  prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                  counterText: '',
                  errorText: _localError,
                ),
              ),
              const SizedBox(height: 28),
              PrimaryButton(
                label: t.sendOtp,
                isLoading: isLoading,
                onPressed: () => _sendOtp(t),
                trailingIcon: Icons.arrow_forward,
              ),
              const Spacer(),
              Center(
                child: TextButton(
                  onPressed: () => _showLanguageReset(context),
                  child: Text(t.changeLanguage,
                      style: t.style(AppTextStyles.caption).copyWith(color: AppColors.primary)),
                ),
              ),
              const SizedBox(height: 4),
              Center(child: Text(t.poweredBy, style: t.style(AppTextStyles.caption))),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showLanguageReset(BuildContext context) async {
    await ref.read(languageProvider.notifier).clear();
    if (!context.mounted) return;
    context.go('/language');
  }
}
