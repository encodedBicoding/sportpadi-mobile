class AuthUser {
  const AuthUser({
    required this.id,
    required this.name,
    required this.email,
    this.image,
  });

  final String id;
  final String name;
  final String email;
  final String? image;

  factory AuthUser.fromJson(Map<String, dynamic> j) => AuthUser(
        id: (j['id'] ?? '') as String,
        name: (j['name'] ?? j['displayName'] ?? '') as String,
        email: (j['email'] ?? '') as String,
        image: (j['image'] ?? j['avatarUrl']) as String?,
      );
}

class SessionState {
  const SessionState({this.user});

  final AuthUser? user;
  bool get isAuthenticated => user != null;

  static const SessionState unauthenticated = SessionState();
}
