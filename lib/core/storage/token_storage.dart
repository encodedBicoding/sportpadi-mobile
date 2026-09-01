import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final tokenStorageProvider =
    Provider<TokenStorage>((ref) => TokenStorage(const FlutterSecureStorage()));

/// Thin wrapper over the OS keychain / keystore for the bearer token.
class TokenStorage {
  TokenStorage(this._storage);

  final FlutterSecureStorage _storage;
  static const _key = 'sp_auth_token';

  Future<String?> read() => _storage.read(key: _key);
  Future<void> write(String token) => _storage.write(key: _key, value: token);
  Future<void> clear() => _storage.delete(key: _key);
}
