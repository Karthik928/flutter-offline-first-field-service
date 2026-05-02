import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:FieldService_app/services/secure_storage_service.dart';
import 'config.dart';
import 'package:flutter/foundation.dart';

/// Lightweight HTTP helper that automatically:
///  • Adds Authorization header if token is saved
///  • Applies timeout from AppConfig
///  • Logs requests in debug mode
class ApiClient {
  /// GET request
  static Future<http.Response> get(
    String path, {
    Map<String, String>? query,
  }) async {
    final uri = AppConfig.uri(path, query);
    final headers = await _headers();
    _log('GET', uri.toString());
    return http.get(uri, headers: headers).timeout(AppConfig.httpTimeout);
  }

  /// POST request with JSON body
  static Future<http.Response> post(
    String path,
    Map<String, dynamic> body, {
    Map<String, String>? query,
  }) async {
    final uri = AppConfig.uri(path, query);
    final headers = await _headers();
    _log('POST', uri.toString(), body);
    return http
        .post(uri, headers: headers, body: jsonEncode(body))
        .timeout(AppConfig.httpTimeout);
  }

  /// PUT request
  static Future<http.Response> put(
    String path,
    Map<String, dynamic> body, {
    Map<String, String>? query,
  }) async {
    final uri = AppConfig.uri(path, query);
    final headers = await _headers();
    _log('PUT', uri.toString(), body);
    return http
        .put(uri, headers: headers, body: jsonEncode(body))
        .timeout(AppConfig.httpTimeout);
  }

  /// Builds unified headers (with Bearer token)
  static Future<Map<String, String>> _headers() async {
    //final prefs = await SharedPreferences.getInstance();
    //final token = prefs.getString('token');
    final token = await SecureStorageService.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  /// Simple debug logger
  static void _log(String method, String url, [dynamic body]) {
    if (kDebugMode) {
      debugPrint('➡️ $method $url');
      if (body != null) debugPrint('Body: ${jsonEncode(body)}');
    }
  }
}
