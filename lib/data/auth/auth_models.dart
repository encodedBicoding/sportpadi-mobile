class AuthUser {
  const AuthUser({
    required this.id,
    required this.name,
    required this.email,
    this.image,
    this.emailVerified = false,
  });

  final String id;
  final String name;
  final String email;
  final String? image;

  /// Better Auth `user.emailVerified`. Every account must confirm its address
  /// before it can create, join or buy — the server refuses those calls until
  /// it's true, and the router parks the user on /verify-email.
  final bool emailVerified;

  factory AuthUser.fromJson(Map<String, dynamic> j) => AuthUser(
        id: (j['id'] ?? '') as String,
        name: (j['name'] ?? j['displayName'] ?? '') as String,
        email: (j['email'] ?? '') as String,
        image: (j['image'] ?? j['avatarUrl']) as String?,
        emailVerified: j['emailVerified'] == true,
      );
}

class SessionState {
  const SessionState({this.user});

  final AuthUser? user;
  bool get isAuthenticated => user != null;
  bool get needsEmailVerification => user != null && !user!.emailVerified;

  static const SessionState unauthenticated = SessionState();
}
