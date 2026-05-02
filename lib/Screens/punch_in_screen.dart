// import 'package:flutter/material.dart';
// import 'package:FieldService_app/screena/main_page.dart';
// import 'package:connectivity_plus/connectivity_plus.dart';
// import 'package:app_settings/app_settings.dart';

// import 'package:http/http.dart' as http;

// //import 'package:FieldService_app/screena/trip_screen.dart';

// class PunchInScreen extends StatefulWidget {
//   const PunchInScreen({super.key});

//   @override
//   State<PunchInScreen> createState() => _PunchInScreenState();
// }

// class _PunchInScreenState extends State<PunchInScreen>
//     with TickerProviderStateMixin {
//   bool _isPunching = false;
//   late AnimationController _fadeController;
//   late AnimationController _pulseController;
//   late AnimationController _slideController;
//   late Animation<double> _fadeAnimation;
//   late Animation<double> _pulseAnimation;
//   late Animation<Offset> _slideAnimation;

//   @override
//   void initState() {
//     super.initState();
//     _fadeController = AnimationController(
//       duration: const Duration(milliseconds: 1500),
//       vsync: this,
//     );
//     _pulseController = AnimationController(
//       duration: const Duration(milliseconds: 1000),
//       vsync: this,
//     );
//     _slideController = AnimationController(
//       duration: const Duration(milliseconds: 1200),
//       vsync: this,
//     );

//     _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
//       CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
//     );
//     _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
//       CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
//     );
//     _slideAnimation =
//         Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
//           CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
//         );

//     _fadeController.forward();
//     _pulseController.repeat(reverse: true);
//     _slideController.forward();
//   }

//   @override
//   void dispose() {
//     _fadeController.dispose();
//     _pulseController.dispose();
//     _slideController.dispose();
//     super.dispose();
//   }

//   Future<bool> _hasInternet() async {
//     final connectivityResult = await Connectivity().checkConnectivity();

//     if (connectivityResult == ConnectivityResult.none) {
//       return false; // No WiFi or mobile
//     }

//     // Optional: do a real internet check
//     try {
//       final result = await http
//           .get(Uri.parse("https://www.google.com"))
//           .timeout(const Duration(seconds: 5));
//       return result.statusCode == 200;
//     } catch (_) {
//       return false;
//     }
//   }

//   Future<void> _showNoInternetDialog() async {
//     showDialog(
//       context: context,
//       barrierDismissible: false, // user must tap a button
//       builder: (BuildContext context) {
//         return Dialog(
//           shape: RoundedRectangleBorder(
//             borderRadius: BorderRadius.circular(20),
//           ),
//           insetPadding: const EdgeInsets.symmetric(
//             horizontal: 40,
//             vertical: 24,
//           ),
//           child: Container(
//             padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
//             decoration: BoxDecoration(
//               color: Colors.white,
//               borderRadius: BorderRadius.circular(20),
//               boxShadow: [
//                 BoxShadow(
//                   color: Colors.black.withValues(alpha:  0.1),
//                   blurRadius: 20,
//                   offset: const Offset(0, 8),
//                 ),
//               ],
//             ),
//             child: Column(
//               mainAxisSize: MainAxisSize.min,
//               children: [
//                 const Icon(
//                   Icons.signal_cellular_connected_no_internet_4_bar,
//                   size: 50,
//                   color: Colors.redAccent,
//                 ),
//                 const SizedBox(height: 16),
//                 const Text(
//                   "No Internet Connection",
//                   textAlign: TextAlign.center,
//                   style: TextStyle(
//                     fontSize: 20,
//                     fontWeight: FontWeight.w600,
//                     color: Colors.black87,
//                   ),
//                 ),
//                 const SizedBox(height: 12),
//                 const Text(
//                   "You are offline. Please enable mobile data or Wi-Fi to continue.",
//                   textAlign: TextAlign.center,
//                   style: TextStyle(
//                     fontSize: 15,
//                     color: Colors.black54,
//                     height: 1.4,
//                   ),
//                 ),
//                 const SizedBox(height: 24),
//                 Row(
//                   mainAxisAlignment: MainAxisAlignment.spaceEvenly,
//                   children: [
//                     Expanded(
//                       child: TextButton(
//                         onPressed: () => Navigator.of(context).pop(),
//                         style: TextButton.styleFrom(
//                           padding: const EdgeInsets.symmetric(vertical: 14),
//                           shape: RoundedRectangleBorder(
//                             borderRadius: BorderRadius.circular(14),
//                           ),
//                           backgroundColor: Colors.grey.shade200,
//                         ),
//                         child: const Text(
//                           "OK",
//                           style: TextStyle(
//                             fontSize: 16,
//                             color: Colors.black87,
//                             fontWeight: FontWeight.w600,
//                           ),
//                         ),
//                       ),
//                     ),
//                     const SizedBox(width: 12),
//                     Expanded(
//                       child: TextButton(
//                         onPressed: () {
//                           Navigator.of(context).pop();
//                           AppSettings.openAppSettings(
//                             type: AppSettingsType.wifi, // Opens WiFi settings
//                           );
//                         },
//                         style: TextButton.styleFrom(
//                           padding: const EdgeInsets.symmetric(vertical: 14),
//                           shape: RoundedRectangleBorder(
//                             borderRadius: BorderRadius.circular(14),
//                           ),
//                           backgroundColor: const Color(0xFF4CAF50),
//                         ),
//                         child: const Text(
//                           "Settings",
//                           style: TextStyle(
//                             fontSize: 16,
//                             color: Colors.white,
//                             fontWeight: FontWeight.w600,
//                           ),
//                         ),
//                       ),
//                     ),
//                   ],
//                 ),
//               ],
//             ),
//           ),
//         );
//       },
//     );
//   }

//   void _punchIn() async {
//     setState(() {
//       _isPunching = true;
//     });

//     bool online = await _hasInternet();

//     if (!online) {
//       if (mounted) {
//         setState(() {
//           _isPunching = false;
//         });
//         _showNoInternetDialog();
//       }
//       return;
//     }

//     // Simulate punch in process
//     await Future.delayed(const Duration(milliseconds: 1000));

//     if (mounted) {
//       ScaffoldMessenger.of(context).showSnackBar(
//         const SnackBar(
//           content: Text("Punch In Successful! Welcome to work."),
//           duration: Durations.medium1,
//           backgroundColor: Colors.white,
//           behavior: SnackBarBehavior.floating,
//         ),
//       );

//       //Navigator.pushReplacementNamed(context, '/home');
//       Navigator.of(
//         context,
//       ).pushReplacement(MaterialPageRoute(builder: (_) => MainPage()));
//     }
//   }

//   void _punchOut() async {
//     // Simulate punch out process
//     await Future.delayed(const Duration(milliseconds: 1500));

//     if (mounted) {
//       ScaffoldMessenger.of(context).showSnackBar(
//         const SnackBar(
//           content: Text("Punch Out Successful! Have a great day."),
//           duration: Durations.medium1,
//           backgroundColor: Color(0xFF4CAF50),
//           behavior: SnackBarBehavior.floating,
//         ),
//       );

//       //Navigator.pushReplacementNamed(context, '/home');
//       //Navigator.of(context).push(MaterialPageRoute(builder: (_) => TripScreen()));
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: Colors.white,
//       body: Container(
//         height: MediaQuery.of(context).size.height,
//         width: MediaQuery.of(context).size.width,
//         color: Colors.white,
//         child: Stack(
//           children: [
//             // Main content
//             SafeArea(
//               child: SingleChildScrollView(
//                 child: Padding(
//                   padding: const EdgeInsets.symmetric(horizontal: 24),
//                   child: FadeTransition(
//                     opacity: _fadeAnimation,
//                     child: SlideTransition(
//                       position: _slideAnimation,
//                       child: Column(
//                         children: [
//                           const SizedBox(height: 40),
//                           // Header section
//                           _buildHeaderSection(),
//                           const SizedBox(height: 40),
//                           // Status card
//                           _buildStatusCard(),
//                           const SizedBox(height: 30),
//                           // Punch button
//                           _buildPunchButton(),
//                           const SizedBox(height: 30),
//                           // Info cards
//                           _buildInfoCards(),
//                           const SizedBox(height: 30),
//                         ],
//                       ),
//                     ),
//                   ),
//                 ),
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   Widget _buildHeaderSection() {
//     return Column(
//       children: [
//         // Logo container
//         Container(
//           padding: const EdgeInsets.all(24),
//           decoration: BoxDecoration(
//             shape: BoxShape.circle,
//             color: const Color(0xFF4CAF50).withValues(alpha: 0.1),
//             boxShadow: [
//               BoxShadow(
//                 color: const Color(0xFF4CAF50).withValues(alpha: 0.2),
//                 blurRadius: 25,
//                 spreadRadius: 8,
//                 offset: const Offset(0, 10),
//               ),
//             ],
//           ),
//           child: Image.asset(
//             'assets/images/login_logo.png',
//             height: 80,
//             width: 80,
//             errorBuilder: (context, error, stackTrace) {
//               return Container(
//                 height: 80,
//                 width: 80,
//                 decoration: const BoxDecoration(
//                   shape: BoxShape.circle,
//                   color: Color(0xFF4CAF50), // Green color for FieldService logo
//                 ),
//                 child: const Icon(
//                   Icons.business,
//                   size: 40,
//                   color: Colors.white,
//                 ),
//               );
//             },
//           ),
//         ),
//         const SizedBox(height: 1),

//         const SizedBox(height: 1),

//         //const SizedBox(height: 0),
//       ],
//     );
//   }

//   Widget _buildStatusCard() {
//     return Container(
//       padding: const EdgeInsets.all(24),
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(24),
//         border: Border.all(
//           color: const Color(0xFF4CAF50).withValues(alpha: 0.2),
//           width: 1,
//         ),
//         boxShadow: [
//           BoxShadow(
//             color: Colors.black.withValues(alpha: 0.1),
//             blurRadius: 20,
//             spreadRadius: 0,
//             offset: const Offset(0, 10),
//           ),
//         ],
//       ),
            //       child: Column(
            //         children: [
//           Row(
//             children: [
//               Container(
//                 padding: const EdgeInsets.all(12),
//                 decoration: BoxDecoration(
//                   color: const Color(0xFF4CAF50).withValues(alpha: 0.2),
//                   borderRadius: BorderRadius.circular(12),
//                 ),
//                 child: const Icon(
//                   Icons.check_circle,
//                   color: Color(0xFF4CAF50),
//                   size: 24,
//                 ),
//               ),
//               const SizedBox(width: 10),
//               Expanded(
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     const Text(
//                       'Ready to Punch In',
//                       style: TextStyle(
//                         color: Colors.black87,
//                         fontSize: 18,
//                         fontWeight: FontWeight.w700,
//                       ),
//                     ),
//                    const SizedBox(height: 1),
//                     // Text(
//                     //   'You are ready to start your work day',
//                     //   style: TextStyle(
//                     //     color: Colors.black54,
//                     //     fontSize: 14,
//                     //     fontWeight: FontWeight.w400,
//                     //   ),
//                     // ),
//                   ],
//                 ),
//               ),
//             ],
            //           ),
            //         ],
            //       ),
//     );
//   }

//   Widget _buildPunchButton() {
//     return Column(
//       children: [
//         // Punch In Button
//         ScaleTransition(
//           scale: _pulseAnimation,
//           child: Container(
//             width: double.infinity,
//             height: 70,
//             decoration: BoxDecoration(
//               color: const Color.fromARGB(255, 46, 185, 172), // Solid green
//               borderRadius: BorderRadius.circular(20),
//               boxShadow: [
//                 BoxShadow(
//                   color: const Color.fromARGB(255, 76, 170, 175).withValues(alpha: 0.4),
//                   blurRadius: 20,
//                   spreadRadius: 0,
//                   offset: const Offset(0, 8),
//                 ),
//               ],
//             ),
//             child: Material(
//               color: Colors.transparent,
//               child: InkWell(
//                 borderRadius: BorderRadius.circular(20),
//                 onTap: _isPunching ? null : _punchIn,
//                 child: Center(
//                   child: _isPunching
//                       ? const SizedBox(
//                           width: 30,
//                           height: 30,
//                           child: CircularProgressIndicator(
//                             color: Colors.white,
//                             strokeWidth: 3,
//                           ),
//                         )
//                       : Row(
//                           mainAxisAlignment: MainAxisAlignment.center,
//                           children: [
//                             const Icon(
//                               Icons.login,
//                               color: Colors.white,
//                               size: 28,
//                             ),
//                             const SizedBox(width: 12),
//                             const Text(
//                               'Punch In',
//                               style: TextStyle(
//                                 color: Colors.white,
//                                 fontSize: 20,
//                                 fontWeight: FontWeight.w700,
//                                 letterSpacing: 0.5,
//                               ),
//                             ),
//                           ],
//                         ),
//                 ),
//               ),
//             ),
//           ),
//         ),
//         const SizedBox(height: 16),
//         // Punch Out Button
//         Container(
//           width: double.infinity,
//           height: 70,
//           decoration: BoxDecoration(
//             color: Colors.white,
//             borderRadius: BorderRadius.circular(20),
//             border: Border.all(color: const Color(0xFF4CAF50), width: 2),
//             boxShadow: [
//               BoxShadow(
//                 color: const Color(0xFF4CAF50).withValues(alpha: 0.2),
//                 blurRadius: 15,
//                 spreadRadius: 0,
//                 offset: const Offset(0, 5),
//               ),
//             ],
//           ),
//           child: Material(
//             color: Colors.transparent,
//             child: InkWell(
//               borderRadius: BorderRadius.circular(20),
//               onTap: _punchOut,
//               child: Center(
//                 child: Row(
//                   mainAxisAlignment: MainAxisAlignment.center,
//                   children: [
//                     Icon(
//                       Icons.logout,
//                       color: const Color(0xFF4CAF50),
//                       size: 28,
//                     ),
//                     const SizedBox(width: 12),
//                     Text(
//                       'Punch Out',
//                       style: TextStyle(
//                         color: const Color(0xFF4CAF50),
//                         fontSize: 20,
//                         fontWeight: FontWeight.w700,
//                         letterSpacing: 0.5,
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//             ),
//           ),
//         ),
//       ],
//     );
//   }

//   Widget _buildInfoCards() {
//     return Column(
//       children: [
//         // Location tracking card
//         Container(
//           width: double.infinity,
//           padding: const EdgeInsets.all(20),
//           decoration: BoxDecoration(
//             color: Colors.white,
//             borderRadius: BorderRadius.circular(20),
//             border: Border.all(
//               color: const Color(0xFF4CAF50).withValues(alpha: 0.2),
//               width: 1,
//             ),
//             boxShadow: [
//               BoxShadow(
//                 color: const Color(0xFF4CAF50).withValues(alpha: 0.1),
//                 blurRadius: 15,
//                 spreadRadius: 0,
//                 offset: const Offset(0, 8),
//               ),
//             ],
//           ),
//           child: Row(
//             children: [
//               Container(
//                 padding: const EdgeInsets.all(12),
//                 decoration: BoxDecoration(
//                   color: const Color(0xFF4CAF50).withValues(alpha: 0.2),
//                   borderRadius: BorderRadius.circular(12),
//                 ),
//                 child: const Icon(
//                   Icons.location_on,
//                   color: Color(0xFF4CAF50),
//                   size: 24,
//                 ),
//               ),
//               const SizedBox(width: 16),
//               Expanded(
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     const Text(
//                       'Location Tracking Active',
//                       style: TextStyle(
//                         color: Colors.black87,
//                         fontSize: 18,
//                         fontWeight: FontWeight.w700,
//                       ),
//                     ),
//                     const SizedBox(height: 4),
//                     Text(
//                       'Your location is being monitored for attendance tracking',
//                       style: TextStyle(
//                         color: Colors.black54,
//                         fontSize: 14,
//                         height: 1.3,
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//             ],
//           ),
//         ),
//         const SizedBox(height: 2),
//         // Security card
//         // Container(
//         //   width: double.infinity,
//         //   padding: const EdgeInsets.all(20),
//         //   decoration: BoxDecoration(
//         //     color: Colors.white,
//         //     borderRadius: BorderRadius.circular(20),
//         //     border: Border.all(
//         //       color: const Color(0xFF4CAF50).withValues(alpha: 0.2),
//         //       width: 1,
//         //     ),
//             // boxShadow: [
//             //   BoxShadow(
//             //     color: const Color(0xFF4CAF50).withValues(alpha: 0.1),
//             //     blurRadius: 15,
//             //     spreadRadius: 0,
//             //     offset: const Offset(0, 8),
//             //   ),
//             // ],
//        //   ),
//         //),
//       ],
//     );
//   }
// }
