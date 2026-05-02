import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';
//import 'package:app_settings/app_settings.dart';
import 'package:FieldService_app/config.dart';
import 'package:FieldService_app/main.dart';
//import '../widgets/custom_app_bar.dart';
//import '../widgets/shared_bottom_nav.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final Color appGreen = const Color(0xFF2E7D32);
  final Color lightGreen = const Color(0xFF4CAF50);
  final Color backgroundColor = const Color(0xFFF5F5F5); // Gray background
  final Color cardBackground = Colors.white; // White body/cards

  // Employee data
  Map<String, dynamic>? employeeData;
  bool isLoading = true;
  String? errorMessage;

  // Future<bool> _hasInternet() async {
  //   final connectivityResult = await Connectivity().checkConnectivity();

  //   if (connectivityResult == ConnectivityResult.none) {
  //     return false; // No WiFi or mobile
  //   }

  //   // Optional: do a real internet check
  //   try {
  //     final result = await http
  //         .get(Uri.parse("https://www.google.com"))
  //         .timeout(const Duration(seconds: 5));
  //     return result.statusCode == 200;
  //   } catch (_) {
  //     return false;
  //   }
  // }

  @override
  void initState() {
    super.initState();
    _fetchEmployeeProfile();
  }

  Future<void> _fetchEmployeeProfile() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final employeeId = prefs.getString('userId') ?? '';
      if (employeeId.isEmpty) {
        setState(() {
          isLoading = false;
          errorMessage = 'User ID not found in preferences';
        });
        return;
      }

      final path = AppConfig.fill('/api/employee/{id}', {'id': employeeId});
      final cacheKey = 'employee:$employeeId';

      final r = await apiClient.getJsonCached(
        path: path,
        cacheKey: cacheKey,
        ttl: const Duration(minutes: 15),
      );

      if (!mounted) return;

      // Expected shapes:
      // { success:true, data:{ employee:{...} } }
      // or sometimes directly { employee:{...} } or raw map.
      Map<String, dynamic>? emp;
      final d = r.data;

      if (d is Map<String, dynamic>) {
        if (d['data'] is Map && (d['data'] as Map)['employee'] is Map) {
          emp = Map<String, dynamic>.from(
            (d['data'] as Map)['employee'] as Map,
          );
        } else if (d['employee'] is Map) {
          emp = Map<String, dynamic>.from(d['employee'] as Map);
        } else {
          // fallback: whole map as profile
          emp = d;
        }
      }

      if (emp != null && emp.isNotEmpty) {
        setState(() {
          employeeData = emp!;
          isLoading = false;
          errorMessage = null;
        });
      } else {
        // If no usable data
        setState(() {
          isLoading = false;
          errorMessage = r.statusCode == 0 && !r.fromCache
              ? 'No internet connection and no cached profile'
              : 'Employee data not found (status: ${r.statusCode})';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        isLoading = false;
        errorMessage = 'Network error: $e';
      });
    }
  }

  Widget _buildBody() {
    if (isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF1AB69C)),
            ),
            SizedBox(height: 16),
            Text(
              'Loading profile...',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    if (errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: Colors.red[400]),
              const SizedBox(height: 16),
              Text(
                'Error Loading Profile',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.red[600],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    isLoading = true;
                    errorMessage = null;
                  });
                  _fetchEmployeeProfile();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(0xFF1AB69C),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Simple Profile Header
          _buildSimpleProfileHeader(),
          const SizedBox(height: 16),

          // Personal Information Card
          _buildSimpleInfoCard('Personal Information', [
            _buildSimpleInfoItem('Email', employeeData?['email'] ?? 'N/A'),
            _buildSimpleInfoItem(
              'Phone',
              employeeData?['contactNumber'] ?? 'N/A',
            ),
            _buildSimpleInfoItem('Address', employeeData?['address'] ?? 'N/A'),
            _buildSimpleInfoItem(
              'Date of Birth',
              employeeData?['dateOfBirth'] != null
                  ? DateTime.parse(
                      employeeData!['dateOfBirth'],
                    ).toLocal().toString().split(' ')[0]
                  : 'N/A',
            ),
            _buildSimpleInfoItem('Gender', employeeData?['gender'] ?? 'N/A'),
            _buildSimpleInfoItem(
              'Blood Group',
              employeeData?['bloodGroup'] ?? 'N/A',
            ),
          ]),
          const SizedBox(height: 12),

          // Work Information Card
          _buildSimpleInfoCard('Work Information', [
            _buildSimpleInfoItem(
              'Employee Code',
              employeeData?['empCode'] ?? 'N/A',
            ),
            _buildSimpleInfoItem(
              'Department',
              employeeData?['department']?['name']?.toString() ?? 'N/A',
            ),

            _buildSimpleInfoItem(
              'Department',
              employeeData?['designation']?['name']?.toString() ?? 'Position',
            ),

            _buildSimpleInfoItem('City', employeeData?['city'] ?? 'N/A'),
            _buildSimpleInfoItem('State', employeeData?['state'] ?? 'N/A'),
            _buildSimpleInfoItem('Country', employeeData?['country'] ?? 'N/A'),
            //_buildSimpleInfoItem('Shift', employeeData?['shift'] ?? 'N/A'),
          ]),
          const SizedBox(height: 12),

          // Bank Information Card
          _buildSimpleInfoCard('Bank Information', [
            _buildSimpleInfoItem(
              'Bank Name',
              employeeData?['bank']?['bankName'] ?? 'N/A',
            ),
            _buildSimpleInfoItem(
              'Account Number',
              maskAccountNumber(employeeData?['bank']?['accountNumber']),
            ),

            _buildSimpleInfoItem(
              'IFSC Code',
              employeeData?['bank']?['ifsc'] ?? 'N/A',
            ),
            _buildSimpleInfoItem(
              'Branch',
              employeeData?['bank']?['branch'] ?? 'N/A',
            ),
          ]),
          // const SizedBox(height: 16),

          // // Logout Button
          // _buildLogoutButton(),
        ],
      ),
    );
  }

  String maskAccountNumber(String? number) {
    if (number == null || number.isEmpty) return 'N/A';

    final clean = number.replaceAll(RegExp(r'\s+'), '');

    if (clean.length <= 4) return clean;

    final last4 = clean.substring(clean.length - 4);
    final masked = 'X' * (clean.length - 4) + last4;

    return masked;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,

      // Modern AppBar with white background
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: Container(
          decoration: const BoxDecoration(
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
            gradient: LinearGradient(
              colors: [
                Color(0xFF52D494), // top gradient color
                Color((0xFF1AB69C)), // bottom gradient color
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: AppBar(
            backgroundColor: Colors.transparent, // must be transparent
            elevation: 0,
            automaticallyImplyLeading: false,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
            ),
            title: const Text(
              'Profile',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
                fontSize: 20,
              ),
            ),
            centerTitle: true,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_sharp, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Color(0xFFFFFFFF).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ],
          ),
        ),
      ),

      body: _buildBody(),

      // Bottom Navigation
      // bottomNavigationBar: BottomNavbar(
      //   selectedMenu: MenuState.ProfileScreen,  onItemSelected: (_) {},
      // ),
    );
  }

  // Simple Profile Header
  Widget _buildSimpleProfileHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBackground,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildProfilePhoto(), // 🔥 REAL IMAGE HERE
          const SizedBox(height: 12),

          Text(
            '${employeeData?['firstName'] ?? ''} ${employeeData?['lastName'] ?? ''}'
                    .trim()
                    .isEmpty
                ? 'Employee Name'
                : '${employeeData?['firstName'] ?? ''} ${employeeData?['lastName'] ?? ''}'
                      .trim(),
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 4),
          Text(
            employeeData?['designation']?['name']?.toString() ?? 'Position',
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  // PROFILE PHOTO
  Widget _buildProfilePhoto() {
    final photo = employeeData?['profilePhoto'];

    if (photo != null && photo.toString().isNotEmpty) {
      final url = AppConfig.imageUrl(photo.toString());

      return ClipRRect(
        borderRadius: BorderRadius.circular(40),
        child: Image.network(
          url,
          width: 80,
          height: 80,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) {
            return Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(40),
              ),
              child: const Icon(Icons.person, size: 40, color: Colors.grey),
            );
          },
        ),
      );
    }

    // Fallback no photo
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(40),
      ),
      child: const Icon(Icons.person, size: 40, color: Colors.grey),
    );
  }

  // Simple Info Card
  Widget _buildSimpleInfoCard(String title, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, Colors.grey[50]!],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: appGreen.withValues(alpha: 0.2), width: 1),
        boxShadow: [
          BoxShadow(
            color: appGreen.withValues(alpha: 0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: RadialGradient(
                // begin: Alignment.topCenter,
                // end: Alignment.bottomCenter,
                center: Alignment(0, 0.5),
                radius: 10,
                colors: [
                  // Color(0xFF6DECA7).withValues(alpha: 0.1),
                  Color(0xFF1AB6A6).withValues(alpha: 0.7),
                  Color(0xFF6DECA7).withValues(alpha: 0.1),
                ],
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,

                //color: appGreen,
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  // Simple Info Item
  Widget _buildSimpleInfoItem(String label, dynamic value) {
    final safeValue = value?.toString() ?? 'N/A';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.grey.withValues(alpha: 0.1), width: 1),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              safeValue,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Logout Button
}

@pragma('vm:entry-point')
void _testCallback() {
  FlutterForegroundTask.setTaskHandler(TestHandler());
}

class TestHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint("🔥 TestHandler started");
  }

  @override
  Future<void> onRepeatEvent(DateTime timestamp) async {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool canceledByUser) async {}

  @override
  void onNotificationPressed() {}
}
