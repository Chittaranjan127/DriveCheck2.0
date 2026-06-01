import '../../core/models/user.dart';

/// Auth state machine. Errors carry a code; UI resolves to localized strings.
sealed class AuthState {
  const AuthState();
}

enum AuthErrorCode { numberNotRegistered, wrongOtp, network, generic }

class AuthInitial extends AuthState {
  const AuthInitial();
}

class AuthLoading extends AuthState {
  const AuthLoading();
}

class AuthOtpSending extends AuthState {
  const AuthOtpSending();
}

class AuthOtpSent extends AuthState {
  final String phoneNumber;
  /// Populated only in dev (backend returns it for convenience). Null in prod.
  final String? mockOtp;
  const AuthOtpSent({required this.phoneNumber, this.mockOtp});
}

class AuthVerifying extends AuthState {
  const AuthVerifying();
}

class AuthAuthenticated extends AuthState {
  final User user;
  const AuthAuthenticated({required this.user});

  String get phoneNumber => user.phoneNumber;
}

class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated();
}

class AuthError extends AuthState {
  final AuthErrorCode code;
  final String? message;
  const AuthError(this.code, [this.message]);
}
