class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    this.verified = false,
    this.emailVerified = true,
    this.isAdmin = false,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        id: json['id'] as String,
        email: json['email'] as String,
        verified: json['verified'] == true,
        // Servers from before email verification don't send it.
        emailVerified: json['emailVerified'] != false,
        isAdmin: json['isAdmin'] == true,
      );

  final String id;
  final String email;

  /// The admin's manual verification badge.
  final bool verified;

  /// Whether the user proved they own [email]. Until then they can listen
  /// but not upload, share publicly or use the bots.
  final bool emailVerified;
  final bool isAdmin;
}

class AuthSession {
  const AuthSession({required this.token, required this.user});

  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
        token: json['token'] as String,
        user: AuthUser.fromJson(json['user'] as Map<String, dynamic>),
      );

  final String token;
  final AuthUser user;
}
