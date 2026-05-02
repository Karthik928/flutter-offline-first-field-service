// NEW SplashScreen.dart
import 'package:flutter/material.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Top green gradient section
          Container(
            height: size.height * 0.40,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF2EC7A6), Color(0xFF3AC08B)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),

          // White rounded card + logo + loader
          Align(
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // White card with rounded top
                Container(
                  width: size.width * 0.82,
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.10),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Circular mint background
                      Container(
                        width: 150,
                        height: 150,
                        decoration: const BoxDecoration(
                          color: Color(0xFFE6FFF2),
                          shape: BoxShape.circle,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Image.asset(
                            "assets/images/login_logo.png",
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),

                      const SizedBox(height: 40),

                      // KEEP your loader
                      const CircularProgressIndicator(
                        strokeWidth: 3,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Color(0xFF2EC7A6),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Bottom right corner image
          Positioned(
            bottom: 25,
            right: 25,
            child: Image.asset(
              'assets/images/richmindx.png',
              width: 100,
              height: 100,
            ),
          ),
        ],
      ),
    );
  }
}
