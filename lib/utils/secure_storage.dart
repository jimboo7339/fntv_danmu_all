import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 账号敏感信息（token / 密码）安全存储。
class SecureStore {
  SecureStore._();
  static final SecureStore instance = SecureStore._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  String _key(String accountId, String field) => '$accountId|$field';

  Future<void> writeToken(String accountId, String token) =>
      _storage.write(key: _key(accountId, 'token'), value: token);

  Future<void> writePass(String accountId, String pass) =>
      _storage.write(key: _key(accountId, 'pass'), value: pass);

  Future<String?> readToken(String accountId) =>
      _storage.read(key: _key(accountId, 'token'));

  Future<String?> readPass(String accountId) =>
      _storage.read(key: _key(accountId, 'pass'));

  Future<void> deletePass(String accountId) =>
      _storage.delete(key: _key(accountId, 'pass'));

  Future<void> deleteAccount(String accountId) async {
    await _storage.delete(key: _key(accountId, 'token'));
    await _storage.delete(key: _key(accountId, 'pass'));
  }
}
