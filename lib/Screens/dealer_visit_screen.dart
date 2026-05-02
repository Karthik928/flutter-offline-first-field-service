// // lib/screena/dealer_visit_screen.dart
// import 'package:firebase_messaging/firebase_messaging.dart';
// import 'package:flutter/material.dart';
// import 'package:FieldService_app/Screens/products_screen.dart';
// import 'package:FieldService_app/services/notification_api.dart';
// import 'package:url_launcher/url_launcher.dart';
// import 'package:flutter/services.dart'; // Clipboard
// // import 'package:your_app/screena/products_screen.dart'; // <- hook up when ready

// class DealerVisitScreen extends StatefulWidget {
//   final String dealerId;
//   final String dealerName;
//   final String shopName;
//   final String address; // display only
//   final String mobile;

//   /// Coordinates for directions & copy (required by your request)
//   final double latitude;
//   final double longitude;

//   const DealerVisitScreen({
//     super.key,
//     required this.dealerId,
//     required this.dealerName,
//     required this.shopName,
//     required this.address,
//     required this.mobile,
//     required this.latitude,
//     required this.longitude,
//   });

//   @override
//   State<DealerVisitScreen> createState() => _DealerVisitScreenState();
// }

// class _DealerVisitScreenState extends State<DealerVisitScreen>
//     with SingleTickerProviderStateMixin {
//   final Color appGreen = const Color(0xFF2E7D32);

//   late final TabController _tab;
//   DateTime? _commitDate;
//   TimeOfDay? _commitTime;
//   final _amountCtrl = TextEditingController();
//   final _noteCtrl = TextEditingController();
//   final _formKey = GlobalKey<FormState>();
//   bool _saving = false;

//   @override
//   void initState() {
//     super.initState();
//     _tab = TabController(length: 2, vsync: this);
//   }

//   @override
//   void dispose() {
//     _tab.dispose();
//     _amountCtrl.dispose();
//     _noteCtrl.dispose();
//     super.dispose();
//   }

//   // ---------------- Actions: Directions / Call / Copy ----------------

//   /// Always use coordinates (lat,lng) for directions.
//   Uri _webDirectionsUri() => Uri.parse(
//     'https://www.google.com/maps/dir/?api=1&destination=${widget.latitude},${widget.longitude}&travelmode=driving',
//   );

//   /// Always use coordinates for iOS Google Maps deep link.
//   Uri _iosGoogleMapsUri() => Uri.parse(
//     'comgooglemaps://?daddr=${widget.latitude},${widget.longitude}&directionsmode=driving',
//   );

//   Future<void> _openDirections() async {
//     final gmapsUrl = _iosGoogleMapsUri();
//     final webUrl = _webDirectionsUri();

//     if (Theme.of(context).platform == TargetPlatform.iOS &&
//         await canLaunchUrl(gmapsUrl)) {
//       await launchUrl(gmapsUrl, mode: LaunchMode.externalApplication);
//       return;
//     }
//     if (await canLaunchUrl(webUrl)) {
//       await launchUrl(webUrl, mode: LaunchMode.externalApplication);
//     } else {
//       if (!mounted) return;
//       ScaffoldMessenger.of(context).showSnackBar(
//         const SnackBar(
//           content: Text('Could not open Maps'),
//           duration: Duration(seconds: 2),
//         ),
//       );
//     }
//   }

//   Future<void> _callDealer() async {
//     final phone = widget.mobile.trim();
//     if (phone.isEmpty) {
//       if (!mounted) return;
//       ScaffoldMessenger.of(context).showSnackBar(
//         const SnackBar(
//           content: Text('No mobile number found'),
//           duration: Duration(seconds: 2),
//         ),
//       );
//       return;
//     }
//     final uri = Uri(scheme: 'tel', path: phone);
//     if (await canLaunchUrl(uri)) {
//       await launchUrl(uri);
//     } else {
//       if (!mounted) return;
//       ScaffoldMessenger.of(context).showSnackBar(
//         const SnackBar(
//           content: Text('Could not open dialer'),
//           duration: Duration(seconds: 2),
//         ),
//       );
//     }
//   }

//   /// Copy ONLY coordinates (lat, lng) as requested.
//   Future<void> _copyAddress() async {
//     final coords = '${widget.latitude}, ${widget.longitude}';
//     await Clipboard.setData(ClipboardData(text: coords));
//     if (!mounted) return;
//     ScaffoldMessenger.of(context).showSnackBar(
//       const SnackBar(
//         content: Text('Coordinates copied'),
//         duration: Duration(seconds: 2),
//       ),
//     );
//   }

//   // ---------------- Pickers ----------------

//   Future<void> _pickDate() async {
//     final now = DateTime.now();
//     final picked = await showDatePicker(
//       context: context,
//       initialDate: _commitDate ?? now,
//       firstDate: now,
//       lastDate: now.add(const Duration(days: 365 * 3)),
//     );
//     if (picked != null) setState(() => _commitDate = picked);
//   }

//   Future<void> _pickTime() async {
//     final picked = await showTimePicker(
//       context: context,
//       initialTime: _commitTime ?? TimeOfDay.now(),
//     );
//     if (picked != null) setState(() => _commitTime = picked);
//   }

//   // ---------------- Save reminder (your API call lives here) ----------------

//   Future<void> _savePaymentCommitment() async {
//     if (!_formKey.currentState!.validate()) return;

//     if (_commitDate == null || _commitTime == null) {
//       ScaffoldMessenger.of(context).showSnackBar(
//         const SnackBar(
//           content: Text('Pick commitment date & time'),
//           duration: Duration(seconds: 2),
//         ),
//       );
//       return;
//     }

//     // Merge local date + time
//     final localDt = DateTime(
//       _commitDate!.year,
//       _commitDate!.month,
//       _commitDate!.day,
//       _commitTime!.hour,
//       _commitTime!.minute,
//     );

//     // Block past or same-moment times
//     if (!localDt.isAfter(DateTime.now())) {
//       await showDialog<void>(
//         context: context,
//         builder: (ctx) => AlertDialog(
//           title: const Text('Choose a future time'),
//           content: Text(
//             'The selected date & time '
//             '(${_commitDate!.day}/${_commitDate!.month}/${_commitDate!.year} '
//             '${_commitTime!.format(context)}) is in the past.',
//           ),
//           actions: [
//             TextButton(
//               onPressed: () => Navigator.of(ctx).pop(),
//               child: const Text('OK'),
//             ),
//           ],
//         ),
//       );
//       return;
//     }

//     // Helpers for formatting
//     String formatINR(num n) {
//       final isNeg = n < 0;
//       final abs = n.abs();
//       final str = abs.toStringAsFixed(abs % 1 == 0 ? 0 : 2);
//       final parts = str.split('.');
//       var intPart = parts[0];
//       final decPart = parts.length > 1 ? '.${parts[1]}' : '';
//       if (intPart.length > 3) {
//         final last3 = intPart.substring(intPart.length - 3);
//         var rest = intPart.substring(0, intPart.length - 3);
//         final buf = <String>[];
//         while (rest.length > 2) {
//           buf.insert(0, rest.substring(rest.length - 2));
//           rest = rest.substring(0, rest.length - 2);
//         }
//         if (rest.isNotEmpty) buf.insert(0, rest);
//         intPart = '${buf.join(',')},$last3';
//       }
//       return '${isNeg ? '-₹' : '₹'}$intPart$decPart';
//     }

//     String whenLocalText0(DateTime dt) {
//       final d = dt.toLocal();
//       const dayAbbr = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
//       const monAbbr = [
//         'Jan',
//         'Feb',
//         'Mar',
//         'Apr',
//         'May',
//         'Jun',
//         'Jul',
//         'Aug',
//         'Sep',
//         'Oct',
//         'Nov',
//         'Dec',
//       ];
//       final dow = dayAbbr[d.weekday - 1];
//       final mon = monAbbr[d.month - 1];
//       final use24h = MediaQuery.of(context).alwaysUse24HourFormat;
//       final mm = d.minute.toString().padLeft(2, '0');
//       String time;
//       if (use24h) {
//         final hh = d.hour.toString().padLeft(2, '0');
//         time = '$hh:$mm';
//       } else {
//         final isPM = d.hour >= 12;
//         var h12 = d.hour % 12;
//         if (h12 == 0) h12 = 12;
//         time = '$h12:$mm ${isPM ? 'PM' : 'AM'}';
//       }
//       final tzAbbr = d.timeZoneName; // e.g., IST
//       return '$dow, ${d.day} $mon ${d.year}, $time $tzAbbr';
//     }

//     // Convert to UTC ISO (server expects UTC)
//     final sendAtUtc = localDt.toUtc().toIso8601String();

//     // Compose request pieces
//     final amount = num.tryParse(_amountCtrl.text.trim()) ?? 0;
//     final title = 'Payment due — ${widget.dealerName}'; // Set B
//     final note = _noteCtrl.text.trim(); // store as `body`
//     final whenLocalText = whenLocalText0(localDt);
//     final displayBody = [
//       formatINR(amount),
//       if (widget.shopName.trim().isNotEmpty) widget.shopName.trim(),
//       whenLocalText,
//       if (note.isNotEmpty) note,
//     ].join(' · ');

//     setState(() => _saving = true);
//     try {
//       // Ensure FCM token for this device
//       final token = await FirebaseMessaging.instance.getToken();
//       if (token == null || token.isEmpty) {
//         if (!mounted) return;
//         ScaffoldMessenger.of(context).showSnackBar(
//           const SnackBar(
//             content: Text('Unable to get device push token. Try again.'),
//             duration: Duration(seconds: 2),
//           ),
//         );
//         return;
//       }

//       // Call your backend to schedule the push
//       final res = await NotificationsApi.schedule(
//         title: title,
//         dealerName: widget.dealerName,
//         shopName: widget.shopName,
//         amount: amount,
//         mobile: widget.mobile,
//         body: note, // store EXACTLY what user typed
//         fcmToken: token,
//         sendAtUtc: sendAtUtc, // UTC
//         // whenLocalText: whenLocalText,
//         // displayBody: displayBody, // what should appear in push body
//       );

//       if (!mounted) return;
//       if (res.success) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(
//             content: const Text('Reminder saved'),
//             duration: Duration(seconds: 2),
//             behavior: SnackBarBehavior.floating,
//             backgroundColor: appGreen,
//           ),
//         );
//         // Clear controls
//         _amountCtrl.clear();
//         _noteCtrl.clear();
//         setState(() {
//           _commitDate = null;
//           _commitTime = null;
//         });
//       } else {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(
//             content: Text(
//               res.message.isEmpty ? 'Failed to schedule' : res.message,
//             ),
//             duration: Duration(seconds: 2),
//           ),
//         );
//       }
//     } catch (e) {
//       if (!mounted) return;
//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(content: Text('Error: $e'), duration: Duration(seconds: 2)),
//       );
//     } finally {
//       if (mounted) setState(() => _saving = false);
//     }
//   }

//   // ---------------- UI ----------------

//   @override
//   Widget build(BuildContext context) {
//     final subtitle = [
//       if (widget.shopName.trim().isNotEmpty) widget.shopName.trim(),
//       if (widget.mobile.trim().isNotEmpty) widget.mobile.trim(),
//     ].join(' • ');

//     return Scaffold(
//       appBar: AppBar(
//         title: const Text(
//           'Purpose of Visit',
//           style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
//         ),
//         centerTitle: true,
//         backgroundColor: Colors.transparent,
//         elevation: 0,
//         leading: IconButton(
//           icon: const Icon(Icons.arrow_back_sharp, color: Colors.black87),
//           onPressed: () => Navigator.pop(context),
//         ),
//         bottom: TabBar(
//           controller: _tab,
//           labelColor: appGreen,
//           unselectedLabelColor: Colors.grey,
//           indicatorColor: appGreen,
//           tabs: const [
//             Tab(icon: Icon(Icons.event_note), text: 'Payment Purpose'),
//             Tab(
//               icon: Icon(Icons.shopping_cart_outlined),
//               text: 'Order Purpose',
//             ),
//           ],
//         ),
//       ),
//       body: TabBarView(
//         controller: _tab,
//         children: [
//           SingleChildScrollView(
//             padding: const EdgeInsets.all(16),
//             child: Column(
//               children: [
//                 _dealerHeaderCard(subtitle),
//                 const SizedBox(height: 12),
//                 _paymentForm(),
//               ],
//             ),
//           ),
//           SingleChildScrollView(
//             padding: const EdgeInsets.all(16),
//             child: Column(
//               children: [
//                 _dealerHeaderCard(subtitle),
//                 const SizedBox(height: 12),
//                 _orderArea(),
//               ],
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _dealerHeaderCard(String subtitle) {
//     return Container(
//       width: double.infinity,
//       padding: const EdgeInsets.all(14),
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(14),
//         boxShadow: [
//           BoxShadow(
//             color: Colors.black.withValues(alpha: 0.06),
//             blurRadius: 10,
//             offset: const Offset(0, 3),
//           ),
//         ],
//       ),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           // Top row: icon + names
//           Row(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               Container(
//                 width: 44,
//                 height: 44,
//                 decoration: BoxDecoration(
//                   color: appGreen.withValues(alpha: 0.1),
//                   borderRadius: BorderRadius.circular(12),
//                 ),
//                 alignment: Alignment.center,
//                 child: Icon(Icons.store_rounded, color: appGreen),
//               ),
//               const SizedBox(width: 12),
//               Expanded(
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     Text(
//                       widget.dealerName,
//                       style: const TextStyle(
//                         fontWeight: FontWeight.w800,
//                         fontSize: 16,
//                       ),
//                       maxLines: 1,
//                       overflow: TextOverflow.ellipsis,
//                     ),
//                     if (subtitle.isNotEmpty)
//                       Text(
//                         subtitle,
//                         style: const TextStyle(
//                           color: Colors.black54,
//                           fontSize: 12.5,
//                         ),
//                         maxLines: 1,
//                         overflow: TextOverflow.ellipsis,
//                       ),
//                   ],
//                 ),
//               ),
//             ],
//           ),

//           const SizedBox(height: 10),

//           // Address (display only) + always show numeric coords line
//           Row(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               Icon(Icons.place, size: 18, color: Colors.grey[600]),
//               const SizedBox(width: 6),
//               Expanded(
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     if (widget.address.trim().isNotEmpty)
//                       Text(
//                         widget.address,
//                         style: const TextStyle(color: Colors.black87),
//                         maxLines: 3,
//                         overflow: TextOverflow.ellipsis,
//                       ),
//                     const SizedBox(height: 4),
//                     Text(
//                       '(${widget.latitude}, ${widget.longitude})',
//                       style: const TextStyle(
//                         color: Colors.black54,
//                         fontSize: 12.5,
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//             ],
//           ),

//           const SizedBox(height: 12),

//           // Actions — single line, scrollable:
//           // 1) Get directions (text+icon)
//           // 2) Call (text+icon)
//           // 3) Copy (icon ONLY)
//           SingleChildScrollView(
//             scrollDirection: Axis.horizontal,
//             child: Row(
//               children: [
//                 ElevatedButton.icon(
//                   onPressed: _openDirections,
//                   style: ElevatedButton.styleFrom(
//                     backgroundColor: appGreen,
//                     foregroundColor: Colors.white,
//                     shape: RoundedRectangleBorder(
//                       borderRadius: BorderRadius.circular(10),
//                     ),
//                   ),
//                   icon: const Icon(Icons.directions_rounded),
//                   label: const Text('Get Directions'),
//                 ),
//                 const SizedBox(width: 8),
//                 OutlinedButton.icon(
//                   onPressed: _callDealer,
//                   style: OutlinedButton.styleFrom(
//                     side: BorderSide(color: appGreen),
//                     foregroundColor: appGreen,
//                     shape: RoundedRectangleBorder(
//                       borderRadius: BorderRadius.circular(10),
//                     ),
//                   ),
//                   icon: const Icon(Icons.call_rounded),
//                   label: const Text('Call'),
//                 ),
//                 const SizedBox(width: 8),
//                 // Icon-only copy button
//                 Tooltip(
//                   message: 'Copy coordinates',
//                   child: InkWell(
//                     borderRadius: BorderRadius.circular(12),
//                     onTap: _copyAddress,
//                     child: Container(
//                       width: 44,
//                       height: 44,
//                       decoration: BoxDecoration(
//                         color: Colors.grey.withValues(alpha: 0.08),
//                         borderRadius: BorderRadius.circular(12),
//                         border: Border.all(
//                           color: Colors.grey.withValues(alpha: 0.15),
//                         ),
//                       ),
//                       alignment: Alignment.center,
//                       child: const Icon(Icons.copy_all_rounded, size: 22),
//                     ),
//                   ),
//                 ),
//               ],
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _paymentForm() {
//     return Form(
//       key: _formKey,
//       child: Column(
//         children: [
//           TextFormField(
//             controller: _amountCtrl,
//             keyboardType: TextInputType.number,
//             decoration: _dec('Amount (₹)'),
//             validator: (v) {
//               final s = (v ?? '').trim();
//               if (s.isEmpty) return 'Amount is required';
//               if (double.tryParse(s) == null) return 'Enter a valid amount';
//               return null;
//             },
//           ),
//           const SizedBox(height: 10),
//           Row(
//             children: [
//               Expanded(
//                 child: OutlinedButton.icon(
//                   onPressed: _pickDate,
//                   icon: const Icon(Icons.calendar_today),
//                   label: Text(
//                     _commitDate == null
//                         ? 'Pick date'
//                         : '${_commitDate!.day}/${_commitDate!.month}/${_commitDate!.year}',
//                   ),
//                 ),
//               ),
//               const SizedBox(width: 8),
//               Expanded(
//                 child: OutlinedButton.icon(
//                   onPressed: _pickTime,
//                   icon: const Icon(Icons.access_time),
//                   label: Text(
//                     _commitTime == null
//                         ? 'Pick time'
//                         : _commitTime!.format(context),
//                   ),
//                 ),
//               ),
//             ],
//           ),
//           const SizedBox(height: 10),
//           TextFormField(
//             controller: _noteCtrl,
//             maxLines: 3,
//             decoration: _dec('Notes (Required)'),
//           ),
//           const SizedBox(height: 16),
//           SizedBox(
//             width: double.infinity,
//             child: ElevatedButton.icon(
//               onPressed: _saving ? null : _savePaymentCommitment,
//               style: ElevatedButton.styleFrom(
//                 backgroundColor: appGreen,
//                 foregroundColor: Colors.white,
//                 shape: RoundedRectangleBorder(
//                   borderRadius: BorderRadius.circular(12),
//                 ),
//                 minimumSize: const Size.fromHeight(48),
//               ),
//               icon: _saving
//                   ? const SizedBox(
//                       height: 18,
//                       width: 18,
//                       child: CircularProgressIndicator(
//                         strokeWidth: 2,
//                         valueColor: AlwaysStoppedAnimation(Colors.white),
//                       ),
//                     )
//                   : const Icon(Icons.save_outlined),
//               label: Text(_saving ? 'Saving...' : 'Save Reminder'),
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   InputDecoration _dec(String label) {
//     return InputDecoration(
//       labelText: label,
//       filled: true,
//       fillColor: Colors.grey.withValues(alpha: 0.06),
//       contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
//       enabledBorder: OutlineInputBorder(
//         borderRadius: BorderRadius.circular(12),
//         borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
//       ),
//       focusedBorder: OutlineInputBorder(
//         borderRadius: BorderRadius.circular(12),
//         borderSide: BorderSide(color: appGreen, width: 1.4),
//       ),
//     );
//   }

//   // Order purpose → "Browse Products"
//   Widget _orderArea() {
//     return Container(
//       width: double.infinity,
//       padding: const EdgeInsets.all(14),
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(14),
//         boxShadow: [
//           BoxShadow(
//             color: Colors.black.withValues(alpha: 0.06),
//             blurRadius: 10,
//             offset: const Offset(0, 3),
//           ),
//         ],
//       ),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           const Text(
//             'Order Purpose',
//             style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
//           ),
//           const SizedBox(height: 8),
//           const Text(
//             'Browse the product catalog, add to cart, and proceed to create an order.',
//             style: TextStyle(color: Colors.black54),
//           ),
//           const SizedBox(height: 12),
//           SizedBox(
//             width: double.infinity,
//             child: OutlinedButton.icon(
//               onPressed: () async {
//                 Navigator.push(
//                   context,
//                   MaterialPageRoute(
//                     builder: (_) => ProductsScreen(dealerId: widget.dealerId, condition: true),
//                   ),
//                 );
//               },
//               icon: const Icon(Icons.shopping_bag_outlined),
//               label: const Text('Browse Products'),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }
