/// User profile as returned by the backend (`/auth/me`, `/auth/verify-otp`).
class User {
  final String phoneNumber;
  final String? name;
  final String? email;
  final String? preferredLanguage; // english | hindi | telugu | bengali
  final String role; // jockey | admin
  final String status; // active | inactive
  final String? employeeId;
  final String? selfieUrl;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? lastLoginAt;

  const User({
    required this.phoneNumber,
    this.name,
    this.email,
    this.preferredLanguage,
    this.role = 'jockey',
    this.status = 'active',
    this.employeeId,
    this.selfieUrl,
    this.createdAt,
    this.updatedAt,
    this.lastLoginAt,
  });

  /// True once language, name and selfie are all set — used to gate /home.
  bool get hasCompletedProfile =>
      (name?.trim().isNotEmpty ?? false) &&
      (preferredLanguage?.isNotEmpty ?? false) &&
      (selfieUrl?.isNotEmpty ?? false);

  factory User.fromJson(Map<String, dynamic> j) => User(
        phoneNumber: j['phoneNumber'] as String,
        name: j['name'] as String?,
        email: j['email'] as String?,
        preferredLanguage: j['preferredLanguage'] as String?,
        role: j['role'] as String? ?? 'jockey',
        status: j['status'] as String? ?? 'active',
        employeeId: j['employeeId'] as String?,
        selfieUrl: j['selfieUrl'] as String?,
        createdAt: _parseDate(j['createdAt']),
        updatedAt: _parseDate(j['updatedAt']),
        lastLoginAt: _parseDate(j['lastLoginAt']),
      );

  static DateTime? _parseDate(dynamic v) =>
      v is String ? DateTime.tryParse(v) : null;
}
