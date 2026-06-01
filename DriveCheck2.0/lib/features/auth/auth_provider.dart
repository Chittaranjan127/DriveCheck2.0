import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/auth_service.dart';
import '../../core/services/auth_token_holder.dart';
import '../../core/services/language_service.dart';
import 'auth_state.dart';

/// Auth notifier backed by the DriveCheck backend (`/auth/*`).
/// Session = JWT in [AuthTokenHolder]; restored on app start by hitting `/auth/me`.
class AuthNotifier extends Notifier<AuthState> {
  late final AuthService _auth;

  @override
  AuthState build() {
    _auth = AuthService();
    // Defer to a microtask so state mutations in _restore() happen
    // AFTER build() returns. Setting state during build is a no-op
    // in Riverpod 2 and would leave us pinned at AuthLoading.
    Future.microtask(_restore);
    return const AuthLoading();
  }

  Future<void> _restore() async {
    final token = AuthTokenHolder.instance.current;
    debugPrint('[auth] restore start, hasToken=${token != null && token.isNotEmpty}');

    // No token → straight to login.
    if (token == null || token.isEmpty) {
      state = const AuthUnauthenticated();
      return;
    }

    // Token present → validate with /auth/me. On success go to the next
    // page; on any failure go to login. Clear the local token on 401 so
    // we don't keep retrying a known-bad session.
    try {
      final user = await _auth.getMe();
      debugPrint('[auth] restore ok: ${user.phoneNumber}');
      state = AuthAuthenticated(user: user);
    } on AuthException catch (e) {
      debugPrint('[auth] restore failed: $e');
      if (e.code == AuthErrorKind.unauthorized) {
        await AuthTokenHolder.instance.clear();
      }
      state = const AuthUnauthenticated();
    }
  }

  Future<void> sendOtp(String phoneNumber) async {
    state = const AuthOtpSending();
    try {
      final res = await _auth.requestOtp(phoneNumber);
      state = AuthOtpSent(phoneNumber: phoneNumber, mockOtp: res.mockOtp);
    } on AuthException catch (e) {
      state = AuthError(_mapKind(e.code), e.message);
    }
  }

  Future<void> verifyOtp(String otp) async {
    final current = state;
    if (current is! AuthOtpSent) return;
    state = const AuthVerifying();
    try {
      final res = await _auth.verifyOtp(
        current.phoneNumber,
        otp,
        deviceInfo: _deviceInfo(),
      );
      await AuthTokenHolder.instance.set(res.token);
      state = AuthAuthenticated(user: res.user);
    } on AuthException catch (e) {
      final code = e.code == AuthErrorKind.unauthorized
          ? AuthErrorCode.wrongOtp
          : _mapKind(e.code);
      state = AuthError(code, e.message);
    }
  }

  Map<String, dynamic> _deviceInfo() => {
        'platform': Platform.isIOS ? 'ios' : 'android',
        'appVersion': '1.0.0',
      };

  /// Refresh the cached user (call after PATCH /auth/me).
  Future<void> refreshMe() async {
    if (state is! AuthAuthenticated) return;
    try {
      final user = await _auth.getMe();
      state = AuthAuthenticated(user: user);
    } on AuthException {
      // keep current state on transient failure
    }
  }

  void resetError() {
    if (state is AuthError) state = const AuthUnauthenticated();
  }

  Future<void> signOut() async {
    // Best-effort: revoke the session on the backend before nuking the local
    // token. Failure (network, already-revoked, expired token) must NOT block
    // sign-out — the user wants to be logged out either way.
    try {
      await _auth.logout();
    } catch (e) {
      debugPrint('[auth] logout request failed (ignored): $e');
    }
    await AuthTokenHolder.instance.clear();
    // Drop the saved language so the next sign-in starts with the
    // chooser. Jockeys swap devices and hand them off between shifts,
    // and the in-app Hindi/Telugu/Bengali switcher isn't obvious to
    // someone who can't read the previous user's script — forcing the
    // language pick once per login is the safest reset.
    try {
      await ref.read(languageProvider.notifier).clear();
    } catch (e) {
      debugPrint('[auth] language clear failed (ignored): $e');
    }
    state = const AuthUnauthenticated();
  }

  AuthErrorCode _mapKind(AuthErrorKind k) {
    switch (k) {
      case AuthErrorKind.network: return AuthErrorCode.network;
      case AuthErrorKind.badRequest: return AuthErrorCode.numberNotRegistered;
      case AuthErrorKind.unauthorized: return AuthErrorCode.wrongOtp;
      default: return AuthErrorCode.generic;
    }
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);
final authServiceProvider = Provider<AuthService>((_) => AuthService());
