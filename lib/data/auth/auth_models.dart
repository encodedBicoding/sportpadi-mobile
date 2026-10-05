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

/// Settings → Sign-in methods (GET /api/mobile/sign-in-methods).
class SignInMethods {
  const SignInMethods({
    required this.email,
    required this.hasPassword,
    required this.linked,
    required this.available,
    required this.methodCount,
  });

  final String email;

  /// An email + password exists for this account.
  final bool hasPassword;

  /// Linked providers: 'google' / 'apple'.
  final List<String> linked;

  /// Providers this server has keys for (so can link).
  final List<String> available;

  /// Password + links. One must always remain.
  final int methodCount;

  bool get lastOne => methodCount <= 1;

  factory SignInMethods.fromJson(Map<String, dynamic> j) {
    final linked = (j['linked'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => m['provider'] as String? ?? '')
        .where((s) => s.isNotEmpty)
        .toList();
    return SignInMethods(
      email: j['email'] as String? ?? '',
      hasPassword: j['hasPassword'] == true,
      linked: linked,
      available: (j['available'] as List? ?? const [])
          .whereType<String>()
          .toList(),
      methodCount: (j['methodCount'] as num?)?.toInt() ??
          ((j['hasPassword'] == true ? 1 : 0) + linked.length),
    );
  }
}
