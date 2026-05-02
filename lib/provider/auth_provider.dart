// lib/provider/auth_provider.dart

import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:FieldService_app/config.dart';
import 'package:FieldService_app/api_client.dart';
import 'package:FieldService_app/services/secure_storage_service.dart'; // legacy static ApiClient used for login

class AuthState {
  final bool loading;
  final bool isLoggedIn;
  final String? token;
  final String? userId;
  final String? error;

  const AuthState({
    this.loading = false,
    this.isLoggedIn = false,
    this.token,
    this.userId,
    this.error,
  });

  AuthState copyWith({
    bool? loading,
    bool? isLoggedIn,
    String? token,
    String? userId,
    String? error,
  }) {
    return AuthState(
      loading: loading ?? this.loading,
      isLoggedIn: isLoggedIn ?? this.isLoggedIn,
      token: token ?? this.token,
      userId: userId ?? this.userId,
      error: error, // ✅ ALLOW NULL
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(const AuthState()) {
    _restore();
  }

  Future<void> _restore() async {
    state = state.copyWith(loading: true, error: null);
    try {
      final prefs = await SharedPreferences.getInstance();
      final loggedIn = prefs.getBool('isLoggedIn') ?? false;
      //final token = prefs.getString('token');
      final token = await SecureStorageService.getToken();
      final userId = prefs.getString('userId');
      state = state.copyWith(
        loading: false,
        isLoggedIn: loggedIn,
        token: token,
        userId: userId,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<void> login(String email, String password) async {
    // 🔥 THIS LINE IS THE FIX
    state = state.copyWith(
      loading: true,
      error: null, // <-- CLEAR ERROR FIRST
    );

    try {
      final response = await ApiClient.post(AppConfig.login, {
        'email': email,
        'password': password,
      });

      if (response.statusCode == 200) {
        state = state.copyWith(loading: false, isLoggedIn: true);
      } else {
        state = state.copyWith(
          loading: false,
          error: 'Invalid email or password',
        );
      }
    } catch (e) {
      state = state.copyWith(
        loading: false,
        error: 'Invalid email or password',
      );
    }
  }

  Future<void> logout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } finally {
      state = const AuthState();
    }
  }
}

// Provider
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});
