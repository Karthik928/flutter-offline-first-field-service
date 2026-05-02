// FILE: lib/screena/dealer_ticket_screen.dart
// DealerTicketScreen — same UI & behavior as your Dealer tab but
// accepts a list of dealers (no network GET). Copy this file to
// lib/screena/dealer_ticket_screen.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:FieldService_app/config.dart';
import 'package:FieldService_app/main.dart';
import 'package:FieldService_app/offline/request_envelope.dart';
import 'package:FieldService_app/services/secure_storage_service.dart';

class DealerTicketScreen extends StatefulWidget {
  // either pass a list OR pass single-dealer params (your payment/ticket callers)
  final List<DealerLite>? dealers;
  final DealerLite? preselected;

  final String? dealerId;
  final String? dealerName;
  final String? shopName;
  final String? address;
  final String? mobile;
  final double? latitude;
  final double? longitude;
  final bool? tripCompleted;
  final double pendingAmount;

  const DealerTicketScreen({
    super.key,
    this.dealers,
    this.preselected,
    this.dealerId,
    this.dealerName,
    this.shopName,
    this.address,
    this.mobile,
    this.latitude,
    this.longitude,
    this.tripCompleted,
    required this.pendingAmount, // ✅ ADD
  });

  @override
  State<DealerTicketScreen> createState() => _DealerTicketScreenState();
}

class _DealerTicketScreenState extends State<DealerTicketScreen> {
  final Color appGreen = const Color(0xFF2E7D32);

  late List<DealerLite> _dealers;
  DealerLite? _selected;

  // Remarks REQUIRED
  final _remarksCtrl = TextEditingController();
  bool _submitting = false;
  String? _inlineBanner;

  void _safeSet(void Function() fn) {
    if (!mounted) return;
    setState(fn);
  }

  @override
  void initState() {
    super.initState();

    // build _dealers from either provided list or single-dealer params
    if (widget.dealers != null && widget.dealers!.isNotEmpty) {
      _dealers = widget.dealers!;
    } else if (widget.dealerId != null ||
        widget.dealerName != null ||
        widget.shopName != null ||
        widget.address != null) {
      _dealers = [
        DealerLite(
          id: widget.dealerId,
          dealerName: widget.dealerName,
          shopName: widget.shopName,
          shopAddress: widget.address,
          mobile: widget.mobile,
          latitude: widget.latitude,
          longitude: widget.longitude,
        ),
      ];
    } else {
      _dealers = <DealerLite>[];
    }

    // preselected takes precedence; else default to first item (if any)
    if (widget.preselected != null) {
      _selected = widget.preselected;
    } else if (_dealers.isNotEmpty) {
      _selected = _dealers.first;
    }

    _remarksCtrl.addListener(() => _safeSet(() {}));
  }

  @override
  void dispose() {
    _remarksCtrl.dispose();
    super.dispose();
  }

  void _errorTop(String msg) => _safeSet(() => _inlineBanner = msg);

  bool get _canSubmitDealer =>
      _selected != null && _remarksCtrl.text.trim().isNotEmpty && !_submitting;

  Future<void> _submitDealerTicket() async {
    if (!_canSubmitDealer) {
      _errorTop('Select a dealer and enter remarks to proceed.');
      return;
    }

    _errorTop('');
    _safeSet(() => _submitting = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final companyId = prefs.getString('companyId') ?? '';
      final employeeId = prefs.getString('userId') ?? '';
      final tripId = prefs.getString('currentTripId') ?? '';
      final tripCompleted = prefs.getBool('tripCompleted') ?? false;
      final effectiveTripId = tripCompleted == true ? tripId : '';
      //final token = prefs.getString('token') ?? '';

      final token = await SecureStorageService.getToken();

      final d = _selected!;
      final body = {
        "companyId": companyId,
        "dealerId": d.id ?? '',
        "employeeId": employeeId,
        if (effectiveTripId.isNotEmpty) "tripId": effectiveTripId,
        "dealerName": d.dealerName ?? d.shopName ?? '',
        "mobileNumber": d.mobile ?? '',
        "dealerLocation": d.shopAddress ?? '',
        "remarks": _remarksCtrl.text.trim(),
      };
      debugPrint(jsonEncode(body));

      debugPrint('🧾 [DealerTicket] POST ${AppConfig.dealerTickets}');
      debugPrint('🧾 [DealerTicket] body: ${jsonEncode(body)}');

      final resp = await apiClient.sendOrQueue(
        method: HttpVerb.post,
        path: AppConfig.dealerTickets,
        jsonBody: body,
        headers: {'Authorization': 'Bearer $token'},
        optimisticOk: true,
      );

      if (!mounted) return;

      if (resp == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Queued offline — will sync automatically'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
        _safeSet(() {
          _selected = null;
          _remarksCtrl.clear();
        });
      } else if (resp.statusCode == 200 || resp.statusCode == 201) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Dealer query submitted successfully'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Color(0xFF2E7D32),
          ),
        );
        _safeSet(() {
          _selected = null;
          _remarksCtrl.clear();
        });
      } else {
        String msg = 'HTTP ${resp.statusCode}';
        try {
          final j = jsonDecode(resp.body);
          if (j is Map && j['message'] is String) msg = j['message'];
          debugPrint('❌ ERROR BODY: ${resp.body}');
        } catch (_) {}
        _errorTop('Failed to raise query: $msg');
      }
    } catch (e) {
      _errorTop('Network error: $e');
    } finally {
      _safeSet(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: Container(
          decoration: const BoxDecoration(
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
            gradient: LinearGradient(
              colors: [
                Color(0xFF52D494), // top
                Color(0xFF1AB69C), // bottom
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            centerTitle: true,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
            ),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_sharp, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            title: const Text(
              'Dealer Query',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
          ),
        ),
      ),

      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if ((_inlineBanner ?? '').isNotEmpty)
                _TopBarMessage(
                  message: _inlineBanner!,
                  onClose: () => _safeSet(() => _inlineBanner = null),
                ),

              if (_selected != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: _DealerInfoReadonlyCard(
                    dealer: _selected!,
                    pendingAmount: widget.pendingAmount, // ✅ PASS DOWN
                  ),
                ),

              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 16, 16),
                child: Column(
                  children: [
                    TextFormField(
                      controller: _remarksCtrl,
                      minLines: 2,
                      maxLines: 4,
                      decoration: InputDecoration(
                        labelText: 'Remarks (required)',
                        filled: true,
                        fillColor: Colors.grey.withValues(alpha: 0.06),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
                        ),

                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Color(0xFF1AB69C),
                            width: 1.3,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Color(0xFF1AB69C),
                            width: 1.8,
                          ),
                        ),
                        errorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Colors.red,
                            width: 1.3,
                          ),
                        ),
                        focusedErrorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Colors.red,
                            width: 1.8,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _canSubmitDealer
                            ? _submitDealerTicket
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Color(0xFF1AB69C),
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _submitting
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : const Text(
                                'Raise Query',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DealerInfoReadonlyCard extends StatelessWidget {
  final DealerLite dealer;
  final double pendingAmount; // ✅ ADD

  const _DealerInfoReadonlyCard({
    required this.dealer,
    required this.pendingAmount, // ✅ ADD
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Color(0xFF1AB69C),
            blurRadius: 3,
            offset: Offset(0, 0.5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if ((dealer.dealerName ?? '').isNotEmpty)
            Text(
              dealer.dealerName!,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          if ((dealer.shopName ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                dealer.shopName!,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[700],
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const SizedBox(height: 8),
          if ((dealer.mobile ?? '').isNotEmpty)
            Row(
              children: [
                Icon(Icons.phone, size: 16, color: Color(0xFF1AB69C)),
                const SizedBox(width: 6),
                Text(
                  dealer.mobile!,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.place, size: 16, color: Color(0xFF1AB69C)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  dealer.shopAddress ?? '-',
                  style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          Row(
            children: [
              Icon(
                Icons.account_balance_wallet,
                size: 15,
                color: Color(0xFF1AB69C),
              ),
              const SizedBox(width: 8),
              Builder(
                builder: (_) {
                  // formatter for Indian currency (₹) with thousands separators
                  final fmt = NumberFormat.currency(
                    locale: 'en_IN',
                    symbol: '₹',
                    decimalDigits: 2,
                  );
                  final pending = pendingAmount;

                  final noDue = pending <= 0.0;
                  debugPrint('pendingAmount=${pending.toString()}');
                  // Debug.log(
                  //   'Dealer ${d.shopName} pendingAmount: $pending'
                  //       as num,
                  // );
                  return Flexible(
                    child: Text(
                      noDue ? 'No Due' : 'Due: ${fmt.format(pending)}',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        color: noDue
                            ? Colors.green
                            : const Color.fromARGB(255, 255, 0, 0),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class DealerLite {
  final String? id;
  final String? dealerName;
  final String? shopName;
  final String? shopAddress;
  final String? mobile;
  final double? latitude;
  final double? longitude;

  DealerLite({
    this.id,
    this.dealerName,
    this.shopName,
    this.shopAddress,
    this.mobile,
    this.latitude,
    this.longitude,
  });
}

class _TopBarMessage extends StatelessWidget {
  const _TopBarMessage({required this.message, required this.onClose});
  final String message;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    if (message.trim().isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFE8E8),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFFC2C2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.red, fontSize: 13.5),
            ),
          ),
          InkWell(
            onTap: onClose,
            child: const Icon(Icons.close, size: 18, color: Colors.red),
          ),
        ],
      ),
    );
  }
}
