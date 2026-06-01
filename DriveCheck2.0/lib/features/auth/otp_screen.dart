import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/translations.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/widgets/in_app_sms_banner.dart';
import '../../shared/widgets/primary_button.dart';
import 'auth_provider.dart';
import 'auth_state.dart';
import 'post_auth_route.dart';

/// 6-box OTP entry. Auto-submits on full input.
class OtpScreen extends ConsumerStatefulWidget {
  final String phoneNumber;
  const OtpScreen({super.key, required this.phoneNumber});

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  static const _resendCooldownSeconds = 10;

  // Each box is seeded with a zero-width space ('​') so that the
  // software keyboard always has *something* to delete when the user taps
  // backspace — without it, iOS/Android IMEs swallow the backspace on an
  // empty field and we never get an onChanged callback to react to.
  static const _placeholder = '​';
  final List<TextEditingController> _controllers = List.generate(
    6,
    (_) => TextEditingController(text: _placeholder),
  );
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());
  Timer? _cooldownTimer;
  int _resendSecondsLeft = 0;
  bool _isVerifying = false;

  @override
  void initState() {
    super.initState();
    for (final c in _controllers) {
      c.selection = const TextSelection.collapsed(offset: _placeholder.length);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNodes.first.requestFocus();
      _startCooldown();
      _scheduleSmsBanner();
    });
  }

  void _clearBoxes() {
    for (final c in _controllers) {
      c.value = const TextEditingValue(
        text: _placeholder,
        selection: TextSelection.collapsed(offset: _placeholder.length),
      );
    }
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    for (final c in _controllers) { c.dispose(); }
    for (final f in _focusNodes) { f.dispose(); }
    super.dispose();
  }

  void _scheduleSmsBanner() {
    final state = ref.read(authProvider);
    final mockOtp = state is AuthOtpSent ? state.mockOtp : null;
    if (mockOtp == null) return;
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      InAppSmsBanner.show(
        context,
        sender: 'MD-DRIVE',
        message: '$mockOtp is your DriveCheck OTP. Do not share with anyone. Valid for 5 minutes.',
      );
    });
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _resendSecondsLeft = _resendCooldownSeconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendSecondsLeft <= 1) {
        timer.cancel();
        setState(() => _resendSecondsLeft = 0);
      } else {
        setState(() => _resendSecondsLeft--);
      }
    });
  }

  Future<void> _resend() async {
    if (_resendSecondsLeft > 0) return;
    _clearBoxes();
    _focusNodes.first.requestFocus();
    setState(() {});
    await ref.read(authProvider.notifier).sendOtp(widget.phoneNumber);
    if (!mounted) return;
    _startCooldown();
    _scheduleSmsBanner();
  }

  String get _otp =>
      _controllers.map((c) => c.text.replaceAll(_placeholder, '')).join();

  void _onChanged(int index, String value) {
    // Keep only digits — strips the ZWSP placeholder and anything pasted that
    // isn't a number.
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');

    if (digits.isEmpty) {
      // User backspaced over the placeholder → step back, clear previous box.
      _controllers[index].value = const TextEditingValue(
        text: _placeholder,
        selection: TextSelection.collapsed(offset: _placeholder.length),
      );
      if (index > 0) {
        _controllers[index - 1].value = const TextEditingValue(
          text: _placeholder,
          selection: TextSelection.collapsed(offset: _placeholder.length),
        );
        _focusNodes[index - 1].requestFocus();
      }
    } else {
      // Distribute (handles both single-digit type and pasted multi-digit).
      for (var j = 0; j < digits.length && index + j < 6; j++) {
        _controllers[index + j].value = TextEditingValue(
          text: '$_placeholder${digits[j]}',
          selection: const TextSelection.collapsed(offset: 2),
        );
      }
      final nextFocus = (index + digits.length).clamp(0, 5);
      _focusNodes[nextFocus].requestFocus();
    }
    setState(() {});
    if (_otp.length == 6) {
      FocusScope.of(context).unfocus();
      _verify();
    }
  }

  Future<void> _verify() async {
    if (_isVerifying) return;
    setState(() => _isVerifying = true);
    final minVisible = Future.delayed(const Duration(milliseconds: 400));
    await ref.read(authProvider.notifier).verifyOtp(_otp);
    await minVisible;
    if (!mounted) return;
    final state = ref.read(authProvider);
    if (state is AuthAuthenticated) {
      final dest = await resolvePostAuthRoute(ref);
      if (!mounted) return;
      context.go(dest);
      return;
    }
    setState(() => _isVerifying = false);
    if (state is AuthError) {
      _clearBoxes();
      _focusNodes.first.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider);
    final auth = ref.watch(authProvider);
    final isLoading = _isVerifying || auth is AuthVerifying;
    final errorText = auth is AuthError
        ? (auth.code == AuthErrorCode.network ? 'Network error. Try again.' : t.otpWrong)
        : null;

    return Scaffold(
      appBar: AppBar(leading: const BackButton()),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              Text(t.enterCode, style: t.style(AppTextStyles.heading1)),
              const SizedBox(height: 8),
              RichText(
                text: TextSpan(
                  style: t.style(AppTextStyles.bodyLarge).copyWith(color: AppColors.textSecondary),
                  children: [
                    TextSpan(text: '${t.sentTo} '),
                    TextSpan(
                      text: '+91 ${widget.phoneNumber}',
                      style: AppTextStyles.bodyLarge.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 36),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(6, _otpBox),
              ),
              if (errorText != null) ...[
                const SizedBox(height: 16),
                Text(errorText, style: t.style(AppTextStyles.body).copyWith(color: AppColors.error)),
              ],
              const SizedBox(height: 32),
              PrimaryButton(
                label: t.verify,
                isLoading: isLoading,
                onPressed: _otp.length == 6 ? _verify : null,
              ),
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: _resendSecondsLeft > 0 ? null : _resend,
                  child: Text(
                    _resendSecondsLeft > 0
                        ? '${t.resend} (${_resendSecondsLeft}s)'
                        : t.resend,
                    style: t.style(AppTextStyles.caption).copyWith(
                      color: _resendSecondsLeft > 0
                          ? AppColors.textHint
                          : AppColors.primary,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _otpBox(int i) {
    return SizedBox(
      width: 48,
      height: 56,
      child: TextField(
        controller: _controllers[i],
        focusNode: _focusNodes[i],
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        cursorColor: AppColors.primary,
        style: AppTextStyles.heading2.copyWith(fontSize: 22),
        decoration: const InputDecoration(counterText: '', contentPadding: EdgeInsets.zero),
        onChanged: (v) => _onChanged(i, v),
      ),
    );
  }
}
