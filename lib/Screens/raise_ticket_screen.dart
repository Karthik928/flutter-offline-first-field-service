// // lib/screena/raise_ticket_screen.dart
// // "Raise a Ticket" with two tabs: Dealer Ticket & Farmer Ticket.
// // ✅ Dealer list (shop name + address shown), single-select dot
// // ✅ Dealer ticket: Remarks REQUIRED; button enabled only when a dealer is selected + remarks entered
// // ✅ Farmer list (name + mobile + location shown), single-select dot
// // ✅ Farmer ticket: strict input blocking (pond name letters/spaces only; pond size 4 digits only; numeric limits),
// //    vibriosis true/false switch, remarks REQUIRED
// // ✅ Uses GET /api/deal/ (fallback /api/dealers/) and GET /api/farm (fallback /api/farmers)
// // ✅ POST /api/dealticket and POST /api/farmticket
// // ✅ Inline top error banners; safe setState + mounted checks

// import 'dart:async';
// import 'dart:convert';
// import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
// import 'package:shared_preferences/shared_preferences.dart';
// import 'package:FieldService_app/config.dart';
// import 'package:FieldService_app/main.dart';
// import 'package:FieldService_app/offline/request_envelope.dart';

// /* ========================= Screen ========================= */

// class RaiseTicketScreen extends StatefulWidget {
//   const RaiseTicketScreen({super.key});

//   @override
//   State<RaiseTicketScreen> createState() => _RaiseTicketScreenState();
// }

// class _RaiseTicketScreenState extends State<RaiseTicketScreen>
//     with SingleTickerProviderStateMixin {
//   final Color appGreen = const Color(0xFF2E7D32);
//   final Color backgroundColor = const Color.fromRGBO(255, 212, 219, 220);

//   late final TabController _tab;

//   @override
//   void initState() {
//     super.initState();
//     _tab = TabController(length: 2, vsync: this);
//   }

//   @override
//   void dispose() {
//     _tab.dispose();
//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: backgroundColor,
//       appBar: AppBar(
//         title: const Text('Raise a Case'),
//         centerTitle: true,
//         bottom: TabBar(
//           controller: _tab,
//           indicatorColor: appGreen,
//           labelColor: appGreen,
//           unselectedLabelColor: Colors.grey[700],
//           tabs: const [
//             Tab(text: 'Dealer Ticket'),
//             Tab(text: 'Farmer Ticket'),
//           ],
//         ),
//       ),
//       body: TabBarView(
//         controller: _tab,
//         children: const [_DealerTicketTab(), _FarmerTicketTab()],
//       ),
//     );
//   }
// }

// /* ========================= Dealer Ticket Tab ========================= */

// class _DealerTicketTab extends StatefulWidget {
//   const _DealerTicketTab();

//   @override
//   State<_DealerTicketTab> createState() => _DealerTicketTabState();
// }

// class _DealerTicketTabState extends State<_DealerTicketTab> {
//   final Color appGreen = const Color(0xFF2E7D32);

//   bool _loading = true;
//   String? _error;
//   String _search = '';
//   List<_DealerLite> _dealers = [];
//   _DealerLite? _selected;

//   // Remarks REQUIRED
//   final _remarksCtrl = TextEditingController();
//   bool _submitting = false;
//   String? _inlineBanner;

//   void _safeSet(void Function() fn) {
//     if (!mounted) return;
//     setState(fn);
//   }

//   @override
//   void initState() {
//     super.initState();
//     _fetchDealers();
//     _remarksCtrl.addListener(() => _safeSet(() {})); // refresh enable state
//   }

//   @override
//   void dispose() {
//     _remarksCtrl.dispose();
//     super.dispose();
//   }

//   Future<void> _fetchDealers() async {
//     _safeSet(() {
//       _loading = true;
//       _error = null;
//     });

//     try {
//       final prefs = await SharedPreferences.getInstance();
//       final employeeId = prefs.getString('userId') ?? '';

//       if (employeeId.isEmpty) {
//         _safeSet(() {
//           _loading = false;
//           _error = 'User ID not found in preferences';
//         });
//         return;
//       }

//       final path = AppConfig.fill('/api/dealers/employee/{id}', {
//         'id': employeeId,
//       });
//       final cacheKey = 'dealers:$employeeId';

//       final r = await apiClient.getJsonCached(
//         path: path,
//         cacheKey: cacheKey,
//         ttl: const Duration(minutes: 10),
//       );

//       // Parse list from either {success, dealers: [...]} or a raw list
//       List listJson = const [];
//       final d = r.data;
//       if (d is Map && d['dealers'] is List) {
//         listJson = d['dealers'] as List;
//       } else if (d is List) {
//         listJson = d;
//       }

//       if (listJson.isNotEmpty) {
//         // Keep only approved dealers (case-insensitive). Try a few common keys.
//         final approvedJson = listJson.where((e) {
//           try {
//             final m = (e as Map<String, dynamic>);
//             final raw =
//                 (m['status'] ?? m['dealerStatus'] ?? m['approvalStatus']);
//             final s = raw?.toString().toLowerCase();
//             return s == 'approved';
//           } catch (_) {
//             return false;
//           }
//         }).toList();

//         if (approvedJson.isNotEmpty) {
//           final list = approvedJson
//               .map<_DealerLite>(
//                 (e) => _DealerLite.fromJson(e as Map<String, dynamic>),
//               )
//               .toList();
//           _safeSet(() => _dealers = list);
//         } else {
//           // No approved dealers found
//           _safeSet(() => _dealers = <_DealerLite>[]);
//         }
//       } else {
//         // If network failed and no cache → show a useful message
//         if (!r.fromCache && r.statusCode != 200) {
//           _safeSet(
//             () => _error = r.statusCode == 0
//                 ? 'Offline and no cached dealers'
//                 : 'Error ${r.statusCode}',
//           );
//         } else {
//           _safeSet(() => _dealers = <_DealerLite>[]);
//         }
//       }
//     } catch (e) {
//       _safeSet(() => _error = 'Network error: $e');
//     } finally {
//       _safeSet(() => _loading = false);
//     }
//   }

//   List<_DealerLite> get _filtered {
//     final q = _search.trim().toLowerCase();
//     if (q.isEmpty) return _dealers;
//     return _dealers.where((d) {
//       return (d.dealerName?.toLowerCase().contains(q) ?? false) ||
//           (d.shopName?.toLowerCase().contains(q) ?? false) ||
//           (d.shopAddress?.toLowerCase().contains(q) ?? false) ||
//           (d.mobile?.toLowerCase().contains(q) ?? false);
//     }).toList();
//   }

//   void _select(_DealerLite d) {
//     _safeSet(() => _selected = (_selected?.id == d.id) ? null : d);
//   }

//   void _errorTop(String msg) => _safeSet(() => _inlineBanner = msg);

//   bool get _canSubmitDealer =>
//       _selected != null && _remarksCtrl.text.trim().isNotEmpty && !_submitting;

//   Future<void> _submitDealerTicket() async {
//     if (!_canSubmitDealer) {
//       _errorTop('Select a dealer and enter remarks to proceed.');
//       return;
//     }

//     _errorTop('');
//     _safeSet(() => _submitting = true);

//     try {
//       final prefs = await SharedPreferences.getInstance();
//       final companyId = prefs.getString('companyId') ?? '';
//       final employeeId = prefs.getString('userId') ?? '';
//       final tripId = prefs.getString('currentTripId') ?? '';
//       final token = prefs.getString('token') ?? '';

//       final d = _selected!;
//       final body = {
//         "companyId": companyId,
//         "dealerId": d.id ?? '',
//         "employeeId": employeeId,
//         if (tripId.isNotEmpty) "tripId": tripId,
//         "dealerName": d.dealerName ?? d.shopName ?? '',
//         "mobileNumber": d.mobile ?? '',
//         "dealerLocation": d.shopAddress ?? '',
//         "remarks": _remarksCtrl.text.trim(),
//       };

//       debugPrint('🧾 [DealerTicket] POST ${AppConfig.dealerTicketsAlt}');
//       debugPrint('🧾 [DealerTicket] body: ${jsonEncode(body)}');

//       final resp = await apiClient.sendOrQueue(
//         method: HttpVerb.post,
//         path: AppConfig.dealerTicketsAlt,
//         jsonBody: body,
//         headers: {'Authorization': 'Bearer $token'},
//         optimisticOk: true, // queued -> treat as success in UI
//       );

//       if (!mounted) return;

//       if (resp == null) {
//         // Offline / retriable server code → queued
//         debugPrint('🟡 [DealerTicket] queued (offline or retriable).');
//         ScaffoldMessenger.of(context).showSnackBar(
//           const SnackBar(
//             content: Text('Queued offline — will sync automatically'),
//             duration: Duration(seconds: 2),
//             behavior: SnackBarBehavior.floating,
//           ),
//         );
//         _safeSet(() {
//           _selected = null;
//           _remarksCtrl.clear();
//         });
//       } else if (resp.statusCode == 200 || resp.statusCode == 201) {
//         debugPrint('✅ [DealerTicket] server OK ${resp.statusCode}');
//         ScaffoldMessenger.of(context).showSnackBar(
//           const SnackBar(
//             content: Text('Dealer ticket raised successfully'),
//             duration: Duration(seconds: 2),
//             behavior: SnackBarBehavior.floating,
//           ),
//         );
//         _safeSet(() {
//           _selected = null;
//           _remarksCtrl.clear();
//         });
//       } else {
//         String msg = 'HTTP ${resp.statusCode}';
//         try {
//           final j = jsonDecode(resp.body);
//           if (j is Map && j['message'] is String) msg = j['message'];
//         } catch (_) {}
//         debugPrint('❌ [DealerTicket] failed: $msg');
//         _errorTop('Failed to raise ticket: $msg');
//       }
//     } catch (e) {
//       debugPrint('💥 [DealerTicket] exception: $e');
//       _errorTop('Network error: $e');
//     } finally {
//       _safeSet(() => _submitting = false);
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     final items = _filtered;

//     return Column(
//       children: [
//         if ((_inlineBanner ?? '').isNotEmpty)
//           _TopBarMessage(
//             message: _inlineBanner!,
//             onClose: () => _safeSet(() => _inlineBanner = null),
//           ),
//         Padding(
//           padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
//           child: _SearchBox(
//             hint: 'Search dealers (name / shop / address / mobile)…',
//             onChanged: (v) => _safeSet(() => _search = v),
//           ),
//         ),
//         Expanded(
//           child: _loading
//               ? const Center(child: CircularProgressIndicator())
//               : (_error != null
//                     ? _ErrorRetry(message: _error!, onRetry: _fetchDealers)
//                     : RefreshIndicator(
//                         onRefresh: _fetchDealers,
//                         child: ListView.separated(
//                           physics: const AlwaysScrollableScrollPhysics(),
//                           padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
//                           itemCount: items.isEmpty ? 1 : items.length,
//                           separatorBuilder: (_, __) =>
//                               const SizedBox(height: 10),
//                           itemBuilder: (_, i) {
//                             if (items.isEmpty) {
//                               return const _EmptyState(
//                                 icon: Icons.store,
//                                 title: 'No dealers found',
//                               );
//                             }
//                             final d = items[i];
//                             final selected = _selected?.id == d.id;
//                             return _DealerTile(
//                               dealer: d,
//                               selected: selected,
//                               onTap: () => _select(d),
//                             );
//                           },
//                         ),
//                       )),
//         ),
//         // Remarks + submit (remarks REQUIRED)
//         Padding(
//           padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
//           child: Column(
//             children: [
//               TextFormField(
//                 controller: _remarksCtrl,
//                 minLines: 2,
//                 maxLines: 4,
//                 decoration: InputDecoration(
//                   labelText: 'Remarks (required)',
//                   filled: true,
//                   fillColor: Colors.grey.withValues(alpha: 0.06),
//                   border: OutlineInputBorder(
//                     borderRadius: BorderRadius.circular(12),
//                   ),
//                 ),
//               ),
//               const SizedBox(height: 12),
//               SizedBox(
//                 width: double.infinity,
//                 child: ElevatedButton(
//                   onPressed: _canSubmitDealer ? _submitDealerTicket : null,
//                   style: ElevatedButton.styleFrom(
//                     backgroundColor: appGreen,
//                     foregroundColor: Colors.white,
//                     minimumSize: const Size(double.infinity, 50),
//                     shape: RoundedRectangleBorder(
//                       borderRadius: BorderRadius.circular(12),
//                     ),
//                   ),
//                   child: _submitting
//                       ? const SizedBox(
//                           height: 20,
//                           width: 20,
//                           child: CircularProgressIndicator(
//                             strokeWidth: 2,
//                             valueColor: AlwaysStoppedAnimation(Colors.white),
//                           ),
//                         )
//                       : const Text(
//                           'Raise Ticket',
//                           style: TextStyle(fontWeight: FontWeight.w700),
//                         ),
//                 ),
//               ),
//             ],
//           ),
//         ),
//       ],
//     );
//   }
// }

// /* ========================= Farmer Ticket Tab ========================= */

// class _FarmerTicketTab extends StatefulWidget {
//   const _FarmerTicketTab();

//   @override
//   State<_FarmerTicketTab> createState() => _FarmerTicketTabState();
// }

// class _FarmerTicketTabState extends State<_FarmerTicketTab> {
//   final Color appGreen = const Color(0xFF2E7D32);

//   // List / search / selection
//   bool _loading = true;
//   String? _error;
//   String _search = '';
//   List<_FarmerLite> _farmers = [];
//   _FarmerLite? _selected;
//   // show red only after first submit

//   // Inline banner error
//   String? _inlineBanner;

//   // Extra form
//   final _formKey = GlobalKey<FormState>();
//   final _farmerNameCtrl = TextEditingController();
//   final _mobileCtrl = TextEditingController();
//   final _locationCtrl = TextEditingController(); // read-only
//   final _pondNameCtrl = TextEditingController();
//   final _pondSizeCtrl = TextEditingController();
//   final _speciesCtrl = TextEditingController();
//   final _phCtrl = TextEditingController();
//   final _ammoniaCtrl = TextEditingController();
//   final _nitriteCtrl = TextEditingController();
//   final _alkalinityCtrl = TextEditingController();
//   final _remarksCtrl = TextEditingController(); // REQUIRED
//   bool _vibriosis = false;
//   bool _submitting = false;

//   // ===== Input formatters (hard block) =====
//   static final List<TextInputFormatter> _lettersOnly = [
//     FilteringTextInputFormatter.allow(RegExp(r"[A-Za-z ]")),
//     LengthLimitingTextInputFormatter(40),
//   ];
//   // Pond Name -> letters/spaces only + helper
//   static final List<TextInputFormatter> _pondNameFmt = [
//     FilteringTextInputFormatter.allow(RegExp(r"[A-Za-z ]")),
//     LengthLimitingTextInputFormatter(40),
//   ];
//   // Pond Size -> digits only, max 4
//   static final List<TextInputFormatter> _pondSizeFmt = [
//     FilteringTextInputFormatter.allow(RegExp(r'^\d{0,4}(\.\d{0,2})?$')),
//   ];

//   // precise regex decimal formatter
//   TextInputFormatter _regexFmt(String pattern) =>
//       _RegexFormatter(RegExp(pattern));
//   // pH up to 2 digits + up to 2 decimals
//   late final _phFmt = _regexFmt(r'^\d{0,2}(\.\d{0,2})?$');
//   // ammonia/nitrite up to 3 digits + up to 2 decimals
//   late final _chemFmt = _regexFmt(r'^\d{0,3}(\.\d{0,2})?$');
//   // alkalinity integers only, up to 4 digits
//   static final List<TextInputFormatter> _alkFmt = [
//     FilteringTextInputFormatter.allow(RegExp(r'^\d{0,4}$')),
//   ];

//   static final List<TextInputFormatter> _lettersAndDigitsOnly = [
//     FilteringTextInputFormatter.allow(RegExp(r"[A-Za-z0-9 ]")),
//     LengthLimitingTextInputFormatter(100),
//   ];

//   @override
//   void initState() {
//     super.initState();
//     _fetchFarmers();
//   }

//   @override
//   void dispose() {
//     _farmerNameCtrl.dispose();
//     _mobileCtrl.dispose();
//     _locationCtrl.dispose();
//     _pondNameCtrl.dispose();
//     _pondSizeCtrl.dispose();
//     _speciesCtrl.dispose();
//     _phCtrl.dispose();
//     _ammoniaCtrl.dispose();
//     _nitriteCtrl.dispose();
//     _alkalinityCtrl.dispose();
//     _remarksCtrl.dispose();
//     super.dispose();
//   }

//   void _safeSet(void Function() fn) {
//     if (!mounted) return;
//     setState(fn);
//   }

//   // ===== Fetch farmers (try /api/farm, fallback /api/farmers) =====
//   Future<void> _fetchFarmers() async {
//     _safeSet(() {
//       _loading = true;
//       _error = null;
//     });

//     try {
//       final prefs = await SharedPreferences.getInstance();
//       final employeeId = prefs.getString('userId') ?? '';

//       if (employeeId.isEmpty) {
//         _safeSet(() {
//           _loading = false;
//           _error = 'User ID not found in preferences';
//         });
//         return;
//       }

//       final path = AppConfig.fill('/api/farmers/employee/{id}', {
//         'id': employeeId,
//       });
//       final cacheKey = 'farmers:$employeeId';

//       final r = await apiClient.getJsonCached(
//         path: path,
//         cacheKey: cacheKey,
//         ttl: const Duration(minutes: 10),
//       );

//       // Parse list from either {farmers: [...]} or a raw list
//       List listJson = const [];
//       final d = r.data;
//       if (d is Map && d['farmers'] is List) {
//         listJson = d['farmers'] as List;
//       } else if (d is List) {
//         listJson = d;
//       }

//       if (listJson.isNotEmpty) {
//         // Keep only approved farmers (case-insensitive). Try a few common keys.
//         final approvedJson = listJson.where((e) {
//           try {
//             final m = (e as Map<String, dynamic>);
//             final raw =
//                 (m['status'] ?? m['farmerStatus'] ?? m['approvalStatus']);
//             final s = raw?.toString().toLowerCase();
//             return s == 'approved';
//           } catch (_) {
//             return false;
//           }
//         }).toList();

//         if (approvedJson.isNotEmpty) {
//           final list = approvedJson
//               .map<_FarmerLite>(
//                 (e) => _FarmerLite.fromJson(e as Map<String, dynamic>),
//               )
//               .toList();
//           _safeSet(() => _farmers = list);
//         } else {
//           // No approved farmers found
//           _safeSet(() => _farmers = <_FarmerLite>[]);
//         }
//       } else {
//         if (!r.fromCache && r.statusCode != 200) {
//           _safeSet(
//             () => _error = r.statusCode == 0
//                 ? 'Offline and no cached farmers'
//                 : 'Error ${r.statusCode}',
//           );
//         } else {
//           _safeSet(() => _farmers = <_FarmerLite>[]);
//         }
//       }
//     } catch (e) {
//       _safeSet(() => _error = 'Failed to load farmers: $e');
//     } finally {
//       _safeSet(() => _loading = false);
//     }
//   }

//   // ===== Filters & selection =====
//   List<_FarmerLite> get _filtered {
//     final q = _search.trim().toLowerCase();
//     if (q.isEmpty) return _farmers;
//     return _farmers.where((f) {
//       return (f.name?.toLowerCase().contains(q) ?? false) ||
//           (f.location?.toLowerCase().contains(q) ?? false) ||
//           (f.mobile?.toLowerCase().contains(q) ?? false);
//     }).toList();
//   }

//   void _select(_FarmerLite f) {
//     final same = _selected?.id == f.id;
//     if (same) {
//       _safeSet(() {
//         _selected = null;
//         _farmerNameCtrl.clear();
//         _mobileCtrl.clear();
//         _locationCtrl.clear();
//       });
//     } else {
//       _safeSet(() {
//         _selected = f;
//         _farmerNameCtrl.text = (f.name ?? '').trim();
//         _mobileCtrl.text = (f.mobile ?? '').trim();
//         _locationCtrl.text = (f.location ?? '').trim();
//       });
//     }
//   }

//   String? _vRequired(String? v, String label) {
//     if ((v ?? '').trim().isEmpty) return '$label is required';
//     return null;
//   }

//   String? _vRangeDouble(String? v, String label, double min, double max) {
//     final s = (v ?? '').trim();
//     if (s.isEmpty) return '$label is required';
//     final d = double.tryParse(s);
//     if (d == null) return 'Enter a valid number for $label';
//     if (d < min || d > max) return '$label must be between $min and $max';
//     return null;
//   }

//   bool get _canSubmitFarmer =>
//       _selected != null && _remarksCtrl.text.trim().isNotEmpty && !_submitting;

//   void _errorTop(String msg) => _safeSet(() => _inlineBanner = msg);

//   // ===== Submit Farmer Ticket =====
//   Future<void> _submitFarmerTicket() async {
//     FocusScope.of(context).unfocus();

//     if (_selected == null) {
//       _errorTop('Please select a farmer.');
//       return;
//     }
//     if (!(_formKey.currentState?.validate() ?? false)) {
//       _errorTop('Please correct the highlighted fields.');
//       return;
//     }
//     if (_remarksCtrl.text.trim().isEmpty) {
//       _errorTop('Remarks are required.');
//       return;
//     }

//     _errorTop('');
//     _safeSet(() => _submitting = true);

//     try {
//       final prefs = await SharedPreferences.getInstance();
//       final companyId = prefs.getString('companyId') ?? '';
//       final employeeId = prefs.getString('userId') ?? '';
//       final tripId = prefs.getString('currentTripId') ?? '';
//       final token = prefs.getString('token') ?? '';

//       double? d(String s) => double.tryParse(s.trim());
//       int? i(String s) => int.tryParse(s.trim());

//       final location = _locationCtrl.text.trim().isNotEmpty
//           ? _locationCtrl.text.trim()
//           : '(Offline — address unavailable)';

//       final body = {
//         "companyId": companyId,
//         "tripId": tripId, // include even if empty
//         "employeeId": employeeId,
//         "farmerId": _selected!.id ?? '',
//         "farmerName": _farmerNameCtrl.text.trim(),
//         "mobileNumber": _mobileCtrl.text.trim(),
//         "location": location,
//         "pondName": _pondNameCtrl.text.trim(),
//         "pondSize": _pondSizeCtrl.text.trim(),
//         "species": _speciesCtrl.text.trim(),
//         "pondParameters": {
//           "pH": d(_phCtrl.text) ?? 0.0,
//           "ammonia": d(_ammoniaCtrl.text) ?? 0.0,
//           "nitrite": d(_nitriteCtrl.text) ?? 0.0,
//           "alkalinity": i(_alkalinityCtrl.text) ?? 0,
//         },
//         "vibriosis": _vibriosis,
//         "remarks": _remarksCtrl.text.trim(),
//       };

//       debugPrint('🧾 [FarmerTicket] POST ${AppConfig.farmerTicket}');
//       debugPrint(
//         '🧾 [FarmerTicket] headers: Bearer ${token.isNotEmpty ? "SET" : "MISSING"}',
//       );
//       debugPrint('🧾 [FarmerTicket] body: ${jsonEncode(body)}');

//       final resp = await apiClient.sendOrQueue(
//         method: HttpVerb.post,
//         path: AppConfig.farmerTicket,
//         jsonBody: body,
//         headers: {
//           'Authorization': 'Bearer $token',
//           'Content-Type': 'application/json',
//         },
//         optimisticOk: true,
//       );

//       if (!mounted) return;

//       if (resp == null) {
//         debugPrint('🟡 [FarmerTicket] queued (offline or retriable).');
//         ScaffoldMessenger.of(context).showSnackBar(
//           const SnackBar(
//             content: Text('Queued offline — will sync automatically'),
//             duration: Duration(seconds: 2),
//             behavior: SnackBarBehavior.floating,
//           ),
//         );
//         _safeResetFarmerForm();
//       } else if (resp.statusCode == 200 || resp.statusCode == 201) {
//         debugPrint('✅ [FarmerTicket] server OK ${resp.statusCode}');
//         ScaffoldMessenger.of(context).showSnackBar(
//           const SnackBar(
//             content: Text('Farmer ticket raised successfully'),
//             duration: Duration(seconds: 2),
//             behavior: SnackBarBehavior.floating,
//           ),
//         );
//         _safeResetFarmerForm();
//       } else {
//         String msg = 'HTTP ${resp.statusCode}';
//         try {
//           final j = jsonDecode(resp.body);
//           if (j is Map && j['message'] is String) msg = j['message'];
//         } catch (_) {}
//         debugPrint('❌ [FarmerTicket] failed: $msg');
//         _errorTop('Failed to raise ticket: $msg');
//       }
//     } catch (e) {
//       debugPrint('💥 [FarmerTicket] exception: $e');
//       _errorTop('Network error: $e');
//     } finally {
//       _safeSet(() => _submitting = false);
//     }
//   }

//   // small helper to clear the farmer form safely
//   void _safeResetFarmerForm() {
//     _safeSet(() {
//       _selected = null;
//       _farmerNameCtrl.clear();
//       _mobileCtrl.clear();
//       _locationCtrl.clear();
//       _pondNameCtrl.clear();
//       _pondSizeCtrl.clear();
//       _speciesCtrl.clear();
//       _phCtrl.clear();
//       _ammoniaCtrl.clear();
//       _nitriteCtrl.clear();
//       _alkalinityCtrl.clear();
//       _remarksCtrl.clear();
//       _vibriosis = false;
//     });
//   }

//   @override
//   Widget build(BuildContext context) {
//     final items = _filtered;

//     return Column(
//       children: [
//         if ((_inlineBanner ?? '').isNotEmpty)
//           _TopBarMessage(
//             message: _inlineBanner!,
//             onClose: () => _safeSet(() => _inlineBanner = null),
//           ),
//         Padding(
//           padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
//           child: _SearchBox(
//             hint: 'Search farmers (name / mobile / location)…',
//             onChanged: (v) => _safeSet(() => _search = v),
//           ),
//         ),
//         Expanded(
//           child: _loading
//               ? const Center(child: CircularProgressIndicator())
//               : (_error != null
//                     ? _ErrorRetry(message: _error!, onRetry: _fetchFarmers)
//                     : RefreshIndicator(
//                         onRefresh: _fetchFarmers,
//                         child: ListView.separated(
//                           physics: const AlwaysScrollableScrollPhysics(),
//                           padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
//                           itemCount:
//                               (items.isEmpty ? 1 : items.length) + 1, // + form
//                           separatorBuilder: (_, __) =>
//                               const SizedBox(height: 10),
//                           itemBuilder: (_, i) {
//                             if (items.isEmpty && i == 0) {
//                               return const _EmptyState(
//                                 icon: Icons.agriculture,
//                                 title: 'No farmers found',
//                               );
//                             }
//                             if (i < items.length) {
//                               final f = items[i];
//                               final selected = _selected?.id == f.id;
//                               return _FarmerTile(
//                                 farmer: f,
//                                 selected: selected,
//                                 onTap: () => _select(f),
//                               );
//                             }

//                             // Extra form (enabled only when selected)
//                             final enabled = _selected != null;
//                             return Opacity(
//                               opacity: enabled ? 1 : 0.5,
//                               child: AbsorbPointer(
//                                 absorbing: !enabled,
//                                 child: _extraFormCard(),
//                               ),
//                             );
//                           },
//                         ),
//                       )),
//         ),
//       ],
//     );
//   }

//   Widget _extraFormCard() {
//     return Card(
//       elevation: 2,
//       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
//       child: Padding(
//         padding: const EdgeInsets.all(14),
//         child: Form(
//           key: _formKey,
//           child: Column(
//             children: [
//               // Pre-filled + editable
//               // TextFormField(
//               //   controller: _farmerNameCtrl,
//               //   decoration: const InputDecoration(labelText: 'Farmer Name'),
//               //   inputFormatters: _lettersOnly,
//               //   validator: _vName,
//               //   textInputAction: TextInputAction.next,
//               // ),
//               // const SizedBox(height: 10),
//               // TextFormField(
//               //   controller: _mobileCtrl,
//               //   decoration: const InputDecoration(labelText: 'Mobile Number'),
//               //   keyboardType: TextInputType.number,
//               //   inputFormatters: _tenDigits,
//               //   validator: _vMobile,
//               //   textInputAction: TextInputAction.next,
//               // ),
//               // const SizedBox(height: 10),
//               // TextFormField(
//               //   controller: _locationCtrl,
//               //   decoration:
//               //       const InputDecoration(labelText: 'Location / Address'),
//               //   readOnly: true,
//               //   enableInteractiveSelection: false,
//               //   validator: (v) => _vRequired(v, 'Location'),
//               // ),
//               // const Divider(height: 24),

//               // Pond Name (letters + spaces only)
//               TextFormField(
//                 controller: _pondNameCtrl,
//                 decoration: const InputDecoration(
//                   labelText: 'Pond Name',
//                   helperText: 'Letters & spaces only',
//                 ),
//                 inputFormatters: _pondNameFmt,
//                 validator: (v) => _vRequired(v, 'Pond name'),
//                 textInputAction: TextInputAction.next,
//               ),
//               const SizedBox(height: 10),

//               // Pond Size (digits only, max 4)
//               TextFormField(
//                 controller: _pondSizeCtrl,
//                 decoration: const InputDecoration(
//                   labelText: 'Pond Size (acres)',
//                   helperText: 'Up to 4 digits only',
//                 ),
//                 keyboardType: TextInputType.number,
//                 inputFormatters: _pondSizeFmt,
//                 validator: (v) => _vRequired(v, 'Pond size'),
//                 textInputAction: TextInputAction.next,
//               ),
//               const SizedBox(height: 10),

//               // Species (letters + spaces)
//               TextFormField(
//                 controller: _speciesCtrl,
//                 decoration: const InputDecoration(labelText: 'Species'),
//                 inputFormatters: _lettersOnly,
//                 validator: (v) => _vRequired(v, 'Species'),
//                 textInputAction: TextInputAction.next,
//               ),
//               const SizedBox(height: 14),

//               Row(
//                 children: [
//                   Expanded(
//                     child: TextFormField(
//                       controller: _phCtrl,
//                       decoration: const InputDecoration(labelText: 'pH (0–14)'),
//                       keyboardType: const TextInputType.numberWithOptions(
//                         decimal: true,
//                       ),
//                       inputFormatters: [_phFmt],
//                       validator: (v) => _vRangeDouble(v, 'pH', 0, 14),
//                     ),
//                   ),
//                   const SizedBox(width: 12),
//                   Expanded(
//                     child: TextFormField(
//                       controller: _ammoniaCtrl,
//                       decoration: const InputDecoration(
//                         labelText: 'Ammonia (mg/L)',
//                       ),
//                       keyboardType: const TextInputType.numberWithOptions(
//                         decimal: true,
//                       ),
//                       inputFormatters: [_chemFmt],
//                       validator: (v) => _vRangeDouble(v, 'Ammonia', 0, 1000),
//                     ),
//                   ),
//                 ],
//               ),
//               const SizedBox(height: 10),
//               Row(
//                 children: [
//                   Expanded(
//                     child: TextFormField(
//                       controller: _nitriteCtrl,
//                       decoration: const InputDecoration(
//                         labelText: 'Nitrite (mg/L)',
//                       ),
//                       keyboardType: const TextInputType.numberWithOptions(
//                         decimal: true,
//                       ),
//                       inputFormatters: [_chemFmt],
//                       validator: (v) => _vRangeDouble(v, 'Nitrite', 0, 1000),
//                     ),
//                   ),
//                   const SizedBox(width: 12),
//                   Expanded(
//                     child: TextFormField(
//                       controller: _alkalinityCtrl,
//                       decoration: const InputDecoration(
//                         labelText: 'Alkalinity (mg/L)',
//                       ),
//                       keyboardType: TextInputType.number,
//                       inputFormatters: _alkFmt,
//                       validator: (v) {
//                         final s = (v ?? '').trim();
//                         if (s.isEmpty) return 'Alkalinity is required';
//                         if (!RegExp(r'^\d+$').hasMatch(s)) {
//                           return 'Alkalinity must be an integer';
//                         }
//                         if (s.length > 4) return 'Value too large';
//                         return null;
//                       },
//                     ),
//                   ),
//                 ],
//               ),
//               const SizedBox(height: 6),
//               SwitchListTile(
//                 value: _vibriosis,
//                 onChanged: (v) => _safeSet(() => _vibriosis = v),
//                 title: const Text('Vibriosis present? (true/false)'),
//                 contentPadding: EdgeInsets.zero,
//               ),
//               const SizedBox(height: 6),

//               // Remarks REQUIRED
//               TextFormField(
//                 controller: _remarksCtrl,
//                 decoration: const InputDecoration(
//                   labelText: 'Remarks (required)',
//                 ),
//                 inputFormatters: _lettersAndDigitsOnly,
//                 maxLines: 3,
//                 validator: (v) => _vRequired(v, 'Remarks'),
//                 onChanged: (_) => _safeSet(() {}), // refresh submit enable
//               ),
//               const SizedBox(height: 14),

//               SizedBox(
//                 width: double.infinity,
//                 child: ElevatedButton(
//                   onPressed: _canSubmitFarmer ? _submitFarmerTicket : null,
//                   style: ElevatedButton.styleFrom(
//                     backgroundColor: appGreen,
//                     foregroundColor: Colors.white,
//                     minimumSize: const Size(double.infinity, 48),
//                   ),
//                   child: _submitting
//                       ? const SizedBox(
//                           height: 20,
//                           width: 20,
//                           child: CircularProgressIndicator(strokeWidth: 2),
//                         )
//                       : const Text('Raise Farmer Ticket'),
//                 ),
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }
// }

// /* ========================= Models & Tiles ========================= */

// class _DealerLite {
//   final String? id;
//   final String? dealerName;
//   final String? shopName;
//   final String? shopAddress;
//   final String? mobile;

//   _DealerLite({
//     this.id,
//     this.dealerName,
//     this.shopName,
//     this.shopAddress,
//     this.mobile,
//   });

//   factory _DealerLite.fromJson(Map<String, dynamic> j) {
//     String? s(dynamic v) => v?.toString().trim();
//     return _DealerLite(
//       id: s(j['_id'] ?? j['id']),
//       dealerName: s(j['dealerName']),
//       shopName: s(j['shopName']),
//       shopAddress: s(j['shopAddress'] ?? j['address']),
//       mobile: s(j['mobileNumber'] ?? j['mobile']),
//     );
//   }
// }

// class _DealerTile extends StatelessWidget {
//   const _DealerTile({
//     required this.dealer,
//     required this.selected,
//     required this.onTap,
//   });

//   final _DealerLite dealer;
//   final bool selected;
//   final VoidCallback onTap;

//   @override
//   Widget build(BuildContext context) {
//     final title = (dealer.shopName?.isNotEmpty ?? false)
//         ? dealer.shopName!
//         : (dealer.dealerName ?? 'Dealer');

//     return InkWell(
//       onTap: onTap,
//       borderRadius: BorderRadius.circular(12),
//       child: Container(
//         padding: const EdgeInsets.all(14),
//         decoration: BoxDecoration(
//           color: Colors.white,
//           borderRadius: BorderRadius.circular(12),
//           boxShadow: [
//             BoxShadow(
//               color: Colors.black.withValues(alpha: 0.06),
//               blurRadius: 8,
//               offset: const Offset(0, 2),
//             ),
//           ],
//           border: Border.all(
//             color: selected ? const Color(0xFF2E7D32) : Colors.transparent,
//             width: 1.2,
//           ),
//         ),
//         child: Row(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             const Icon(Icons.store, size: 28, color: Color(0xFF2E7D32)),
//             const SizedBox(width: 10),
//             Expanded(
//               child: Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   // title
//                   Text(
//                     title,
//                     maxLines: 1,
//                     overflow: TextOverflow.ellipsis,
//                     style: const TextStyle(
//                       fontSize: 16,
//                       fontWeight: FontWeight.w700,
//                     ),
//                   ),
//                   const SizedBox(height: 6),

//                   // mobile with phone icon
//                   if ((dealer.mobile ?? '').isNotEmpty)
//                     Row(
//                       crossAxisAlignment: CrossAxisAlignment.start,
//                       children: [
//                         Icon(Icons.phone, size: 16, color: Colors.grey[600]),
//                         const SizedBox(width: 6),
//                         Expanded(
//                           child: Text(
//                             dealer.mobile!,
//                             style: TextStyle(
//                               fontSize: 13,
//                               color: Colors.grey[700],
//                               fontWeight: FontWeight.w600,
//                             ),
//                             maxLines: 1,
//                             overflow: TextOverflow.ellipsis,
//                           ),
//                         ),
//                       ],
//                     ),

//                   const SizedBox(height: 6),

//                   // address (human-friendly)
//                   Row(
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     children: [
//                       Icon(Icons.place, size: 16, color: Colors.grey[600]),
//                       const SizedBox(width: 6),
//                       Expanded(
//                         child: Text(
//                           dealer.shopAddress ?? '-',
//                           style: TextStyle(
//                             fontSize: 13,
//                             color: Colors.grey[700],
//                           ),
//                           maxLines: 2,
//                           overflow: TextOverflow.ellipsis,
//                         ),
//                       ),
//                     ],
//                   ),
//                 ],
//               ),
//             ),
//             const SizedBox(width: 8),
//             Icon(
//               selected ? Icons.radio_button_checked : Icons.radio_button_off,
//               color: selected ? const Color(0xFF2E7D32) : Colors.grey,
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }

// class _FarmerLite {
//   final String? id;
//   final String? name;
//   final String? mobile;
//   final String? location;

//   _FarmerLite({this.id, this.name, this.mobile, this.location});

//   factory _FarmerLite.fromJson(Map<String, dynamic> j) {
//     String? s(dynamic v) => v?.toString().trim();
//     return _FarmerLite(
//       id: s(j['_id'] ?? j['id']),
//       name: s(j['name'] ?? j['farmerName']),
//       mobile: s(j['mobileNumber'] ?? j['mobile']),
//       location: s(j['address'] ?? j['location']),
//     );
//   }
// }

// class _FarmerTile extends StatelessWidget {
//   const _FarmerTile({
//     required this.farmer,
//     required this.selected,
//     required this.onTap,
//   });

//   final _FarmerLite farmer;
//   final bool selected;
//   final VoidCallback onTap;

//   @override
//   Widget build(BuildContext context) {
//     return InkWell(
//       onTap: onTap,
//       borderRadius: BorderRadius.circular(12),
//       child: Container(
//         padding: const EdgeInsets.all(14),
//         decoration: BoxDecoration(
//           color: Colors.white,
//           borderRadius: BorderRadius.circular(12),
//           boxShadow: [
//             BoxShadow(
//               color: Colors.black.withValues(alpha: 0.06),
//               blurRadius: 8,
//               offset: const Offset(0, 2),
//             ),
//           ],
//           border: Border.all(
//             color: selected ? const Color(0xFF2E7D32) : Colors.transparent,
//             width: 1.2,
//           ),
//         ),
//         child: Row(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             const Icon(Icons.agriculture, size: 28, color: Color(0xFF2E7D32)),
//             const SizedBox(width: 10),
//             Expanded(
//               child: Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   // farmer name
//                   Text(
//                     farmer.name ?? 'Farmer',
//                     maxLines: 1,
//                     overflow: TextOverflow.ellipsis,
//                     style: const TextStyle(
//                       fontSize: 16,
//                       fontWeight: FontWeight.w700,
//                     ),
//                   ),
//                   const SizedBox(height: 6),

//                   // mobile with phone icon
//                   if ((farmer.mobile ?? '').isNotEmpty)
//                     Row(
//                       crossAxisAlignment: CrossAxisAlignment.start,
//                       children: [
//                         Icon(Icons.phone, size: 16, color: Colors.grey[600]),
//                         const SizedBox(width: 6),
//                         Expanded(
//                           child: Text(
//                             farmer.mobile!,
//                             style: TextStyle(
//                               fontSize: 13,
//                               color: Colors.grey[700],
//                               fontWeight: FontWeight.w600,
//                             ),
//                             maxLines: 1,
//                             overflow: TextOverflow.ellipsis,
//                           ),
//                         ),
//                       ],
//                     ),

//                   const SizedBox(height: 6),

//                   // location
//                   Row(
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     children: [
//                       Icon(Icons.place, size: 16, color: Colors.grey[600]),
//                       const SizedBox(width: 6),
//                       Expanded(
//                         child: Text(
//                           farmer.location ?? '-',
//                           style: TextStyle(
//                             fontSize: 13,
//                             color: Colors.grey[700],
//                           ),
//                           maxLines: 2,
//                           overflow: TextOverflow.ellipsis,
//                         ),
//                       ),
//                     ],
//                   ),
//                 ],
//               ),
//             ),
//             const SizedBox(width: 8),
//             Icon(
//               selected ? Icons.radio_button_checked : Icons.radio_button_off,
//               color: selected ? const Color(0xFF2E7D32) : Colors.grey,
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }

// /* ========================= Shared UI Helpers ========================= */

// class _SearchBox extends StatelessWidget {
//   const _SearchBox({required this.hint, required this.onChanged});
//   final String hint;
//   final ValueChanged<String> onChanged;

//   @override
//   Widget build(BuildContext context) {
//     return TextField(
//       onChanged: onChanged,
//       textInputAction: TextInputAction.search,
//       decoration: InputDecoration(
//         hintText: hint,
//         prefixIcon: const Icon(Icons.search),
//         filled: true,
//         fillColor: Colors.grey.withValues(alpha: 0.08),
//         border: OutlineInputBorder(
//           borderRadius: BorderRadius.circular(12),
//           borderSide: BorderSide.none,
//         ),
//         contentPadding: const EdgeInsets.symmetric(
//           horizontal: 12,
//           vertical: 12,
//         ),
//       ),
//     );
//   }
// }

// class _TopBarMessage extends StatelessWidget {
//   const _TopBarMessage({required this.message, required this.onClose});
//   final String message;
//   final VoidCallback onClose;

//   @override
//   Widget build(BuildContext context) {
//     if (message.trim().isEmpty) return const SizedBox.shrink();
//     return Container(
//       margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
//       padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
//       decoration: BoxDecoration(
//         color: const Color(0xFFFFE8E8),
//         borderRadius: BorderRadius.circular(10),
//         border: Border.all(color: const Color(0xFFFFC2C2)),
//       ),
//       child: Row(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           const Icon(Icons.error_outline, color: Colors.red, size: 18),
//           const SizedBox(width: 8),
//           Expanded(
//             child: Text(
//               message,
//               style: const TextStyle(color: Colors.red, fontSize: 13.5),
//             ),
//           ),
//           InkWell(
//             onTap: onClose,
//             child: const Icon(Icons.close, size: 18, color: Colors.red),
//           ),
//         ],
//       ),
//     );
//   }
// }

// class _ErrorRetry extends StatelessWidget {
//   const _ErrorRetry({required this.message, required this.onRetry});
//   final String message;
//   final VoidCallback onRetry;

//   @override
//   Widget build(BuildContext context) {
//     return Center(
//       child: Padding(
//         padding: const EdgeInsets.all(18),
//         child: Column(
//           mainAxisSize: MainAxisSize.min,
//           children: [
//             const Icon(Icons.info_outline, color: Colors.orange, size: 32),
//             const SizedBox(height: 10),
//             Text(message, textAlign: TextAlign.center),
//             const SizedBox(height: 10),
//             TextButton(onPressed: onRetry, child: const Text('Retry')),
//           ],
//         ),
//       ),
//     );
//   }
// }

// class _EmptyState extends StatelessWidget {
//   const _EmptyState({required this.icon, required this.title});
//   final IconData icon;
//   final String title;
//   @override
//   Widget build(BuildContext context) {
//     return Center(
//       child: Padding(
//         padding: const EdgeInsets.all(18),
//         child: Column(
//           mainAxisSize: MainAxisSize.min,
//           children: [
//             Icon(icon, size: 40, color: Colors.grey[500]),
//             const SizedBox(height: 10),
//             Text(title, style: TextStyle(color: Colors.grey[700])),
//           ],
//         ),
//       ),
//     );
//   }
// }

// // Precise regex input formatter: keeps old value if new text doesn't match
// class _RegexFormatter extends TextInputFormatter {
//   _RegexFormatter(this.regex);
//   final RegExp regex;
//   @override
//   TextEditingValue formatEditUpdate(
//     TextEditingValue oldValue,
//     TextEditingValue newValue,
//   ) {
//     if (newValue.text.isEmpty || regex.hasMatch(newValue.text)) {
//       return newValue;
//     }
//     return oldValue;
//   }
// }
