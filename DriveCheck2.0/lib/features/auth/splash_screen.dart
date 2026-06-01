import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/widgets/cars24_wordmark.dart';
import 'auth_provider.dart';
import 'auth_state.dart';
import 'post_auth_route.dart';

/// Splash. Cars24 indigo background, wordmark center, app name beneath.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  // Status copy is intentionally tied to what's actually happening on
  // boot — auth check, AI warm-up, list fetch — rather than generic
  // "Loading…" filler. Keeps the splash from feeling like a stall.
  static const _statusMessages = [
    'Waking up your AI co-pilot…',
    'Checking your sign-in…',
    "Loading today's drives…",
    'Almost on the road…',
  ];
  static const _minSplashDuration = Duration(milliseconds: 600);
  static const _maxSplashDuration = Duration(seconds: 8);

  int _statusIndex = 0;
  Timer? _statusTimer;
  Timer? _deadlineTimer;
  ProviderSubscription<AuthState>? _authSub;
  DateTime? _mountedAt;
  bool _routed = false;

  @override
  void initState() {
    super.initState();
    _mountedAt = DateTime.now();
    _statusTimer = Timer.periodic(const Duration(milliseconds: 1400), (_) {
      if (!mounted) return;
      setState(() => _statusIndex = (_statusIndex + 1) % _statusMessages.length);
    });

    // React to auth becoming non-loading via Riverpod's own subscription
    // mechanism — no polling loop, so the spinner's animation ticker
    // doesn't compete with `Future.delayed(50ms)` microtasks every frame.
    _authSub = ref.listenManual<AuthState>(
      authProvider,
      (_, next) {
        if (!_routed && next is! AuthLoading) _route();
      },
      fireImmediately: true,
    );

    // Hard ceiling: if /auth/me never resolves (API down, no network),
    // bounce to /login with the safer "unauthenticated" guess.
    _deadlineTimer = Timer(_maxSplashDuration, () {
      if (mounted && !_routed) _route();
    });
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _deadlineTimer?.cancel();
    _authSub?.close();
    super.dispose();
  }

  Future<void> _route() async {
    if (_routed || !mounted) return;
    _routed = true;
    _deadlineTimer?.cancel();
    _authSub?.close();
    _authSub = null;

    // Hold on the brand for at least [_minSplashDuration] even if auth
    // resolved instantly — sub-100ms splashes feel like a glitch.
    final elapsed = DateTime.now().difference(_mountedAt!);
    if (elapsed < _minSplashDuration) {
      await Future.delayed(_minSplashDuration - elapsed);
      if (!mounted) return;
    }

    final auth = ref.read(authProvider);
    debugPrint('[splash] resolved, state=${auth.runtimeType}');
    if (auth is! AuthAuthenticated) {
      if (!mounted) return;
      context.go('/login');
      return;
    }
    final dest = await resolvePostAuthRoute(ref);
    if (!mounted) return;
    context.go(dest);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: Stack(
        children: [
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Cars24Wordmark(fontSize: 40, color: AppColors.onPrimary),
                const SizedBox(height: 28),
                Text(
                  AppStrings.appName,
                  style: AppTextStyles.heading2.copyWith(color: AppColors.onPrimary, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                Text(
                  AppStrings.appTaglineEn,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.body.copyWith(
                    color: AppColors.onPrimary.withValues(alpha: 0.85),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  AppStrings.appTaglineHi,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.onPrimary.withValues(alpha: 0.65),
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 48),
                SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppColors.onPrimary.withValues(alpha: 0.85),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.2),
                        end: Offset.zero,
                      ).animate(anim),
                      child: child,
                    ),
                  ),
                  child: Text(
                    _statusMessages[_statusIndex],
                    key: ValueKey(_statusIndex),
                    style: AppTextStyles.body.copyWith(
                      color: AppColors.onPrimary.withValues(alpha: 0.75),
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 32,
            child: Center(
              child: Text(
                AppStrings.poweredBy,
                style: AppTextStyles.caption.copyWith(color: AppColors.onPrimary.withValues(alpha: 0.6)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
