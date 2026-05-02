// trip_details_screen.dart
import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:FieldService_app/config.dart';
import 'package:FieldService_app/services/secure_storage_service.dart';

class TripDetailsScreen extends StatefulWidget {
  final String tripId;

  // NEW: local-first data from Trips list
  final TripDetail? initial;

  const TripDetailsScreen({super.key, required this.tripId, this.initial});

  @override
  State<TripDetailsScreen> createState() => _TripDetailsScreenState();
}

class _TripDetailsScreenState extends State<TripDetailsScreen> {
  bool _loading = true;
  String? _error;
  TripDetail? _trip;

  @override
  void initState() {
    super.initState();

    // If we have data from the list screen, show it immediately
    if (widget.initial != null) {
      _trip = widget.initial;
      _loading = false;

      // Fire a silent background refresh to pull latest details
      unawaited(_fetchTrip(silent: true));
    } else {
      // Fallback: old behavior (should rarely happen in your flow)
      _fetchTrip();
    }
  }

  Future<void> _fetchTrip({bool retry = false, bool silent = false}) async {
    if (!mounted) return;
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    // Only block with "No Internet" if we have no initial trip
    if (!silent && _trip == null) {
      final conn = await (Connectivity().checkConnectivity());
      if (conn.contains(ConnectivityResult.none)) {
        setState(() {
          _error = "No Internet Connection";
          _loading = false;
        });
        return;
      }
    }

    try {
      //final prefs = await SharedPreferences.getInstance();
      //final token = prefs.getString('token') ?? prefs.getString('authToken');
      final token = await SecureStorageService.getToken();
      final path = AppConfig.tripDetailsById.replaceAll('{id}', widget.tripId);
      final uri = Uri.parse('${AppConfig.apiBase}$path');

      final resp = await http
          .get(
            uri,
            headers: token != null && token.isNotEmpty
                ? {
                    'Accept': 'application/json',
                    'Authorization': 'Bearer $token',
                  }
                : {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 10));

      if (resp.statusCode != 200) {
        setState(() {
          _error = 'Server returned ${resp.statusCode}';
          _loading = false;
        });
        return;
      }

      final Map<String, dynamic> data =
          jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _trip = TripDetail.fromJson(data);
        _loading = false;
      });
    } catch (e) {
      // Retry once (only if not silent)
      if (!silent && !retry) {
        await Future.delayed(const Duration(milliseconds: 300));
        if (!mounted) return;
        return _fetchTrip(retry: true);
      }

      if (!mounted) return;

      if (silent) {
        // Background refresh failed — keep existing UI
        debugPrint('TripDetails silent refresh failed: $e');
        return;
      }

      // Detect offline error inside catch (Timeout/dns)
      if (e.toString().contains("SocketException")) {
        setState(() {
          _error = "No Internet Connection";
          _loading = false;
        });
        return;
      }
      if (!mounted) return;
      setState(() {
        _error = "Failed to load trip";
        _loading = false;
      });
    }
  }

  String _formatDateShort(DateTime d) {
    return DateFormat('d MMM yyyy').format(d);
  }

  String _formatTime(DateTime d) {
    return DateFormat('h:mm a').format(d);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
            iconTheme: const IconThemeData(color: Colors.white),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
            ),
            title: const Text(
              'Trip Details',
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
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : (_error != null)
            ? _errorView()
            : _trip == null
            ? const Center(child: Text('No data'))
            : _content(context, theme),
      ),
    );
  }

  Widget _errorView() {
    final error = _error ?? 'Failed to load trip';
    final isNoInternet = error == "No Internet Connection";

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isNoInternet ? Icons.wifi_off_rounded : Icons.error_outline,
              size: 48,
              color: Colors.redAccent,
            ),
            const SizedBox(height: 12),
            Text(
              error,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red, fontSize: 16),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _fetchTrip(),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content(BuildContext ctx, ThemeData theme) {
    final t = _trip;
    if (t == null) return const Center(child: Text('No data'));

    final completed = t.endTime != null;
    final durationSeconds = t.durationSeconds;

    //if (durationSeconds != null) {
    final safeDurationSeconds = durationSeconds ?? 0;
    final hours = safeDurationSeconds ~/ 3600;
    final minutes = (safeDurationSeconds % 3600) ~/ 60;
    final seconds = safeDurationSeconds % 60;

    String durationText = '';

    if (hours > 0) {
      durationText += '${hours}h ';
    }

    if (minutes > 0 || hours > 0) {
      durationText += '${minutes}m ';
    }

    durationText += '${seconds}s';

    durationText = durationText.trim();
    //}

    final totalKm = t.totalKm;
    final incentive = t.incentive;
    final startTime = t.startTime;
    final endTime = t.endTime;
    final startLat = t.startLat;
    final startLon = t.startLon;
    final endLat = t.endLat;
    final endLon = t.endLon;
    final kmText = totalKm != null ? '${_formatKm(totalKm)} km' : '--';
    final isDark = theme.brightness == Brightness.dark;

    final cardBg = isDark ? const Color(0xFF111214) : Colors.white;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // header card (date + status + ride id)
          Container(
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Color(0xFF1AB69C), // your custom color
                width: 1.2, // ensure visibility
              ),

              boxShadow: isDark
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 8,
                      ),
                    ],
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _formatDateShort(t.tripDate),
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 22,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: completed
                              ? const Color(0xFF1AB69C)
                              : const Color(0xFFF59E0B),
                          borderRadius: BorderRadius.circular(50),
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            completed ? 'Completed' : 'Ongoing',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    _smallStat(
                      icon: Icons.route_rounded,
                      label: kmText,
                      dark: isDark,
                    ),
                    _smallStat(
                      icon: Icons.timer_rounded,
                      label: durationText,
                      dark: isDark,
                    ),
                    if (incentive != null)
                      _smallStat(
                        icon: Icons.currency_rupee_rounded,
                        label: "Rs ${incentive.toStringAsFixed(2)}",
                        dark: isDark,
                      ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // timeline card: start -> end
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0xFF1AB69C), width: 1.2),
            ),

            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(14.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // timeline visuals
                  Column(
                    children: [
                      SizedBox(height: 3),
                      _timelineDot(color: const Color(0xFF1AB69C)),
                      Container(
                        width: 2,
                        height: 131,
                        color: Colors.grey.shade200,
                      ),
                      _timelineDot(color: const Color(0xFFF59E0B)),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionHeader('Start location'),
                        const SizedBox(height: 8),
                        Text(
                          t.startLocationName ?? '—',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              Icons.access_time,
                              size: 14,
                              color: Color(0xFF1AB69C),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              startTime != null ? _formatTime(startTime) : '--',
                              style: TextStyle(
                                color: Colors.grey.shade700,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(width: 12),
                            if (startLat != null && startLon != null) ...[
                              Icon(
                                Icons.my_location,
                                size: 14,
                                color: Color(0xFF1AB69C),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${startLat.toStringAsFixed(3)}, ${startLon.toStringAsFixed(3)}',
                                style: TextStyle(
                                  color: Colors.grey.shade700,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 12),
                        Divider(height: 6, color: Color(0xFF1AB69C)),
                        const SizedBox(height: 12),
                        _sectionHeader('End location'),
                        const SizedBox(height: 8),
                        Text(
                          t.endLocationName ?? '—',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              Icons.access_time,
                              size: 14,
                              color: Color(0xFF1AB69C),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              endTime != null ? _formatTime(endTime) : '--',
                              style: TextStyle(
                                color: Colors.grey.shade700,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(width: 12),
                            if (endLat != null && endLon != null) ...[
                              Icon(
                                Icons.my_location,
                                size: 14,
                                color: Color(0xFF1AB69C),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${endLat.toStringAsFixed(3)}, ${endLon.toStringAsFixed(3)}',
                                style: TextStyle(
                                  color: Colors.grey.shade700,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 20),
                        if (totalKm != null)
                          Text(
                            '$durationText • ${_formatKm(totalKm)} km',
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          _purposeSummaryCard(t, isDark),

          const SizedBox(height: 16),

          _activityDataCard(t, isDark),

          const SizedBox(height: 18),

          // compact metrics row
          // Row(
          //   children: [
          //     Expanded(
          //       child: _infoTile(
          //         'Start KM',
          //         t.startKmReading != null
          //             ? _formatKm(t.startKmReading!)
          //             : '--',
          //       ),
          //     ),
          //     const SizedBox(width: 12),
          //     Expanded(
          //       child: _infoTile(
          //         'End KM',
          //         t.endKmReading != null ? _formatKm(t.endKmReading!) : '--',
          //       ),
          //     ),
          //     const SizedBox(width: 12),
          //     Expanded(
          //       child: _infoTile(
          //         'Total KM',
          //         t.totalKm != null ? _formatKm(t.totalKm!) : '--',
          //       ),
          //     ),
          //   ],
          // ),

          // const SizedBox(height: 18),

          // subtle help card
          // Container(
          //   decoration: BoxDecoration(
          //     color: Theme.of(context).brightness == Brightness.dark
          //         ? Colors.white.withValues(alpha: 0.03)
          //         : Colors.grey.shade100,
          //     borderRadius: BorderRadius.circular(12),
          //   ),
          //   padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          //   child: Row(
          //     children: [
          //       Container(
          //         padding: const EdgeInsets.all(10),
          //         decoration: BoxDecoration(
          //           color: Colors.blue.shade50,
          //           shape: BoxShape.circle,
          //         ),
          //         child: Icon(
          //           Icons.headset_mic,
          //           color: Colors.blue.shade700,
          //           size: 18,
          //         ),
          //       ),
          //       const SizedBox(width: 12),
          //       Expanded(
          //         child: Text(
          //           'Need help? We\'re a tap away',
          //           style: TextStyle(color: Colors.grey.shade800),
          //         ),
          //       ),
          //       const Icon(Icons.chevron_right, color: Colors.grey),
          //     ],
          //   ),
          // ),

          //const SizedBox(height: 18),

          // Close button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(
                  0xFF1AB69C,
                ), // FIXED BACKGROUND COLOR
                foregroundColor: Colors.white, // text/icon color
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text(
                'Close',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // small helpers & widgets
  Widget _purposeSummaryCard(TripDetail t, bool isDark) {
    if (t.purposes.isEmpty) return const SizedBox.shrink();

    return _detailCard(
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(Icons.task_alt_rounded, 'Purposes'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: t.purposes
                .map(
                  (p) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1AB69C).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: const Color(0xFF1AB69C).withValues(alpha: 0.35),
                      ),
                    ),
                    child: Text(
                      p,
                      style: const TextStyle(
                        color: Color(0xFF1AB69C),
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _activityDataCard(TripDetail t, bool isDark) {
    final sections = <Widget>[
      if (t.orders.isNotEmpty)
        _activitySection(
          title: 'Orders',
          icon: Icons.shopping_cart_rounded,
          count: t.orders.length,
          children: t.orders.map(_orderTile).toList(),
        ),
      if (t.payments.isNotEmpty)
        _activitySection(
          title: 'Payments',
          icon: Icons.payment_rounded,
          count: t.payments.length,
          children: t.payments.map(_paymentTile).toList(),
        ),
      if (t.dealerTickets.isNotEmpty)
        _activitySection(
          title: 'Dealer Tickets',
          icon: Icons.confirmation_number_rounded,
          count: t.dealerTickets.length,
          children: t.dealerTickets.map(_dealerTicketTile).toList(),
        ),
      if (t.farmerTickets.isNotEmpty)
        _activitySection(
          title: 'Farmer Tickets',
          icon: Icons.support_agent_rounded,
          count: t.farmerTickets.length,
          children: t.farmerTickets.map(_farmerTicketTile).toList(),
        ),
      if (t.visits.isNotEmpty)
        _activitySection(
          title: 'Other Visits',
          icon: Icons.place_rounded,
          count: t.visits.length,
          children: t.visits.map(_visitTile).toList(),
        ),
    ];

    if (sections.isEmpty) {
      return _detailCard(
        isDark: isDark,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(Icons.inventory_2_outlined, 'Trip Activity'),
            const SizedBox(height: 12),
            Text(
              'No activity data available for this trip.',
              style: TextStyle(color: Colors.grey.shade700),
            ),
          ],
        ),
      );
    }

    return _detailCard(
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(Icons.inventory_2_rounded, 'Trip Activity'),
          const SizedBox(height: 12),
          ..._separated(sections, const SizedBox(height: 14)),
        ],
      ),
    );
  }

  Widget _detailCard({required bool isDark, required Widget child}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF111214) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1AB69C), width: 1.2),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 8,
                ),
              ],
      ),
      padding: const EdgeInsets.all(14),
      child: child,
    );
  }

  Widget _sectionTitle(IconData icon, String title) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: const Color(0xFF1AB69C).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: const Color(0xFF1AB69C), size: 18),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
        ),
      ],
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _activitySection({
    required String title,
    required IconData icon,
    required int count,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: const Color(0xFF1AB69C), size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$title ($count)',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ..._separated(children, const Divider(height: 18)),
      ],
    );
  }

  Widget _orderTile(Map<String, dynamic> item) {
    final orderId = _textOf(item, ['orderId', '_id']);
    final status = _textOf(item, ['status']);
    final total = _numOf(item, ['finalAmount', 'totalAmount']);
    final items = _listOf(item['items']);
    return _activityTile(
      title: orderId.isNotEmpty ? orderId : 'Order',
      subtitle: '${items.length} item${items.length == 1 ? '' : 's'}',
      trailing: total != null ? 'Rs ${total.toStringAsFixed(2)}' : status,
      status: status,
    );
  }

  Widget _paymentTile(Map<String, dynamic> item) {
    final title = _textOf(item, ['paymentId', 'title', '_id']);
    final amount = _numOf(item, ['amount', 'paidAmount']);
    final status = _textOf(item, ['status']);
    return _activityTile(
      title: title.isNotEmpty ? title : 'Payment',
      subtitle: _textOf(item, ['body', 'remarks', 'note']),
      trailing: amount != null ? 'Rs ${amount.toStringAsFixed(2)}' : status,
      status: status,
    );
  }

  Widget _dealerTicketTile(Map<String, dynamic> item) {
    final status = _textOf(item, ['status']);
    return _activityTile(
      title: _textOf(item, [
        'dealerTicketId',
        '_id',
      ], fallback: 'Dealer Ticket'),
      subtitle: _textOf(item, ['remarks', 'dealerName', 'dealerLocation']),
      trailing: _formatIsoDate(_textOf(item, ['createdAt', 'updatedAt'])),
      status: status,
    );
  }

  Widget _farmerTicketTile(Map<String, dynamic> item) {
    final ponds = _listOf(item['ponds']);
    final remarks = _textOf(item, ['remarks', 'farmerName', 'address']);
    final subtitle = [
      if (remarks.isNotEmpty) remarks,
      if (ponds.isNotEmpty)
        '${ponds.length} pond${ponds.length == 1 ? '' : 's'}',
    ].join(' • ');
    final status = _textOf(item, ['status']);

    return _activityTile(
      title: _textOf(item, [
        'farmerTicketId',
        'ticketId',
        '_id',
      ], fallback: 'Farmer Ticket'),
      subtitle: subtitle,
      trailing: _formatIsoDate(_textOf(item, ['createdAt', 'updatedAt'])),
      status: status,
    );
  }

  Widget _visitTile(Map<String, dynamic> item) {
    return _activityTile(
      title: _textOf(item, ['purpose'], fallback: 'Other Visit'),
      subtitle: _textOf(item, ['reason', 'address']),
      trailing: _formatIsoDate(_textOf(item, ['visitDate', 'createdAt'])),
      status: _textOf(item, ['idOfVisitor.type']),
    );
  }

  Widget _activityTile({
    required String title,
    required String subtitle,
    required String trailing,
    required String status,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                ),
              ),
              if (subtitle.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 12.5),
                ),
              ],
              if (status.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                _statusChip(status),
              ],
            ],
          ),
        ),
        if (trailing.trim().isNotEmpty) ...[
          const SizedBox(width: 10),
          Text(
            trailing,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
          ),
        ],
      ],
    );
  }

  Widget _statusChip(String status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF1AB69C).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status,
        style: const TextStyle(
          color: Color(0xFF1AB69C),
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  List<Widget> _separated(List<Widget> children, Widget separator) {
    if (children.isEmpty) return const [];
    return [
      for (int i = 0; i < children.length; i++) ...[
        if (i > 0) separator,
        children[i],
      ],
    ];
  }

  String _formatIsoDate(String value) {
    if (value.trim().isEmpty) return '';
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return value;
    return DateFormat('d MMM').format(parsed.toLocal());
  }

  String _textOf(
    Map<String, dynamic> item,
    List<String> keys, {
    String fallback = '',
  }) {
    for (final key in keys) {
      dynamic value = item;
      for (final part in key.split('.')) {
        if (value is Map) {
          value = value[part];
        } else {
          value = null;
          break;
        }
      }
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString();
      }
    }
    return fallback;
  }

  double? _numOf(Map<String, dynamic> item, List<String> keys) {
    for (final key in keys) {
      final value = item[key];
      if (value is num) return value.toDouble();
      if (value != null) {
        final parsed = double.tryParse(value.toString());
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  List<Map<String, dynamic>> _listOf(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
  }

  Widget _sectionHeader(String text) {
    return Row(
      children: [
        // Container(
        //   width: 4,
        //   height: 20,
        //   decoration: BoxDecoration(
        //     color: Theme.of(context).primaryColor,
        //     borderRadius: BorderRadius.circular(4),
        //   ),
        // ),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
        ),
      ],
    );
  }

  Widget _timelineDot({required Color color}) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 4),
        ],
      ),
    );
  }

  Widget _smallStat({
    required IconData icon,
    required String label,
    required bool dark,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: dark ? Colors.white : Color((0xFF1AB69C)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 16,
            color: dark ? Colors.white : Colors.white,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: dark ? Colors.white : Colors.black87,
          ),
        ),
      ],
    );
  }

  String _formatKm(double v) {
    // up to 3 decimals - if whole, show no decimals
    if (v % 1 == 0) return v.toStringAsFixed(0);
    return v.toStringAsFixed(3);
  }
}

// Minimal TripDetail model
class TripDetail {
  final double? startLat;
  final double? startLon;
  final double? endLat;
  final double? endLon;
  final String id;
  final String? companyId;
  final DateTime tripDate;
  final DateTime? startTime;
  final DateTime? endTime;
  final String? startLocationName;
  final String? endLocationName;
  final double? startKmReading;
  final double? endKmReading;
  final double? totalKm;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final int? ticketsCount;
  final double? incentive; // NEW FIELD
  final String employeeName;
  final String employeeCode;
  final String employeeEmail;
  final String employeeContact;
  final List<String> purposes;
  final List<Map<String, dynamic>> orders;
  final List<Map<String, dynamic>> payments;
  final List<Map<String, dynamic>> farmerTickets;
  final List<Map<String, dynamic>> dealerTickets;
  final List<Map<String, dynamic>> visits;

  TripDetail({
    required this.id,
    required this.tripDate,
    this.startTime,
    this.endTime,
    this.startLat,
    this.startLon,
    this.endLat,
    this.endLon,
    this.companyId,
    this.startLocationName,
    this.endLocationName,
    this.startKmReading,
    this.endKmReading,
    this.totalKm,
    this.createdAt,
    this.updatedAt,
    this.ticketsCount,
    this.incentive,
    this.employeeName = '',
    this.employeeCode = '',
    this.employeeEmail = '',
    this.employeeContact = '',
    this.purposes = const [],
    this.orders = const [],
    this.payments = const [],
    this.farmerTickets = const [],
    this.dealerTickets = const [],
    this.visits = const [],
  });

  int? get durationSeconds {
    final start = startTime;
    final end = endTime;
    if (start != null && end != null) {
      return end.difference(start).inSeconds;
    }
    return null;
  }

  factory TripDetail.fromJson(Map<String, dynamic> json) {
    double? parseNum(dynamic v) {
      if (v == null) return null;
      try {
        return double.parse(v.toString());
      } catch (_) {
        if (v is num) return v.toDouble();
      }
      return null;
    }

    DateTime? parseDate(dynamic v) {
      if (v == null) return null;
      try {
        return DateTime.parse(v.toString()).toLocal();
      } catch (_) {
        return null;
      }
    }

    Map<String, dynamic> mapOf(dynamic value) {
      if (value is Map) return value.cast<String, dynamic>();
      return const {};
    }

    List<Map<String, dynamic>> listOfMaps(dynamic value) {
      if (value is! List) return const [];
      return value
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
    }

    final tripJson = mapOf(json['trip']).isNotEmpty
        ? mapOf(json['trip'])
        : json;
    final employeeJson = mapOf(json['employee']);
    final dataJson = mapOf(json['data']);
    final startLoc = mapOf(tripJson['startLocation']);
    final endLoc = mapOf(tripJson['endLocation']);
    final rawPurposes = json['purpose'];
    final purposes = rawPurposes is List
        ? rawPurposes
              .map((e) => e?.toString().trim() ?? '')
              .where((e) => e.isNotEmpty)
              .toList()
        : <String>[];
    final employeeName = [
      employeeJson['firstName']?.toString().trim() ?? '',
      employeeJson['lastName']?.toString().trim() ?? '',
    ].where((e) => e.isNotEmpty).join(' ');

    return TripDetail(
      id: tripJson['_id']?.toString() ?? '',
      tripDate: parseDate(tripJson['tripDate']) ?? DateTime.now(),
      startTime: parseDate(tripJson['startTime']),
      endTime: parseDate(tripJson['endTime']),
      startLat: parseNum(
        startLoc['latitude'] ?? startLoc['lat'] ?? startLoc['latitide'],
      ),
      startLon: parseNum(
        startLoc['longitude'] ?? startLoc['lon'] ?? startLoc['long'],
      ),
      endLat: parseNum(endLoc['latitude'] ?? endLoc['lat']),
      endLon: parseNum(endLoc['longitude'] ?? endLoc['lon'] ?? endLoc['long']),
      companyId: tripJson['companyId']?.toString(),
      startLocationName: tripJson['startLocationName']?.toString(),
      endLocationName: tripJson['endLocationName']?.toString(),
      startKmReading: parseNum(tripJson['startKmReading']),
      endKmReading: parseNum(tripJson['endKmReading']),
      totalKm: parseNum(tripJson['totalKm'] ?? tripJson['distance']),
      incentive: parseNum(tripJson['incentive']), // NEW
      createdAt: parseDate(tripJson['createdAt']),
      updatedAt: parseDate(tripJson['updatedAt']),
      ticketsCount: int.tryParse(tripJson['ticketsCount']?.toString() ?? ''),
      employeeName: employeeName,
      employeeCode: employeeJson['empCode']?.toString() ?? '',
      employeeEmail: employeeJson['email']?.toString() ?? '',
      employeeContact: employeeJson['contactNumber']?.toString() ?? '',
      purposes: purposes,
      orders: listOfMaps(dataJson['orders']),
      payments: listOfMaps(dataJson['payments']),
      farmerTickets: listOfMaps(dataJson['farmerTickets']),
      dealerTickets: listOfMaps(dataJson['dealerTickets']),
      visits: listOfMaps(dataJson['visits']),
    );
  }
}
