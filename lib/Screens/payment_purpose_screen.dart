// File: payment_purpose_screen.dart
// Standalone screen extracted from DealerVisitScreen — contains the full Payment Purpose UI & logic

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:FieldService_app/services/notification_api.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart'; // Clipboard

class PaymentPurposeScreen extends StatefulWidget {
  final String dealerId;
  final String dealerName;
  final String shopName;
  final String address;
  final String mobile;
  final double latitude;
  final double longitude;
  final double pendingAmount;

  const PaymentPurposeScreen({
    super.key,
    required this.dealerId,
    required this.dealerName,
    required this.shopName,
    required this.address,
    required this.mobile,
    required this.latitude,
    required this.longitude,
    required this.pendingAmount, // ✅ ADD
  });

  @override
  State<PaymentPurposeScreen> createState() => _PaymentPurposeScreenState();
}

class _PaymentPurposeScreenState extends State<PaymentPurposeScreen> {
  final Color appGreen = const Color(0xFF1AB69C);
  DateTime? _commitDate;
  TimeOfDay? _commitTime;
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Uri _webDirectionsUri() => Uri.parse(
    'https://www.google.com/maps/dir/?api=1&destination=${widget.latitude},${widget.longitude}&travelmode=driving',
  );

  Uri _iosGoogleMapsUri() => Uri.parse(
    'comgooglemaps://?daddr=${widget.latitude},${widget.longitude}&directionsmode=driving',
  );

  Future<void> _openDirections() async {
    final gmapsUrl = _iosGoogleMapsUri();
    final webUrl = _webDirectionsUri();

    if (Theme.of(context).platform == TargetPlatform.iOS &&
        await canLaunchUrl(gmapsUrl)) {
      await launchUrl(gmapsUrl, mode: LaunchMode.externalApplication);
      return;
    }
    if (await canLaunchUrl(webUrl)) {
      await launchUrl(webUrl, mode: LaunchMode.externalApplication);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open Maps'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _callDealer() async {
    final phone = widget.mobile.trim();
    if (phone.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No mobile number found'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open dialer'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _copyAddress() async {
    final coords = '${widget.latitude}, ${widget.longitude}';
    await Clipboard.setData(ClipboardData(text: coords));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Coordinates copied'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _commitDate ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 3)),
    );
    if (picked != null) setState(() => _commitDate = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _commitTime ?? TimeOfDay.now(),
    );
    if (picked != null) setState(() => _commitTime = picked);
  }

  Future<void> _savePaymentCommitment() async {
    if (!_formKey.currentState!.validate()) return;

    if (_commitDate == null || _commitTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pick commitment date & time'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final localDt = DateTime(
      _commitDate!.year,
      _commitDate!.month,
      _commitDate!.day,
      _commitTime!.hour,
      _commitTime!.minute,
    );

    if (!localDt.isAfter(DateTime.now())) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Choose a future time'),
          content: Text(
            'The selected date & time '
            '(${_commitDate!.day}/${_commitDate!.month}/${_commitDate!.year} '
            '${_commitTime!.format(context)}) is in the past.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    String formatINR(num n) {
      final isNeg = n < 0;
      final abs = n.abs();
      final str = abs.toStringAsFixed(abs % 1 == 0 ? 0 : 2);
      final parts = str.split('.');
      var intPart = parts[0];
      final decPart = parts.length > 1 ? '.${parts[1]}' : '';
      if (intPart.length > 3) {
        final last3 = intPart.substring(intPart.length - 3);
        var rest = intPart.substring(0, intPart.length - 3);
        final buf = <String>[];
        while (rest.length > 2) {
          buf.insert(0, rest.substring(rest.length - 2));
          rest = rest.substring(0, rest.length - 2);
        }
        if (rest.isNotEmpty) buf.insert(0, rest);
        intPart = '${buf.join(',')},$last3';
      }
      return '${isNeg ? '-₹' : '₹'}$intPart$decPart';
    }

    String whenLocalText0(DateTime dt) {
      final d = dt.toLocal();
      const dayAbbr = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      const monAbbr = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      final dow = dayAbbr[d.weekday - 1];
      final mon = monAbbr[d.month - 1];
      final use24h = MediaQuery.of(context).alwaysUse24HourFormat;
      final mm = d.minute.toString().padLeft(2, '0');
      String time;
      if (use24h) {
        final hh = d.hour.toString().padLeft(2, '0');
        time = '$hh:$mm';
      } else {
        final isPM = d.hour >= 12;
        var h12 = d.hour % 12;
        if (h12 == 0) h12 = 12;
        time = '$h12:$mm ${isPM ? 'PM' : 'AM'}';
      }
      final tzAbbr = d.timeZoneName;
      return '$dow, ${d.day} $mon ${d.year}, $time $tzAbbr';
    }

    final sendAtUtc = localDt.toUtc().toIso8601String();
    final amount = num.tryParse(_amountCtrl.text.trim()) ?? 0;
    final title = widget.dealerName;
    final note = _noteCtrl.text.trim();
    final whenLocalText = whenLocalText0(localDt);
    [
      formatINR(amount),
      if (widget.shopName.trim().isNotEmpty) widget.shopName.trim(),
      whenLocalText,
      if (note.isNotEmpty) note,
    ].join(' · ');

    if (mounted) setState(() => _saving = true);
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to get device push token. Try again.'),
            duration: Duration(seconds: 2),
          ),
        );
        return;
      }

      final res = await NotificationsApi.schedule(
        title: title,
        dealerId: widget.dealerId,
        dealerName: widget.dealerName,
        shopName: widget.shopName,
        amount: amount,
        mobile: widget.mobile,
        body: note,
        fcmToken: token,
        sendAtUtc: sendAtUtc,
      );

      if (!mounted) return;
      if (res.success) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Reminder saved'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Color(0xFF1AB69C),
          ),
        );
        _amountCtrl.clear();
        _noteCtrl.clear();
        setState(() {
          _commitDate = null;
          _commitTime = null;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              res.message.isEmpty ? 'Failed to schedule' : res.message,
            ),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          duration: Duration(seconds: 2),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      if (widget.shopName.trim().isNotEmpty) widget.shopName.trim(),
      if (widget.mobile.trim().isNotEmpty) widget.mobile.trim(),
    ].join(' • ');

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
              'Schedule Payment',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
          ),
        ),
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _dealerHeaderCard(subtitle),
            const SizedBox(height: 32),
            _paymentForm(),
          ],
        ),
      ),
    );
  }

  Widget _dealerHeaderCard(String subtitle) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Color(0xFF1AB69C),
            blurRadius: 3,
            offset: const Offset(0, 0.5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Color.fromARGB(255, 144, 252, 234),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(Icons.store_rounded, color: Color(0xFF1AB69C)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.dealerName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 12.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.place, size: 18, color: Color(0xFF1AB69C)),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.address.trim().isNotEmpty)
                      Text(
                        widget.address,
                        style: const TextStyle(color: Colors.black87),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: 4),
                    Text(
                      '(${widget.latitude}, ${widget.longitude})',
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
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
                  final pending =
                      widget.pendingAmount; // already parsed in model
                  final noDue = pending <= 0.0;
                  // safe debug print of numeric value
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
                        fontSize: 18,
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
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _openDirections,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFF1AB69C),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.directions_rounded),
                  label: const Text('Get Directions'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _callDealer,
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Color(0xFF1AB69C)),
                    foregroundColor: Color(0xFF1AB69C),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.call_rounded),
                  label: const Text('Call'),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: 'Copy coordinates',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: _copyAddress,
                    child: Container(
                      width: 44,
                      height: 54,
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.grey.withValues(alpha: 0.15),
                        ),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(Icons.copy_all_rounded, size: 22),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _paymentForm() {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          TextFormField(
            controller: _amountCtrl,
            keyboardType: TextInputType.number,
            decoration: _dec('Amount (₹)'),
            validator: (v) {
              final s = (v ?? '').trim();
              if (s.isEmpty) return 'Amount is required';
              if (double.tryParse(s) == null) return 'Enter a valid amount';
              return null;
            },
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(
                      color: Color(0xFF1AB69C),
                      width: 1.5,
                    ),
                  ),
                  onPressed: _pickDate,
                  icon: const Icon(
                    Icons.calendar_today,
                    color: Color(0xFF1AB69C),
                  ),
                  label: Text(
                    _commitDate == null
                        ? 'Pick date'
                        : '${_commitDate!.day}/${_commitDate!.month}/${_commitDate!.year}',
                    style: const TextStyle(color: Colors.black),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(
                      color: Color(0xFF1AB69C),
                      width: 1.5,
                    ),
                  ),
                  onPressed: _pickTime,
                  icon: const Icon(Icons.access_time, color: Color(0xFF1AB69C)),
                  label: Text(
                    _commitTime == null
                        ? 'Pick time'
                        : _commitTime!.format(context),
                    style: const TextStyle(color: Colors.black),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),
          TextFormField(
            controller: _noteCtrl,
            maxLines: 3,
            decoration: _dec('Notes (Required)'),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _saving ? null : _savePaymentCommitment,
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFF1AB69C),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                minimumSize: const Size.fromHeight(48),
              ),
              icon: _saving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_saving ? 'Saving...' : 'Save Reminder'),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _dec(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Colors.grey.withValues(alpha: 0.06),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: appGreen, width: 1.4),
      ),
    );
  }
}
