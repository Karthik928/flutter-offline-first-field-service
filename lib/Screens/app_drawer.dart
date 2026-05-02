import 'package:flutter/material.dart';
//import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive/hive.dart';
//import 'package:http/http.dart' as http;
//import 'package:app_settings/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:FieldService_app/Screens/dealers_screen.dart';
import 'package:FieldService_app/Screens/expenses_list_page.dart';
import 'package:FieldService_app/Screens/failed_records_screen.dart';
import 'package:FieldService_app/Screens/farmer_visit_screen.dart';
import 'package:FieldService_app/Screens/help_support.dart';
import 'package:FieldService_app/Screens/login_screen.dart';
import 'package:FieldService_app/Screens/profile_screen.dart';
import 'package:FieldService_app/Screens/trips.dart';
import 'package:FieldService_app/offline/failed_record_store.dart';
import 'package:FieldService_app/services/attendance_service.dart';

class AppDrawer extends StatefulWidget {
  const AppDrawer({super.key});

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  String? _userName;
  String? _userEmail;

  // Keep your brand color, add complementary accents
  final Color primary = const Color(0xFF1EB89C);
  final Color accent = const Color(0xFF0BA5EC);
  final Color tileBg = const Color(0xFFF7F9FA);

  late FailedRecordStore failedRecordStore; // ← NEW

  // Future<bool> _hasInternet() async {
  //   final List<ConnectivityResult> connectivityResult = await Connectivity()
  //       .checkConnectivity();

  //   if (connectivityResult.contains(ConnectivityResult.none)) {
  //     return false; // No network
  //   }

  //   // Optional: real internet check
  //   try {
  //     final result = await http
  //         .get(Uri.parse("https://www.google.com"))
  //         .timeout(const Duration(seconds: 1));

  //     return result.statusCode == 200;
  //   } catch (_) {
  //     return false;
  //   }
  // }

  // Future<void> _showNoInternetDialog() async {
  //   showDialog(
  //     context: context,
  //     barrierDismissible: false, // user must tap a button
  //     builder: (BuildContext context) {
  //       return Dialog(
  //         shape: RoundedRectangleBorder(
  //           borderRadius: BorderRadius.circular(20),
  //         ),
  //         insetPadding: const EdgeInsets.symmetric(
  //           horizontal: 40,
  //           vertical: 24,
  //         ),
  //         child: Container(
  //           padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
  //           decoration: BoxDecoration(
  //             color: Colors.white,
  //             borderRadius: BorderRadius.circular(20),
  //             boxShadow: [
  //               BoxShadow(
  //                 color: Colors.black.withValues(alpha: 0.1),
  //                 blurRadius: 20,
  //                 offset: const Offset(0, 8),
  //               ),
  //             ],
  //           ),
  //           child: Column(
  //             mainAxisSize: MainAxisSize.min,
  //             children: [
  //               const Icon(
  //                 Icons.signal_cellular_connected_no_internet_4_bar,
  //                 size: 50,
  //                 color: Colors.redAccent,
  //               ),
  //               const SizedBox(height: 16),
  //               const Text(
  //                 "No Internet Connection",
  //                 textAlign: TextAlign.center,
  //                 style: TextStyle(
  //                   fontSize: 20,
  //                   fontWeight: FontWeight.w600,
  //                   color: Colors.black87,
  //                 ),
  //               ),
  //               const SizedBox(height: 12),
  //               const Text(
  //                 "You are offline. Please enable mobile data or Wi-Fi to continue.",
  //                 textAlign: TextAlign.center,
  //                 style: TextStyle(
  //                   fontSize: 15,
  //                   color: Colors.black54,
  //                   height: 1.4,
  //                 ),
  //               ),
  //               const SizedBox(height: 24),
  //               Row(
  //                 mainAxisAlignment: MainAxisAlignment.spaceEvenly,
  //                 children: [
  //                   Expanded(
  //                     child: TextButton(
  //                       onPressed: () => Navigator.of(context).pop(),
  //                       style: TextButton.styleFrom(
  //                         padding: const EdgeInsets.symmetric(vertical: 14),
  //                         shape: RoundedRectangleBorder(
  //                           borderRadius: BorderRadius.circular(14),
  //                         ),
  //                         backgroundColor: Colors.grey.shade200,
  //                       ),
  //                       child: const Text(
  //                         "OK",
  //                         style: TextStyle(
  //                           fontSize: 16,
  //                           color: Colors.black87,
  //                           fontWeight: FontWeight.w600,
  //                         ),
  //                       ),
  //                     ),
  //                   ),
  //                   const SizedBox(width: 12),
  //                   Expanded(
  //                     child: TextButton(
  //                       onPressed: () {
  //                         Navigator.of(context).pop();
  //                         AppSettings.openAppSettings(
  //                           type: AppSettingsType.wifi, // Opens WiFi settings
  //                         );
  //                       },
  //                       style: TextButton.styleFrom(
  //                         padding: const EdgeInsets.symmetric(vertical: 14),
  //                         shape: RoundedRectangleBorder(
  //                           borderRadius: BorderRadius.circular(14),
  //                         ),
  //                         backgroundColor: const Color(0xFF4CAF50),
  //                       ),
  //                       child: const Text(
  //                         "Settings",
  //                         style: TextStyle(
  //                           fontSize: 16,
  //                           color: Colors.white,
  //                           fontWeight: FontWeight.w600,
  //                         ),
  //                       ),
  //                     ),
  //                   ),
  //                 ],
  //               ),
  //             ],
  //           ),
  //         ),
  //       );
  //     },
  //   );
  // }

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();

    setState(() {
      final firstName = prefs.getString('firstName') ?? '';
      final lastName = prefs.getString('lastName') ?? '';
      _userName = ('$firstName $lastName').trim().isEmpty
          ? 'User'
          : ('$firstName $lastName').trim();

      _userEmail = prefs.getString('userEmail') ?? '';
    });

    debugPrint("✅ Loaded user data → Name: $_userName, Email: $_userEmail");
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final frs = FailedRecordStore(); // ← NEW
    final divider = Divider(
      height: 28,
      thickness: 1,
      indent: 16,
      endIndent: 16,
      color: isDark ? Colors.white12 : Colors.black12,
    );

    return Drawer(
      width: 300,
      backgroundColor: const Color(0xFFF5F5F5), // Gray background
      child: SafeArea(
        child: Column(
          children: [
            Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                splashColor: Colors.white24,
                highlightColor: Colors.white10,
                onTap: () {
                  Navigator.of(context).pop(); // close drawer

                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ProfileScreen()),
                  );
                },

                child: _HeaderCard(
                  name: _userName ?? 'Loading...',
                  email: _userEmail ?? '',
                  primary: primary,
                  accent: accent,
                  showArrow: true,
                ),
              ),
            ),

            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _SectionLabel(text: 'Main'),
                  // _menuTile(
                  //   icon: Icons.home_outlined,
                  //   title: 'Home',
                  //   onTap: () => _navigateTo(context, const HomeDashboard()),
                  // ),
                  //   _menuTile(
                  //   icon: Icons.location_on_outlined,
                  //   title: 'punch',
                  //   onTap: () async => await _navigateTo(context, const PunchInScreen()),
                  // ),
                  _menuTile(
                    icon: Icons.location_on_outlined,
                    title: 'Trip Logs',
                    onTap: () async =>
                        await _navigateTo(context, const Trips()),
                  ),
                  // _menuTile(
                  //   icon: Icons.production_quantity_limits_outlined,
                  //   title: 'My Orders',
                  //   onTap: () async => await _navigateTo(
                  //     context,
                  //     const OrderDetailsScreen(condition: false),
                  //   ),
                  // ),
                  // _menuTile(
                  //   icon: Icons.agriculture_outlined,
                  //   title: 'Farmers',
                  //   onTap: () async => await _navigateTo(context, const FarmerTicketScreen()),
                  // ),
                  //divider,
                  // const _SectionLabel(text: 'Operations'),
                  // _menuTile(
                  //   icon: Icons.store_mall_directory_outlined,
                  //   title: 'Dealers',
                  //   onTap: () async => await _navigateTo(
                  //     context,
                  //     const DealersScreen(display: false),
                  //   ),
                  // ),

                  // _menuTile(
                  //   icon: Icons.people,
                  //   title: 'Farmers',
                  //   onTap: () async => await _navigateTo(
                  //     context,
                  //     const FarmerVisitScreen(display: false),
                  //   ),
                  // ),
                  _menuTile(
                    icon: Icons.confirmation_number_outlined,
                    title: 'Expenses Status',
                    onTap: () async =>
                        await _navigateTo(context, const ExpensesListPage()),
                  ),

                  // _menuTile(
                  //   icon: Icons.pie_chart_outline_rounded,
                  //   title: 'Reports',
                  //   onTap: () async => await _navigateTo(context, const ReportsScreen()),
                  //   trailing: _Badge(text: 'New'),
                  // ),
                  divider,
                  const _SectionLabel(text: 'Support'),
                  _menuTile(
                    icon: Icons.pie_chart_outline_rounded,
                    title: 'Failed Sync Records',
                    onTap: () async => await _navigateTo(
                      context,
                      FailedRecordsScreen(store: frs),
                    ),
                    //trailing: _Badge(text: 'New'),
                  ),
                  _menuTile(
                    icon: Icons.help_outline,
                    title: 'Help & Support',
                    onTap: () async =>
                        await _navigateTo(context, const HelpSupport()),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
            // Footer: version + logout
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Text(
                  //   'App v1.0.0',
                  //   textAlign: TextAlign.center,
                  //   style: TextStyle(
                  //     fontSize: 12,
                  //     color: isDark ? Colors.white54 : Colors.black45,
                  //     fontWeight: FontWeight.w600,
                  //   ),
                  // ),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: () async => await _logout(),
                    icon: const Icon(Icons.logout),
                    label: const Text('Logout'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- Modern tile (soft card + icon capsule) ----
  Widget _menuTile({
    required IconData icon,
    required String title,
    Widget? trailing,
    required Future<void> Function() onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          // Ensure any focused input is unfocused so keyboard hides
          FocusScope.of(context).unfocus();
          FocusManager.instance.primaryFocus?.unfocus();

          Navigator.pop(context); // close drawer
          await Future.delayed(
            const Duration(milliseconds: 100),
          ); // Small delay
          await onTap();
        },
        child: Ink(
          // decoration: BoxDecoration(
          //   color: tileBg,
          //   borderRadius: BorderRadius.circular(14),
          //   border: Border.all(color: Colors.black12.withValues(alpha: 0.05)),
          // ),
          child: ListTile(
            leading: _IconCapsule(icon: icon, color: primary),
            title: Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                letterSpacing: .2,
              ),
            ),
            trailing:
                trailing ??
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
                  color: Colors.grey,
                ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 2,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _navigateTo(BuildContext context, Widget screen) async {
    // Navigate directly without internet check
    if (mounted) {
      try {
        await Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => screen));
      } catch (e) {
        // Handle any navigation errors
        debugPrint('Navigation error: $e');
      }
    }
  }

  Future<bool> _isOnDutyToday() async {
    try {
      return await AttendanceService.isOnDutyCachedForToday();
    } catch (e) {
      debugPrint('[AppDrawer] _isOnDutyToday: error checking duty state: $e');
      return false;
    }
  }

  Future<void> _logout() async {
    final onDuty = await _isOnDutyToday();
    if (onDuty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'You cannot logout while you are ON DUTY. Please check out first.',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(top: 16, left: 12, right: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }

    // Use Hive-based helper to determine if a trip is active
    final tripActive = await _isTripActive();

    if (tripActive) {
      // Show top floating snackbar (blocked)
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            "You cannot logout while a trip is active.",
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(top: 16, left: 12, right: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }
    if (!mounted) return;
    // No trip active → show normal confirmation dialog
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Color.fromARGB(255, 255, 255, 255),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: const Color(0xFF1AB69C).withValues(alpha: 0.5),
              width: 1,
            ),
          ),

          title: const Text(
            'Logout',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          content: const Text(
            'Are you sure you want to logout?',
            style: TextStyle(color: Colors.black54),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: TextButton.styleFrom(
                backgroundColor: Color(0xFF1AB69C),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Cancel',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(
                backgroundColor: Colors.red.shade600,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Logout',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (shouldLogout == true && mounted) {
      // Clear all cache and session data
      try {
        // Clear SharedPreferences (all keys)
        final prefs = await SharedPreferences.getInstance();
        await prefs.clear();

        // Clear Hive boxes
        try {
          final tripBox = await Hive.openBox('current_trip');
          await tripBox.clear();
          await tripBox.close();
        } catch (e) {
          debugPrint('Error clearing trip box: $e');
        }

        try {
          final userBox = await Hive.openBox('user_data');
          await userBox.clear();
          await userBox.close();
        } catch (e) {
          debugPrint('Error clearing user_data box: $e');
        }

        // Don't close all Hive boxes here. Closing Hive globally causes other
        // parts of the app (which keep Box references) to throw
        // "Box has already closed" when they access their boxes afterward.
        // We already cleared and closed per-box above (tripBox, userBox).
        // await Hive.close(); // <-- removed to avoid closed-box errors

        debugPrint('✅ All cache and session data cleared on logout');
      } catch (e) {
        debugPrint('Error clearing cache: $e');
      }

      if (!mounted) return;
      // Navigate to Login (clearing backstack)
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }
}

/// Returns true when an active trip is present in Hive.
/// Adjust the box name / key / status check if your data shape is different.
Future<bool> _isTripActive() async {
  try {
    // Use the same box name you used in main.dart
    final Box tripBox = await Hive.openBox('current_trip');
    final dynamic active = tripBox.get('active'); // could be Map or null
    if (active == null) return false;

    // Example: active = { 'status': 'started', ... }
    final status = (active is Map && active.containsKey('status'))
        ? active['status']?.toString()
        : null;

    return status == 'started';
  } catch (e) {
    debugPrint('Error checking trip state from Hive: $e');
    // Conservative: treat as active? here we choose to treat as not active to avoid blocking unnecessarily.
    // If you prefer to be conservative and block logout when uncertain, return true instead.
    return false;
  }
}

/// ---------- Header Card (gradient + account) ----------
class _HeaderCard extends StatelessWidget {
  final String name;
  final String email;
  final Color primary;
  final Color accent;
  final bool showArrow;

  const _HeaderCard({
    required this.name,
    required this.email,
    required this.primary,
    required this.accent,
    this.showArrow = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            primary,
            primary.withValues(alpha: 0.85),
            accent.withValues(alpha: 0.65),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: primary.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: Colors.white,
            child: Text(
              _initials(name),
              style: TextStyle(
                color: primary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    letterSpacing: .2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'View profile',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          //const SizedBox(width: 8),
          if (showArrow)
            Icon(
              Icons.chevron_right_rounded,
              color: Colors.white.withValues(alpha: 0.9),
              size: 28,
            ),
        ],
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return 'U';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}

/// ---------- Icon capsule ----------
class _IconCapsule extends StatelessWidget {
  final IconData icon;
  final Color color;
  const _IconCapsule({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color, size: 22),
    );
  }
}

/// ---------- Small badge ----------
class Badge extends StatelessWidget {
  final String text;
  const Badge({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF6FF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE6ECF5)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: Color(0xFF2563EB),
          letterSpacing: .2,
        ),
      ),
    );
  }
}

/// ---------- Tiny section label ----------
class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel({required this.text});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.white54
              : Colors.black54,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}
