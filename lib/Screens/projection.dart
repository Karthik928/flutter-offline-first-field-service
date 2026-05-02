// projection.dart (NO DIO VERSION)
// Shows Upcoming & Past scheduled payments
// Tap → fetch dealer by ID using http + AppConfig

import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:FieldService_app/config.dart';
import 'package:FieldService_app/main.dart';
import 'package:FieldService_app/offline/cache_store.dart';
import 'package:FieldService_app/services/notification_api.dart';
import 'package:FieldService_app/services/secure_storage_service.dart';

class ProjectionPage extends StatefulWidget {
  const ProjectionPage({super.key});

  @override
  State<ProjectionPage> createState() => _ProjectionPageState();
}

class _ProjectionPageState extends State<ProjectionPage>
    with SingleTickerProviderStateMixin {
  final Color appGreen = const Color(0xFF1AB69C);

  bool _loading = true;
  String? _error;

  List<ScheduledPayment> _upcoming = [];
  List<ScheduledPayment> _past = [];

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ---------------- AUTH HEADERS ----------------

  Future<Map<String, String>> _headers() async {
    // final prefs = await SharedPreferences.getInstance();
    // final token = prefs.getString('token');
    final token = await SecureStorageService.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  // ---------------- LOAD DATA ----------------

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final items = await fetchPayments(_headers);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      final upcoming = items.where((it) {
        final dt = it.sendAt.toLocal();
        return it.sent == false && !dt.isBefore(today);
      }).toList();

      final past = items.where((it) {
        final dt = it.sendAt.toLocal();
        return it.sent == true || dt.isBefore(today);
      }).toList();

      upcoming.sort((a, b) => a.sendAt.compareTo(b.sendAt));
      past.sort((a, b) => a.sendAt.compareTo(b.sendAt));

      if (!mounted) return;
      setState(() {
        _upcoming = upcoming;
        _past = past;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  // ---------------- HELPERS ----------------

  String _formatDate(DateTime dt) {
    final d = dt.toLocal();
    return "${d.day}/${d.month}/${d.year} ${d.hour}:${d.minute.toString().padLeft(2, '0')}";
  }

  String _inr(num n) => "₹${n.toStringAsFixed(0)}";

  // ---------------- STATUS BOTTOM SHEET ----------------
  // Bottom sheet shows all details (name, shop, address, phone, amount, status)
  // Only allow Update when status == 'pending'

  void _openStatusBottomSheet(ScheduledPayment p) {
    String selectedStatus = 'completed';
    bool submitting = false;
    final paidController = TextEditingController();
    DateTime? pickedDate;
    TimeOfDay? pickedTime;

    // helper to combine date+time into a local DateTime
    DateTime? pickedLocalDateTime() {
      if (pickedDate == null || pickedTime == null) return null;
      return DateTime(
        pickedDate!.year,
        pickedDate!.month,
        pickedDate!.day,
        pickedTime!.hour,
        pickedTime!.minute,
      );
    }

    // helper to get ISO UTC string for sending to server
    String? rescheduleIsoUtc() {
      final dt = pickedLocalDateTime();
      if (dt == null) return null;
      return dt.toUtc().toIso8601String();
    }

    // human-friendly local string for confirmation dialog
    String pickedLocalFormatted() {
      final dt = pickedLocalDateTime();
      if (dt == null) return '-';
      final hh = dt.hour.toString().padLeft(2, '0');
      final mm = dt.minute.toString().padLeft(2, '0');
      return '${dt.day}/${dt.month}/${dt.year} $hh:$mm (${dt.timeZoneName})';
    }

    // compute pending (read-only)
    num getPaidValue() {
      final text = paidController.text.trim();
      if (text.isEmpty) return 0;
      return num.tryParse(text) ?? 0;
    }

    final rootContext = context;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final dealerFuture = (p.dealerIdTrimmed != null)
            ? fetchDealer(p.dealerIdTrimmed!, _headers)
            : Future<Dealer?>.value(null);

        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              ),
              child: FutureBuilder<Dealer?>(
                future: dealerFuture,
                builder: (context, snap) {
                  final dealer = snap.data;
                  final origAmount = p.amount ?? 0;
                  final paidVal = getPaidValue();
                  final pendingVal = (origAmount - paidVal) < 0
                      ? 0
                      : (origAmount - paidVal);

                  return SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header + current status
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                p.title ?? 'Update Status',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: _statusColor(
                                  p.status,
                                ).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                p.status ?? 'unknown',
                                style: TextStyle(
                                  color: _statusColor(p.status),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 10),
                        Text(
                          dealer?.dealerName ?? p.dealerName ?? '-',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: appGreen,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(dealer?.shopName ?? p.shopName ?? '-'),
                        const SizedBox(height: 6),
                        if ((dealer?.shopAddress ?? '') != '' ||
                            (p.dealerRaw is Map &&
                                (p.dealerRaw['shopAddress'] ?? '') != ''))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: Text(
                              dealer?.shopAddress ??
                                  (p.dealerRaw is Map
                                      ? p.dealerRaw['shopAddress'] ?? ''
                                      : ''),
                              style: const TextStyle(color: Colors.black54),
                            ),
                          ),
                        if ((p.mobile ?? '').isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: Row(
                              children: [
                                Icon(Icons.call, size: 16, color: appGreen),
                                const SizedBox(width: 8),
                                Text(
                                  p.mobile ?? '',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),

                        // Amount
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: Row(
                            children: [
                              const Icon(Icons.payment, size: 16),
                              const SizedBox(width: 8),
                              Text(
                                _inr(origAmount),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 8),

                        // Dropdown
                        DropdownButtonFormField<String>(
                          initialValue: selectedStatus,
                          items: const [
                            DropdownMenuItem(
                              value: 'completed',
                              child: Text('Completed'),
                            ),
                            DropdownMenuItem(
                              value: 'rescheduled',
                              child: Text('Rescheduled'),
                            ),
                            DropdownMenuItem(
                              value: 'partial payment',
                              child: Text('Partial Payment'),
                            ),
                          ],
                          onChanged: submitting
                              ? null
                              : (v) => setSheetState(
                                  () => selectedStatus = v ?? selectedStatus,
                                ),
                          decoration: const InputDecoration(
                            labelText: 'Action',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),

                        const SizedBox(height: 12),

                        // If partial payment => show paid + pending + reschedule pickers
                        if (selectedStatus == 'partial payment') ...[
                          TextFormField(
                            controller: paidController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText: 'Paid amount',
                              border: OutlineInputBorder(),
                              isDense: true,
                              hintText: origAmount.toString(),
                            ),
                            onChanged: (_) => setSheetState(() {}),
                          ),
                          const SizedBox(height: 8),
                          // Pending (read-only)
                          TextFormField(
                            readOnly: true,
                            decoration: InputDecoration(
                              labelText: 'Pending amount',
                              border: const OutlineInputBorder(),
                              isDense: true,
                              hintText: pendingVal.toString(),
                            ),
                            controller: TextEditingController(
                              text: pendingVal.toString(),
                            ),
                          ),
                          const SizedBox(height: 8),
                          // Date + Time pickers for pending schedule
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: submitting
                                      ? null
                                      : () async {
                                          final d = await showDatePicker(
                                            context: ctx,
                                            initialDate: DateTime.now(),
                                            firstDate: DateTime.now().subtract(
                                              const Duration(days: 0),
                                            ),
                                            lastDate: DateTime.now().add(
                                              const Duration(days: 365),
                                            ),
                                          );
                                          if (d != null) {
                                            setSheetState(() => pickedDate = d);
                                          }
                                        },
                                  child: Text(
                                    pickedDate == null
                                        ? 'Pick Date'
                                        : '${pickedDate!.day}/${pickedDate!.month}/${pickedDate!.year}',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: submitting
                                      ? null
                                      : () async {
                                          final t = await showTimePicker(
                                            context: ctx,
                                            initialTime: TimeOfDay.now(),
                                          );
                                          if (t != null) {
                                            setSheetState(() => pickedTime = t);
                                          }
                                        },
                                  child: Text(
                                    pickedTime == null
                                        ? 'Pick Time'
                                        : '${pickedTime!.hour.toString().padLeft(2, '0')}:${pickedTime!.minute.toString().padLeft(2, '0')}',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],

                        // If rescheduled => show date+time
                        if (selectedStatus == 'rescheduled') ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: submitting
                                      ? null
                                      : () async {
                                          final d = await showDatePicker(
                                            context: ctx,
                                            initialDate: DateTime.now(),
                                            firstDate: DateTime.now().subtract(
                                              const Duration(days: 0),
                                            ),
                                            lastDate: DateTime.now().add(
                                              const Duration(days: 365),
                                            ),
                                          );
                                          if (d != null) {
                                            setSheetState(() => pickedDate = d);
                                          }
                                        },
                                  child: Text(
                                    pickedDate == null
                                        ? 'Pick Date'
                                        : '${pickedDate!.day}/${pickedDate!.month}/${pickedDate!.year}',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: submitting
                                      ? null
                                      : () async {
                                          final t = await showTimePicker(
                                            context: ctx,
                                            initialTime: TimeOfDay.now(),
                                          );
                                          if (t != null) {
                                            setSheetState(() => pickedTime = t);
                                          }
                                        },
                                  child: Text(
                                    pickedTime == null
                                        ? 'Pick Time'
                                        : '${pickedTime!.hour.toString().padLeft(2, '0')}:${pickedTime!.minute.toString().padLeft(2, '0')}',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],

                        const SizedBox(height: 12),

                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: submitting
                                ? null
                                : () async {
                                    // basic validation
                                    if (selectedStatus == 'partial payment') {
                                      final paid = getPaidValue();
                                      if (paid <= 0) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Enter a paid amount > 0',
                                            ),
                                          ),
                                        );
                                        return;
                                      }
                                      final orig = origAmount;
                                      if (paid > orig) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Paid amount cannot exceed total amount',
                                            ),
                                          ),
                                        );
                                        return;
                                      }
                                      if (pickedLocalDateTime() == null) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Pick date and time for pending amount',
                                            ),
                                          ),
                                        );
                                        return;
                                      }
                                    } else if (selectedStatus ==
                                        'rescheduled') {
                                      if (pickedLocalDateTime() == null) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Pick a date and time',
                                            ),
                                          ),
                                        );
                                        return;
                                      }
                                    }

                                    // confirmation dialog — show local formatted time so it matches picker
                                    final summary = StringBuffer(
                                      'Change status to "$selectedStatus"',
                                    );
                                    if (selectedStatus == 'partial payment') {
                                      final paid = getPaidValue();
                                      summary.writeln('\nPaid: $paid');
                                      summary.writeln(
                                        'Pending: ${(origAmount - paid)}',
                                      );
                                      summary.writeln(
                                        'Pending scheduled at: ${pickedLocalFormatted()}',
                                      );
                                    } else if (selectedStatus ==
                                        'rescheduled') {
                                      summary.writeln(
                                        '\nRescheduled at: ${pickedLocalFormatted()}',
                                      );
                                    }

                                    final confirmed = await showDialog<bool>(
                                      context: ctx,
                                      builder: (dctx) {
                                        return AlertDialog(
                                          title: const Text('Confirm update'),
                                          content: Text(summary.toString()),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(dctx, false),
                                              child: const Text('Cancel'),
                                            ),
                                            ElevatedButton(
                                              onPressed: () =>
                                                  Navigator.pop(dctx, true),
                                              child: const Text('Confirm'),
                                            ),
                                          ],
                                        );
                                      },
                                    );

                                    if (confirmed != true) return;

                                    setSheetState(() => submitting = true);

                                    // build PATCH body for notification update
                                    // --- BUILD patchBody and schedule payload (robust + debug) ---
                                    // capture paidVal once (so we don't recalc later with changed controller/state)
                                    final paidVal = getPaidValue();
                                    final pendingVal =
                                        (origAmount - paidVal) < 0
                                        ? 0
                                        : (origAmount - paidVal);

                                    // build PATCH body (server truth)
                                    final Map<String, dynamic> patchBody = {
                                      'status': selectedStatus,
                                    };

                                    if (selectedStatus == 'partial payment') {
                                      patchBody['paidAmount'] = paidVal;
                                      patchBody['pendingAmount'] = pendingVal;
                                      final iso = rescheduleIsoUtc();
                                      if (iso != null) {
                                        patchBody['rescheduleAt'] = iso;
                                      }
                                    } else if (selectedStatus ==
                                        'rescheduled') {
                                      final iso = rescheduleIsoUtc();
                                      if (iso != null) {
                                        patchBody['rescheduleAt'] = iso;
                                      }
                                    }

                                    // DEBUG: show exactly what we'll PATCH
                                    debugPrint(
                                      '🔧 [Payments] PATCH -> notifId=${p.id} body=${jsonEncode(patchBody)}',
                                    );

                                    // 1) PATCH update notification (status + fields)
                                    final okPatch =
                                        await _updateNotificationStatus(
                                          p.id,
                                          patchBody,
                                        );
                                    debugPrint(
                                      '🔧 [Payments] PATCH result for ${p.id}: $okPatch',
                                    );

                                    bool okSchedule = true;

                                    // 2) If patch succeeded and we need a scheduled follow-up, call NotificationsApi.schedule
                                    if (okPatch &&
                                        (selectedStatus == 'rescheduled' ||
                                            selectedStatus ==
                                                'partial payment')) {
                                      try {
                                        // choose schedule amount strictly by action
                                        late final num scheduleAmount;
                                        if (selectedStatus ==
                                            'partial payment') {
                                          scheduleAmount =
                                              pendingVal; // REMAINING amount only
                                        } else {
                                          scheduleAmount =
                                              origAmount; // RESCHEDULE -> full original amount
                                        }

                                        // prepare other schedule params
                                        final sendAtUtc =
                                            rescheduleIsoUtc() ?? '';
                                        final dealerIdForSchedule =
                                            p.dealerIdTrimmed ??
                                            (p.dealerRaw is Map
                                                ? (p.dealerRaw['_id']
                                                          ?.toString() ??
                                                      '')
                                                : '');
                                        final mobileForSchedule =
                                            p.mobile ??
                                            (p.dealerRaw is Map
                                                ? (p.dealerRaw['mobileNumber']
                                                          ?.toString() ??
                                                      '')
                                                : '');
                                        final title =
                                            p.title ??
                                            'Payment due — ${p.dealerName ?? ''}';
                                        final note =
                                            selectedStatus == 'partial payment'
                                            ? 'Pending payment reminder'
                                            : 'Rescheduled payment reminder';

                                        final fcmToken = await FirebaseMessaging
                                            .instance
                                            .getToken();
                                        if (fcmToken == null ||
                                            fcmToken.isEmpty) {
                                          debugPrint(
                                            '❌ [Payments] FCM token missing – cannot schedule',
                                          );
                                          okSchedule = false;
                                          throw Exception('FCM token missing');
                                        }

                                        // DEBUG: log schedule payload
                                        debugPrint(
                                          '🔔 [Payments] Scheduling reminder: '
                                          'title="$title", dealerId="$dealerIdForSchedule", amount=$scheduleAmount, '
                                          'sendAtUtc="$sendAtUtc", mobile="$mobileForSchedule", fcmTokenPresent=${fcmToken.isNotEmpty}',
                                        );

                                        final res =
                                            await NotificationsApi.schedule(
                                              title: title,
                                              dealerId: dealerIdForSchedule,
                                              dealerName: p.dealerName ?? '',
                                              shopName: p.shopName ?? '',
                                              amount: scheduleAmount,
                                              mobile: mobileForSchedule,
                                              body: note,
                                              fcmToken: fcmToken,
                                              sendAtUtc: sendAtUtc,
                                            );

                                        okSchedule = res.success;
                                        debugPrint(
                                          '🔔 [Payments] schedule result: success=${res.success}, message="${res.message}", id=${res.id}',
                                        );
                                        if (!okSchedule) {
                                          debugPrint(
                                            '🔔 [Payments] schedule failed message: ${res.message}',
                                          );
                                        }
                                      } catch (e, st) {
                                        okSchedule = false;
                                        debugPrint(
                                          '🔔 [Payments] schedule exception: $e\n$st',
                                        );
                                      }
                                    }

                                    // stop spinner & show user feedback
                                    setSheetState(() => submitting = false);

                                    if (okPatch) {
                                      if (!context.mounted) return;
                                      Navigator.pop(ctx);
                                      await _load(); // refresh canonical server list

                                      if (selectedStatus == 'completed') {
                                        if (!context.mounted) return;
                                        Navigator.pop(ctx);
                                        await _load();
                                        if (!context.mounted) return;
                                        ScaffoldMessenger.of(
                                          rootContext,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Status updated to "completed"',
                                            ),
                                          ),
                                        );
                                      } else {
                                        if (okSchedule) {
                                          if (!context.mounted) return;
                                          Navigator.pop(ctx);
                                          await _load();
                                          if (!context.mounted) return;
                                          ScaffoldMessenger.of(
                                            rootContext,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Status updated and follow-up scheduled',
                                              ),
                                            ),
                                          );
                                        } else {
                                          if (!context.mounted) return;
                                          Navigator.pop(ctx);
                                          await _load();
                                          if (!context.mounted) return;
                                          // include server message if available (helps debug)
                                          ScaffoldMessenger.of(
                                            rootContext,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                'Status updated but scheduling failed',
                                              ),
                                            ),
                                          );
                                        }
                                      }
                                    } else {
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Failed to update status',
                                          ),
                                        ),
                                      );
                                    }
                                  },
                            child: submitting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text('Update'),
                          ),
                        ),

                        const SizedBox(height: 8),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openDealer(String dealerId) async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return FutureBuilder<Dealer>(
          future: fetchDealer(dealerId, _headers),
          builder: (_, snap) {
            if (!snap.hasData) {
              return const SizedBox(
                height: 200,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final d = snap.data!;
            return Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    d.dealerName ?? '-',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: appGreen,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(d.shopName ?? '-'),
                  const SizedBox(height: 8),
                  Text(
                    d.shopAddress ?? '-',
                    style: const TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    "Pending Amount: ${_inr(d.pendingAmount ?? 0)}",
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text("Delivered: ${_inr(d.deliveredOrdersAmount ?? 0)}"),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// Patch notification with arbitrary JSON body (must include "status")
  Future<bool> _updateNotificationStatus(
    String notifId,
    Map<String, dynamic> body,
  ) async {
    try {
      final headers = await _headers();
      headers['Content-Type'] = 'application/json';

      final path = AppConfig.p(AppConfig.updateNotification, {'id': notifId});
      final uri = AppConfig.u(path);

      final resp = await http
          .patch(uri, headers: headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 12));

      if (resp.statusCode == 200 || resp.statusCode == 204) {
        return true;
      } else {
        debugPrint(
          '❌ updateNotification failed ${resp.statusCode} ${resp.body}',
        );
        return false;
      }
    } catch (e) {
      debugPrint('❌ updateNotification exception: $e');
      return false;
    }
  }

  Color _statusColor(String? s) {
    switch ((s ?? '').toLowerCase()) {
      case 'pending':
        return Colors.orange;
      case 'partial payment':
        return Colors.blue;
      case 'rescheduled':
        return Colors.purple;
      case 'completed':
      case 'paid':
        return appGreen;
      default:
        return Colors.grey;
    }
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,

      // ---------- APP BAR ----------
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(108),
        child: Container(
          decoration: const BoxDecoration(
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
            gradient: LinearGradient(
              colors: [Color(0xFF52D494), Color(0xFF1AB69C)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            automaticallyImplyLeading: false,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
            ),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_sharp, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            title: const Text(
              'Payments',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
                fontSize: 20,
              ),
            ),
            centerTitle: true,
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: Colors.white,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              tabs: const [
                Tab(text: 'Upcoming'),
                Tab(text: 'Past'),
              ],
            ),
          ),
        ),
      ),

      // ---------- BODY ----------
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text('Error: $_error'))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildList(_upcoming, 'No upcoming payments'),
                _buildList(_past, 'No past payments'),
              ],
            ),
    );
  }

  Widget _buildList(List<ScheduledPayment> list, String emptyText) {
    if (list.isEmpty) {
      return Center(child: Text(emptyText));
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: appGreen,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(14),
        itemCount: list.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final p = list[i];

          // 🚫 HARD FILTER — do not render card if dealer info is missing
          final hasDealer =
              (p.dealerIdTrimmed != null && p.dealerIdTrimmed!.isNotEmpty) ||
              ((p.dealerName ?? '').isNotEmpty) ||
              ((p.shopName ?? '').isNotEmpty);

          if (!hasDealer) {
            return const SizedBox.shrink(); // ❌ no card created
          }

          final isOverdue = !p.sent && p.sendAt.isBefore(DateTime.now());
          final isReminder = !p.sent;
          final when = _formatDate(p.sendAt);

          return InkWell(
            onTap: () {
              if ((p.status ?? '').toLowerCase() == 'pending') {
                _openStatusBottomSheet(p);
              } else if (p.dealerIdTrimmed != null) {
                _openDealer(p.dealerIdTrimmed!);
              }
            },
            child: Column(
              children: [
                Container(
                  //...
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: appGreen.withValues(alpha: 0.12)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ICON
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: isReminder
                              ? Colors.amber.withValues(alpha: 0.15)
                              : appGreen.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          isReminder ? Icons.schedule : Icons.mark_email_read,
                          color: isReminder ? Colors.amber[700] : appGreen,
                        ),
                      ),

                      const SizedBox(width: 12),

                      // DETAILS
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Title + Amount
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    p.title ?? p.dealerName ?? '-',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15.5,
                                    ),
                                  ),
                                ),
                                Text(
                                  _inr(p.amount ?? 0),
                                  style: TextStyle(
                                    color: appGreen,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 6),

                            // Shop name
                            if ((p.shopName ?? '').isNotEmpty)
                              Text(
                                p.shopName ?? '',
                                style: TextStyle(
                                  color: Colors.black87.withValues(alpha: 0.8),
                                ),
                              ),

                            const SizedBox(height: 6),

                            // Mobile (main card)
                            if ((p.mobile ?? '').isNotEmpty)
                              Row(
                                children: [
                                  Icon(Icons.call, size: 14, color: appGreen),
                                  const SizedBox(width: 6),
                                  Text(
                                    p.mobile ?? '',
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                  const Spacer(),

                                  // animated status pill
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 300),
                                    transitionBuilder: (child, anim) =>
                                        ScaleTransition(
                                          scale: anim,
                                          child: child,
                                        ),
                                    child:
                                        (p.status != null &&
                                            p.status!.isNotEmpty)
                                        ? Container(
                                            key: ValueKey<String>(p.status!),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: _statusColor(
                                                p.status,
                                              ).withValues(alpha: 0.12),
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                            child: Text(
                                              p.status!,
                                              style: TextStyle(
                                                color: _statusColor(p.status),
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          )
                                        : const SizedBox.shrink(),
                                  ),
                                ],
                              ),

                            const SizedBox(height: 8),

                            // Date + Status pill (Animated)
                            Row(
                              children: [
                                Icon(Icons.schedule, size: 14, color: appGreen),
                                const SizedBox(width: 6),
                                Text(
                                  when,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: isOverdue
                                        ? Colors.redAccent
                                        : Colors.black54,
                                    fontWeight: isOverdue
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ---------------- MODELS ----------------

class ScheduledPayment {
  final String id;
  final String? title;
  final String? dealerName;
  final String? shopName;
  final String? mobile;
  final num? amount;
  final DateTime sendAt;
  bool sent;
  String? status; // <-- not final now
  final dynamic dealerRaw;

  ScheduledPayment({
    required this.id,
    this.title,
    this.dealerName,
    this.shopName,
    this.mobile,
    this.amount,
    required this.sendAt,
    required this.sent,
    this.status,
    this.dealerRaw,
  });

  String? get dealerIdTrimmed {
    if (dealerRaw is String) return dealerRaw;
    if (dealerRaw is Map && dealerRaw['_id'] != null) {
      return dealerRaw['_id'].toString();
    }
    return null;
  }

  factory ScheduledPayment.fromJson(Map<String, dynamic> j) {
    return ScheduledPayment(
      id: j['_id'],
      title: j['title'],
      dealerName: j['dealerName'],
      shopName: j['shopName'],
      mobile: j['mobile'],
      amount: j['amount'],
      sendAt: DateTime.parse(j['sendAt']),
      sent: j['sent'] == true,
      status: j['status']?.toString(),
      dealerRaw: j['dealerId'],
    );
  }
}

class Dealer {
  final String? dealerName;
  final String? shopName;
  final String? shopAddress;
  final num? pendingAmount;
  final num? deliveredOrdersAmount;

  Dealer({
    this.dealerName,
    this.shopName,
    this.shopAddress,
    this.pendingAmount,
    this.deliveredOrdersAmount,
  });

  factory Dealer.fromJson(Map<String, dynamic> j) {
    return Dealer(
      dealerName: j['dealerName'],
      shopName: j['shopName'],
      shopAddress: j['shopAddress'],
      pendingAmount: j['pendingAmount'],
      deliveredOrdersAmount: j['deliveredOrdersAmount'],
    );
  }
}

// ---------------- SERVICE ----------------

Future<List<ScheduledPayment>> fetchPayments(
  Future<Map<String, String>> Function() headerBuilder,
) async {
  final prefs = await SharedPreferences.getInstance();
  final employeeId = (prefs.getString('userId') ?? '').trim();
  final companyId = (prefs.getString('companyId') ?? '').trim();

  if (employeeId.isEmpty || companyId.isEmpty) {
    debugPrint(
      '❌ [NotificationsApi] Missing employeeId/companyId '
      'employeeId="$employeeId" companyId="$companyId"',
    );
  }

  final cacheKey = 'payments:employee:$employeeId';

  final uri = AppConfig.u(
    AppConfig.p(AppConfig.notificationsByEmployee, {'id': employeeId}),
  );

  // ---------------- TRY NETWORK FIRST ----------------
  try {
    final headers = await headerBuilder();
    final res = await http.get(uri, headers: headers);

    if (res.statusCode == 200) {
      // Save fresh data to cache
      await apiClient.cache?.put(
        cacheKey,
        CacheEntry(
          body: res.body,
          statusCode: res.statusCode,
          storedAtMillis: DateTime.now().millisecondsSinceEpoch,
        ),
      );

      final body = jsonDecode(res.body);
      final list = body['data'] as List? ?? [];
      return list.map((e) => ScheduledPayment.fromJson(e)).toList();
    }
  } catch (e) {
    // swallow and fallback to cache
  }

  // ---------------- FALLBACK TO CACHE ----------------
  final cached = apiClient.cache?.get(cacheKey);
  if (cached != null && cached.body.isNotEmpty) {
    try {
      final body = jsonDecode(cached.body);
      final list = body['data'] as List? ?? [];
      return list.map((e) => ScheduledPayment.fromJson(e)).toList();
    } catch (_) {}
  }

  // ---------------- NOTHING WORKED ----------------
  return <ScheduledPayment>[];
}

Future<Dealer> fetchDealer(
  String dealerId,
  Future<Map<String, String>> Function() headerBuilder,
) async {
  final cacheKey = 'dealer:detail:$dealerId';

  final path = AppConfig.p(AppConfig.dealerByID, {'id': dealerId});
  final uri = AppConfig.u(path);

  // ---------------- TRY NETWORK FIRST ----------------
  try {
    final headers = await headerBuilder();
    final res = await http.get(uri, headers: headers);

    if (res.statusCode == 200) {
      await apiClient.cache?.put(
        cacheKey,
        CacheEntry(
          body: res.body,
          statusCode: res.statusCode,
          storedAtMillis: DateTime.now().millisecondsSinceEpoch,
        ),
      );

      final body = jsonDecode(res.body);
      return Dealer.fromJson(body['dealer']);
    }
  } catch (e) {
    // swallow and fallback to cache
  }

  // ---------------- FALLBACK TO CACHE ----------------
  final cached = apiClient.cache?.get(cacheKey);
  if (cached != null && cached.body.isNotEmpty) {
    try {
      final body = jsonDecode(cached.body);
      if (body['dealer'] is Map) {
        return Dealer.fromJson(body['dealer']);
      }
    } catch (_) {}
  }

  throw Exception('No internet and no cached dealer');
}
