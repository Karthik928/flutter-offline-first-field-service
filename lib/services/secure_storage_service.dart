import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  static const _storage = FlutterSecureStorage();

  static const String _tokenKey = "auth_token";
  static const String _attendanceIdKey = "attendance_id";

  /// Save token
  static Future<void> saveToken(String token) async {
    await _storage.write(key: _tokenKey, value: token);
  }

  /// Read token
  static Future<String?> getToken() async {
    return await _storage.read(key: _tokenKey);
  }

  /// Save attendance ID securely
  static Future<void> saveAttendanceId(String attendanceId) async {
    await _storage.write(key: _attendanceIdKey, value: attendanceId);
  }

  /// Read stored attendance ID
  static Future<String?> getAttendanceId() async {
    return await _storage.read(key: _attendanceIdKey);
  }

  /// Delete attendance ID
  static Future<void> deleteAttendanceId() async {
    await _storage.delete(key: _attendanceIdKey);
  }

  /// Delete token (logout)
  static Future<void> deleteToken() async {
    await _storage.delete(key: _tokenKey);
  }

  /// Clear all secure storage
  static Future<void> clearAll() async {
    await _storage.deleteAll();
  }
}
