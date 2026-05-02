import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:app_settings/app_settings.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:FieldService_app/config.dart';
import 'dart:convert';
import 'dart:async';
import 'package:FieldService_app/api_client.dart';
import 'package:FieldService_app/services/secure_storage_service.dart';

import 'main_page.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _pwdController = TextEditingController();

  bool _isPasswordVisible = false;
  bool _isLoading = false;
  bool _submitted = false;

  late final AnimationController _fadeController;
  late final AnimationController _slideController;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    );
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.20), end: Offset.zero).animate(
          CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
        );

    _fadeController.forward();
    _slideController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    _emailController.dispose();
    _pwdController.dispose();
    super.dispose();
  }

  // ----------------------------- No Internet Dialog -----------------------------
  Future<void> _showNoInternetDialog() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 40,
            vertical: 24,
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.signal_cellular_connected_no_internet_4_bar,
                  size: 50,
                  color: Colors.redAccent,
                ),
                const SizedBox(height: 16),
                const Text(
                  "No Internet Connection",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  "You are offline. Please enable mobile data or Wi-Fi to continue.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.black54,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          backgroundColor: Colors.grey.shade200,
                        ),
                        child: const Text(
                          "OK",
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.black87,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextButton(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          AppSettings.openAppSettings(
                            type: AppSettingsType.wifi,
                          );
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          backgroundColor: const Color(0xFF4CAF50),
                        ),
                        child: const Text(
                          "Settings",
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ----------------------------- Internet check -----------------------------
  Future<bool> _hasInternet() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult.contains(ConnectivityResult.none)) return false;

    final candidates = [
      Uri.tryParse('${AppConfig.apiBase}/healthz'),
      Uri.tryParse(AppConfig.apiBase),
    ].whereType<Uri>().toList();

    for (final uri in candidates) {
      try {
        final resp = await http.get(uri).timeout(const Duration(seconds: 3));
        if (resp.statusCode >= 200 && resp.statusCode < 500) {
          return true;
        }
      } on TimeoutException {
        // try next
      } catch (_) {
        // try next
      }
    }

    // fallback to google
    try {
      final resp = await http
          .get(Uri.parse('https://www.google.com'))
          .timeout(const Duration(seconds: 4));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ----------------------------- UI -----------------------------
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Top mint gradient header
          Container(
            height: size.height * 0.33,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF2EC7A6), Color(0xFF3AC08B)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),

          SafeArea(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: SlideTransition(
                position: _slideAnimation,
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      // push card down so it overlaps the gradient
                      SizedBox(height: size.height * 0.14),

                      // White rounded card (top corners rounded) — logo INSIDE
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.symmetric(horizontal: 18),
                        padding: const EdgeInsets.only(
                          top: 36,
                          left: 20,
                          right: 20,
                          bottom: 30,
                        ),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(42),
                            topRight: Radius.circular(42),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 20,
                              offset: Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            // Pale mint outer circle + inner white disc with logo (inside card)
                            Container(
                              width: 140,
                              height: 140,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFFEAFDF6),
                              ),
                              child: Center(
                                child: Container(
                                  width: 110,
                                  height: 110,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black12,
                                        blurRadius: 18,
                                        offset: Offset(0, 6),
                                      ),
                                    ],
                                  ),
                                  padding: const EdgeInsets.all(14),
                                  child: Image.asset(
                                    'assets/images/login_logo.png',
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(height: 28),

                            // Email label & field
                            const Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Email',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            _buildTextField(
                              controller: _emailController,
                              hint: 'Enter your email',
                              icon: Icons.email_outlined,
                              keyboardType: TextInputType.emailAddress,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please enter your email address';
                                }
                                final pattern = RegExp(
                                  r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                                );
                                if (!pattern.hasMatch(value.trim())) {
                                  return 'Please enter a valid email address';
                                }
                                return null;
                              },
                              textInputAction: TextInputAction.next,
                              onFieldSubmitted: (_) =>
                                  FocusScope.of(context).nextFocus(),
                            ),

                            const SizedBox(height: 18),

                            // Password label & field
                            const Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Password',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            _buildTextField(
                              controller: _pwdController,
                              hint: 'Enter your password',
                              icon: Icons.lock_outline,
                              isPassword: true,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please enter your password';
                                }
                                if (value.length < 6) {
                                  return 'Password must be at least 6 characters';
                                }
                                return null;
                              },
                              textInputAction: TextInputAction.done,
                              onFieldSubmitted: (_) => _attemptLogin(),
                            ),

                            // const SizedBox(height: 8),

                            // // Forget Password (right aligned, subtle)
                            // Align(
                            //   alignment: Alignment.centerRight,
                            //   child: TextButton(
                            //     onPressed: () {
                            //       // keep empty or implement your navigation
                            //     },
                            //     style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(44, 20), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                            //     child: const Text(
                            //       'Forget Password',
                            //       style: TextStyle(color: Color(0xFF3AC08B), fontWeight: FontWeight.w600, fontSize: 12),
                            //     ),
                            //   ),
                            // ),
                            const SizedBox(height: 20),

                            // Log In button
                            Center(child: _buildLoginButton()),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------- Input field builder -----------------------------
  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool isPassword = false,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    TextInputAction? textInputAction,
    void Function(String)? onFieldSubmitted,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: isPassword && !_isPasswordVisible,
      keyboardType: keyboardType,
      validator: validator,
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
      style: const TextStyle(color: Colors.black87, fontSize: 15),
      showCursor: true,
      enableInteractiveSelection: true,
      mouseCursor: SystemMouseCursors.text,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.black38, fontSize: 14),
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: 12.0, right: 8),
          child: Icon(icon, color: const Color(0xFF3AC08B), size: 22),
        ),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 40,
          minHeight: 40,
        ),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                  _isPasswordVisible ? Icons.visibility : Icons.visibility_off,
                  color: const Color(0xFF3AC08B),
                ),
                onPressed: () =>
                    setState(() => _isPasswordVisible = !_isPasswordVisible),
              )
            : null,
        filled: true,
        fillColor: const Color(0xFFEFFAF6),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
      ),
    );
  }

  // ----------------------------- Button -----------------------------
  Widget _buildLoginButton() {
    return Container(
      width: 200,
      height: 48,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF3AC08B), Color(0xFF2EC7A6)],
        ),
        borderRadius: BorderRadius.circular(200),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2EC7A6).withValues(alpha: 0.25),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(200),
          onTap: _isLoading ? null : _attemptLogin,
          child: Center(
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 3,
                    ),
                  )
                : const Text(
                    'Log In',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  // ----------------------------- Network & Login logic (unchanged behavior) -----------------------------
  String _extractErrorMessage(http.Response response) {
    String fallback = 'Login failed (${response.statusCode})';
    if (response.body.isEmpty) return fallback;

    try {
      final dynamic body = jsonDecode(response.body);
      if (body is Map<String, dynamic>) {
        final msg = body['message'];
        if (msg is String && msg.trim().isNotEmpty) return msg;

        final err = body['error'];
        if (err is String && err.trim().isNotEmpty) return err;

        final errors = body['errors'];
        if (errors is List && errors.isNotEmpty) {
          final first = errors.first;
          if (first is String && first.trim().isNotEmpty) return first;
          if (first is Map && first.values.isNotEmpty) {
            final v = first.values.first;
            if (v is List && v.isNotEmpty && v.first is String) {
              return v.first as String;
            }
          }
        } else if (errors is Map && errors.values.isNotEmpty) {
          final v = errors.values.first;
          if (v is List && v.isNotEmpty && v.first is String) {
            return v.first as String;
          }
          if (v is String && v.trim().isNotEmpty) return v;
        }
      }
    } catch (_) {
      // ignore parse error
    }
    return fallback;
  }

  void _attemptLogin() async {
    FocusScope.of(context).unfocus();

    if (!_submitted) setState(() => _submitted = true);
    //if (!_formKey.currentState!.validate()) return;
    if (!mounted) return;
    setState(() => _isLoading = true);
    final hasInternet = await _hasInternet();
    if (!hasInternet) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showNoInternetDialog();
      return;
    }

    //setState(() => _isLoading = true);

    try {
      final loginData = {
        'email': _emailController.text.trim(),
        'password': _pwdController.text.trim(),
      };
      final response = await ApiClient.post(AppConfig.login, loginData);

      if (!mounted) return;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final prefs = await SharedPreferences.getInstance();

        await prefs.setBool('isLoggedIn', true);
        await prefs.setString('userEmail', _emailController.text.trim());

        // save token if available
        final token = body['token'] ?? body['access_token'];
        if (token is String && token.isNotEmpty) {
          //await prefs.setString('token', token);
          await SecureStorageService.saveToken(token);
        }

        bool isZonalManager = false;
        final user = body['data']?['employee'] ?? {};
        if (user is Map) {
          final id = user['_id'];
          final companyId = user['companyId'];
          final firstName = user['firstName'];
          final lastName = user['lastName'];

          if (id is String && id.isNotEmpty) {
            await prefs.setString('userId', id);
          }
          if (companyId is String && companyId.isNotEmpty) {
            await prefs.setString('companyId', companyId);
          }
          if (firstName is String && firstName.isNotEmpty) {
            await prefs.setString('firstName', firstName);
          }
          if (lastName is String && lastName.isNotEmpty) {
            await prefs.setString('lastName', lastName);
          }
          isZonalManager = (user['isZonalManager'] is bool)
              ? user['isZonalManager'] as bool
              : false;
          await prefs.setBool('isZonalManager', isZonalManager);
        }
        if (mounted) {
          ScaffoldMessenger.of(context).clearSnackBars();

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Login successful!'),
              duration: Duration(seconds: 2),
              backgroundColor: Colors.green,
            ),
          );

          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => MainPage(isZonalManager: isZonalManager),
            ),
          );
        }
      } else {
        final errMsg = _extractErrorMessage(response);
        if (mounted) {
          ScaffoldMessenger.of(context).clearSnackBars();

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errMsg),
              duration: const Duration(seconds: 2),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } on TimeoutException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Request timed out'),
          duration: Duration(seconds: 2),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Network error: $e'),
          duration: const Duration(seconds: 2),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
