// import 'package:flutter/material.dart';
// import 'package:connectivity_plus/connectivity_plus.dart';
// import 'package:http/http.dart' as http;

// class ReportsScreen extends StatefulWidget {
//   const ReportsScreen({super.key});

//   @override
//   State<ReportsScreen> createState() => _ReportsScreenState();
// }

// class _ReportsScreenState extends State<ReportsScreen>
//     with TickerProviderStateMixin {
//   late final TabController _tabController;
//   late AnimationController _fadeController;
//   late Animation<double> _fadeAnimation;

//   @override
//   void initState() {
//     super.initState();
//     _tabController = TabController(length: 3, vsync: this, initialIndex: 1);
//     _fadeController = AnimationController(
//       duration: const Duration(milliseconds: 1000),
//       vsync: this,
//     );
//     _fadeAnimation = Tween<double>(
//       begin: 0.0,
//       end: 1.0,
//     ).animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeOut));
//     _fadeController.forward();
//   }

//   @override
//   void dispose() {
//     _tabController.dispose();
//     _fadeController.dispose();
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
//                   color: Colors.black.withValues(alpha: 0.1),
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
//                     const SizedBox(width: 4),
//                     // Expanded(
//                     //   child: TextButton(
//                     //     onPressed: () {
//                     //       Navigator.of(context).pop();
//                     //       AppSettings.openAppSettings(
//                     //         type: AppSettingsType.wifi, // Opens WiFi settings
//                     //       );
//                     //     },
//                     //     style: TextButton.styleFrom(
//                     //       padding: const EdgeInsets.symmetric(vertical: 14),
//                     //       shape: RoundedRectangleBorder(
//                     //         borderRadius: BorderRadius.circular(14),
//                     //       ),
//                     //       backgroundColor: const Color(0xFF4CAF50),
//                     //     ),
//                     //     child: const Text(
//                     //       "Settings",
//                     //       style: TextStyle(
//                     //         fontSize: 16,
//                     //         color: Colors.white,
//                     //         fontWeight: FontWeight.w600,
//                     //       ),
//                     //     ),
//                     //   ),
//                     // ),
//                   ],
//                 ),
//               ],
//             ),
//           ),
//         );
//       },
//     );
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: const Color(0xFFF0F2F5),
//       appBar: AppBar(
//         title: const Text(
//           'Reports',
//           style: TextStyle(
//             fontSize: 20,
//             fontWeight: FontWeight.bold,
//             color: Colors.black,
//           ),
//         ),
//         backgroundColor: const Color(0xFFF3FAF7),
//         elevation: 0,
//         centerTitle: true,
//       ),
//       body: FutureBuilder<bool>(
//         future: _hasInternet(),
//         builder: (context, snapshot) {
//           if (snapshot.connectionState == ConnectionState.waiting) {
//             return const Center(
//               child: CircularProgressIndicator(
//                 valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4CAF50)),
//               ),
//             );
//           }

//           if (snapshot.hasData && !snapshot.data!) {
//             // No internet connection
//             WidgetsBinding.instance.addPostFrameCallback((_) {
//               _showNoInternetDialog();
//             });
//           }

//           return Column(
//             children: [
//               _buildModernTabBar(),
//               Expanded(
//                 child: FadeTransition(
//                   opacity: _fadeAnimation,
//                   child: TabBarView(
//                     controller: _tabController,
//                     children: [
//                       _buildModernReportContent(
//                         farmers: '6',
//                         tickets: '4',
//                         products: '5',
//                         revenue: '₹1,200',
//                         progress: 0.2,
//                         period: 'Today',
//                       ),
//                       _buildModernWeeklyReportContent(
//                         period: 'Weekly',
//                         weekRange: '21 - 27 Dec',
//                         weekData: {
//                           '1-6 Dec': {
//                             'farmers': 8,
//                             'tickets': 5,
//                             'products': 9,
//                             'revenue': 1800,
//                           },
//                           '7-13 Dec': {
//                             'farmers': 12,
//                             'tickets': 8,
//                             'products': 14,
//                             'revenue': 2400,
//                           },
//                           '14-20 Dec': {
//                             'farmers': 6,
//                             'tickets': 4,
//                             'products': 7,
//                             'revenue': 1500,
//                           },
//                           '21-27 Dec': {
//                             'farmers': 10,
//                             'tickets': 6,
//                             'products': 11,
//                             'revenue': 2100,
//                           },
//                           '28-31 Dec': {
//                             'farmers': 7,
//                             'tickets': 5,
//                             'products': 8,
//                             'revenue': 1600,
//                           },
//                           '1-6 jan': {
//                             'farmers': 3,
//                             'tickets': 2,
//                             'products': 4,
//                             'revenue': 800,
//                           },
//                           '7-14 jan': {
//                             'farmers': 2,
//                             'tickets': 2,
//                             'products': 1,
//                             'revenue': 400,
//                           },
//                         },
//                       ),
//                       _buildModernMonthlyReportContent(
//                         period: 'Monthly',
//                         monthRange: 'Dec 2024',
//                         monthData: {
//                           'nov': {
//                             'farmers': 45,
//                             'tickets': 28,
//                             'products': 52,
//                             'revenue': 28500,
//                           },
//                           'oct': {
//                             'farmers': 38,
//                             'tickets': 24,
//                             'products': 41,
//                             'revenue': 17200,
//                           },
//                           'dec': {
//                             'farmers': 52,
//                             'tickets': 35,
//                             'products': 58,
//                             'revenue': 29800,
//                           },
//                           'jan': {
//                             'farmers': 45,
//                             'tickets': 33,
//                             'products': 49,
//                             'revenue': 14700,
//                           },
//                         },
//                       ),
//                     ],
//                   ),
//                 ),
//               ),
//             ],
//           );
//         },
//       ),
//     );
//   }

//   Widget _buildModernTabBar() {
//     return Container(
//       margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(20),
//         boxShadow: [
//           BoxShadow(
//             color: Colors.black.withValues(alpha: 0.08),
//             blurRadius: 20,
//             offset: const Offset(0, 8),
//           ),
//         ],
//       ),
//       child: TabBar(
//         controller: _tabController,
//         isScrollable: true,
//         padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
//         indicator: BoxDecoration(
//           gradient: LinearGradient(
//             colors: [const Color(0xFF96CD9E), const Color(0xFF96CD9E)],
//             begin: Alignment.topLeft,
//             end: Alignment.bottomRight,
//           ),
//           borderRadius: BorderRadius.circular(20),
//         ),
//         labelColor: Colors.white,
//         unselectedLabelColor: Colors.grey[600],
//         labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
//         unselectedLabelStyle: const TextStyle(
//           fontWeight: FontWeight.w500,
//           fontSize: 14,
//         ),
//         indicatorSize: TabBarIndicatorSize.tab,
//         tabAlignment: TabAlignment.center,
//         tabs: const [
//           Tab(
//             child: Padding(
//               padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
//               child: Text('Today'),
//             ),
//           ),
//           Tab(
//             child: Padding(
//               padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
//               child: Text('Week'),
//             ),
//           ),
//           Tab(
//             child: Padding(
//               padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
//               child: Text('Month'),
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildModernReportContent({
//     required String farmers,
//     required String tickets,
//     required String products,
//     required String revenue,
//     required double progress,
//     required String period,
//   }) {
//     return SingleChildScrollView(
//       padding: const EdgeInsets.all(12),
//       child: Column(
//         children: [
//           _buildModernSummaryCard(
//             farmers,
//             tickets,
//             products,
//             revenue,
//             progress,
//             period,
//           ),
//           const SizedBox(height: 10),
//           _buildModernProgressCard(progress),
//           // const SizedBox(height: 20),
//           // _buildModernQuickActions(),
//         ],
//       ),
//     );
//   }

//   Widget _buildModernWeeklyReportContent({
//     required String period,
//     required String weekRange,
//     required Map<String, Map<String, int>> weekData,
//   }) {
//     final totalFarmers = weekData.values.fold<int>(
//       0,
//       (sum, data) => sum + data['farmers']!,
//     );
//     final totalTickets = weekData.values.fold<int>(
//       0,
//       (sum, data) => sum + data['tickets']!,
//     );
//     final totalProducts = weekData.values.fold<int>(
//       0,
//       (sum, data) => sum + data['products']!,
//     );
//     final totalRevenue = weekData.values.fold<int>(
//       0,
//       (sum, data) => sum + data['revenue']!,
//     );

//     return SingleChildScrollView(
//       padding: const EdgeInsets.all(12),
//       child: Column(
//         children: [
//           _buildModernPeriodHeader(period, weekRange),
//           const SizedBox(height: 0.5),
//           _buildModernSummaryCard(
//             totalFarmers.toString(),
//             totalTickets.toString(),
//             totalProducts.toString(),
//             '₹${totalRevenue.toString()}',
//             0.7,
//             period,
//           ),
//           const SizedBox(height: 10),
//           _buildModernWeekOverview(weekData),
//         ],
//       ),
//     );
//   }

//   Widget _buildModernMonthlyReportContent({
//     required String period,
//     required String monthRange,
//     required Map<String, Map<String, int>> monthData,
//   }) {
//     final totalFarmers = monthData.values.fold<int>(
//       0,
//       (sum, data) => sum + data['farmers']!,
//     );
//     final totalTickets = monthData.values.fold<int>(
//       0,
//       (sum, data) => sum + data['tickets']!,
//     );
//     final totalProducts = monthData.values.fold<int>(
//       0,
//       (sum, data) => sum + data['products']!,
//     );
//     final totalRevenue = monthData.values.fold<int>(
//       0,
//       (sum, data) => sum + data['revenue']!,
//     );

//     return SingleChildScrollView(
//       padding: const EdgeInsets.all(12),
//       child: Column(
//         children: [
//           _buildModernPeriodHeader(period, monthRange),
//           const SizedBox(height: 5),
//           _buildModernSummaryCard(
//             totalFarmers.toString(),
//             totalTickets.toString(),
//             totalProducts.toString(),
//             '₹${totalRevenue.toString()}',
//             0.8,
//             period,
//           ),
//           const SizedBox(height: 10),
//           _buildModernMonthOverview(monthData),
//         ],
//       ),
//     );
//   }

//   // Modern UI Helper Methods
//   Widget _buildModernSummaryCard(
//     String farmers,
//     String tickets,
//     String products,
//     String revenue,
//     double progress,
//     String period,
//   ) {
//     return Container(
//       padding: const EdgeInsets.all(12),
//       decoration: BoxDecoration(
//         gradient: LinearGradient(
//           colors: [Colors.white, const Color(0xFFF8F9FA)],
//           begin: Alignment.topLeft,
//           end: Alignment.bottomRight,
//         ),
//         borderRadius: BorderRadius.circular(24),
//         boxShadow: [
//           BoxShadow(
//             color: Colors.black.withValues(alpha: 0.08),
//             blurRadius: 20,
//             offset: const Offset(0, 8),
//           ),
//         ],
//       ),
//       child: Column(
//         children: [
//           Row(
//             mainAxisAlignment: MainAxisAlignment.spaceBetween,
//             children: [
//               Text(
//                 period,
//                 style: const TextStyle(
//                   fontSize: 20,
//                   fontWeight: FontWeight.bold,
//                   color: Color(0xFF2C3E50),
//                 ),
//               ),
//             ],
//           ),
//           const SizedBox(height: 8),
//           Row(
//             children: [
//               Expanded(
//                 child: _buildModernStatItem(
//                   'Farmers',
//                   farmers,
//                   Icons.people,
//                   const Color(0xFF3B82F6),
//                 ),
//               ),
//               const SizedBox(width: 8),
//               Expanded(
//                 child: _buildModernStatItem(
//                   'Tickets',
//                   tickets,
//                   Icons.confirmation_number,
//                   const Color(0xFF10B981),
//                 ),
//               ),
//             ],
//           ),
//           const SizedBox(height: 8),
//           Row(
//             children: [
//               Expanded(
//                 child: _buildModernStatItem(
//                   'Products',
//                   products,
//                   Icons.inventory,
//                   const Color(0xFFF59E0B),
//                 ),
//               ),
//               const SizedBox(width: 8),
//               Expanded(
//                 child: _buildModernStatItem(
//                   'Revenue',
//                   revenue,
//                   Icons.currency_rupee,
//                   const Color(0xFFEF4444),
//                 ),
//               ),
//             ],
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildModernStatItem(
//     String label,
//     String value,
//     IconData icon,
//     Color color,
//   ) {
//     return Container(
//       padding: const EdgeInsets.all(8),
//       decoration: BoxDecoration(
//         color: color.withValues(alpha: 0.1),
//         borderRadius: BorderRadius.circular(16),
//         border: Border.all(color: color.withValues(alpha: 0.2)),
//       ),
//       child: Column(
//         children: [
//           Icon(icon, color: color, size: 18),
//           const SizedBox(height: 4),
//           Text(
//             value,
//             style: TextStyle(
//               fontSize: 16,
//               fontWeight: FontWeight.bold,
//               color: color,
//             ),
//           ),
//           const SizedBox(height: 1),
//           Text(
//             label,
//             style: TextStyle(
//               fontSize: 11,
//               color: Colors.grey[600],
//               fontWeight: FontWeight.w500,
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildModernProgressCard(double progress) {
//     return Container(
//       padding: const EdgeInsets.all(16),
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(24),
//         boxShadow: [
//           BoxShadow(
//             color: Colors.black.withValues(alpha: 0.08),
//             blurRadius: 20,
//             offset: const Offset(0, 8),
//           ),
//         ],
//       ),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           const Text(
//             'Performance Progress',
//             style: TextStyle(
//               fontSize: 18,
//               fontWeight: FontWeight.bold,
//               color: Color(0xFF2C3E50),
//             ),
//           ),
//           const SizedBox(height: 10),
//           LinearProgressIndicator(
//             value: progress,
//             backgroundColor: Colors.grey[200],
//             valueColor: AlwaysStoppedAnimation<Color>(
//               progress > 0.7
//                   ? const Color(0xFF10B981)
//                   : progress > 0.4
//                   ? const Color(0xFFF59E0B)
//                   : const Color(0xFFEF4444),
//             ),
//             minHeight: 8,
//           ),
//           const SizedBox(height: 12),
//         ],
//       ),
//     );
//   }

//   Widget _buildModernPeriodHeader(String period, String range) {
//     return const SizedBox.shrink();
//   }

//   Widget _buildModernWeekOverview(Map<String, Map<String, int>> weekData) {
//     return Container(
//       padding: const EdgeInsets.all(16),
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(24),
//         boxShadow: [
//           BoxShadow(
//             color: Colors.black.withValues(alpha: 0.08),
//             blurRadius: 20,
//             offset: const Offset(0, 8),
//           ),
//         ],
//       ),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           const Text(
//             'Weekly Overview',
//             style: TextStyle(
//               fontSize: 18,
//               fontWeight: FontWeight.bold,
//               color: Color(0xFF2C3E50),
//             ),
//           ),
//           const SizedBox(height: 10),
//           ...weekData.entries.map(
//             (entry) => _buildModernWeekItem(entry.key, entry.value),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildModernWeekItem(String week, Map<String, int> data) {
//     return Container(
//       margin: const EdgeInsets.only(bottom: 12),
//       padding: const EdgeInsets.all(16),
//       decoration: BoxDecoration(
//         color: const Color(0xFFF8F9FA),
//         borderRadius: BorderRadius.circular(16),
//         border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
//       ),
//       child: Row(
//         children: [
//           Expanded(
//             flex: 2,
//             child: Text(
//               week,
//               style: const TextStyle(
//                 fontSize: 14,
//                 fontWeight: FontWeight.w600,
//                 color: Color(0xFF2C3E50),
//               ),
//             ),
//           ),
//           Expanded(
//             child: Text(
//               '${data['farmers']} Farmers',
//               style: TextStyle(fontSize: 12, color: Colors.grey[600]),
//               textAlign: TextAlign.center,
//             ),
//           ),
//           Expanded(
//             child: Text(
//               '${data['tickets']} Tickets',
//               style: TextStyle(fontSize: 12, color: Colors.grey[600]),
//               textAlign: TextAlign.center,
//             ),
//           ),
//           Expanded(
//             child: Text(
//               '₹${data['revenue']}',
//               style: const TextStyle(
//                 fontSize: 12,
//                 fontWeight: FontWeight.bold,
//                 color: Color(0xFF2E7D32),
//               ),
//               textAlign: TextAlign.center,
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildModernMonthOverview(Map<String, Map<String, int>> monthData) {
//     return Container(
//       padding: const EdgeInsets.all(16),
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(24),
//         boxShadow: [
//           BoxShadow(
//             color: Colors.black.withValues(alpha: 0.08),
//             blurRadius: 20,
//             offset: const Offset(0, 8),
//           ),
//         ],
//       ),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           const Text(
//             'Monthly Overview',
//             style: TextStyle(
//               fontSize: 18,
//               fontWeight: FontWeight.bold,
//               color: Color(0xFF2C3E50),
//             ),
//           ),
//           const SizedBox(height: 10),
//           ...monthData.entries.map(
//             (entry) => _buildModernMonthItem(entry.key, entry.value),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildModernMonthItem(String month, Map<String, int> data) {
//     return Container(
//       margin: const EdgeInsets.only(bottom: 12),
//       padding: const EdgeInsets.all(16),
//       decoration: BoxDecoration(
//         color: const Color(0xFFF8F9FA),
//         borderRadius: BorderRadius.circular(16),
//         border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
//       ),
//       child: Row(
//         children: [
//           Expanded(
//             flex: 2,
//             child: Text(
//               month.toUpperCase(),
//               style: const TextStyle(
//                 fontSize: 14,
//                 fontWeight: FontWeight.w600,
//                 color: Color(0xFF2C3E50),
//               ),
//             ),
//           ),
//           Expanded(
//             child: Text(
//               '${data['farmers']}',
//               style: TextStyle(fontSize: 12, color: Colors.grey[600]),
//               textAlign: TextAlign.center,
//             ),
//           ),
//           Expanded(
//             child: Text(
//               '${data['tickets']}',
//               style: TextStyle(fontSize: 12, color: Colors.grey[600]),
//               textAlign: TextAlign.center,
//             ),
//           ),
//           Expanded(
//             child: Text(
//               '₹${data['revenue']}',
//               style: const TextStyle(
//                 fontSize: 12,
//                 fontWeight: FontWeight.bold,
//                 color: Color(0xFF2E7D32),
//               ),
//               textAlign: TextAlign.center,
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }
