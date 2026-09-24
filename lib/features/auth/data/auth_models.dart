class AuthUser {
  const AuthUser({required this.id, required this.email});

  factory AuthUser.fromJson(Map<String, dynamic> json) =>
      AuthUser(id: json['id'] as String, email: json['email'] as String);

  final String id;
  final String email;
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
