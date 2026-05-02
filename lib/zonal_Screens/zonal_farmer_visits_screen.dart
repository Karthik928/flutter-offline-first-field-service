import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:FieldService_app/config.dart';
import 'package:FieldService_app/services/secure_storage_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Model  (mirrors the dealer screen — isolated to keep files self-contained)
// ─────────────────────────────────────────────────────────────────────────────

class _FarmerVisitGroup {
  final String employeeId;
  final String firstName;
  final String lastName;
  final String empCode;
  final String profilePhoto;
  final List<Map<String, dynamic>> visits;

  const _FarmerVisitGroup({
    required this.employeeId,
    required this.firstName,
    required this.lastName,
    required this.empCode,
    required this.profilePhoto,
    required this.visits,
  });

  String get fullName => '$firstName $lastName'.trim();
}

class _FlatFarmerVisit {
  final _FarmerVisitGroup group;
  final Map<String, dynamic> visitData;

  const _FlatFarmerVisit({required this.group, required this.visitData});

  Map<String, dynamic>? get visit =>
      visitData['visit'] as Map<String, dynamic>?;

  String get visitId => visit?['id']?.toString() ?? '';
  String get visitType => visit?['visitType']?.toString() ?? 'Visit';

  Map<String, dynamic>? get customer =>
      visit?['customer'] as Map<String, dynamic>?;
  String get customerName => customer?['name']?.toString() ?? '—';
  String get customerMobile => customer?['mobile']?.toString() ?? '—';

  String get purpose => visit?['purpose']?.toString() ?? '—';

  String get rawDate => visit?['date']?.toString() ?? '';
  String get formattedDate {
    try {
      final dt = DateTime.parse(rawDate).toLocal();
      const months = [
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
      final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final m = dt.minute.toString().padLeft(2, '0');
      final ampm = dt.hour >= 12 ? 'PM' : 'AM';
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year}  •  $h:$m $ampm';
    } catch (_) {
      return rawDate;
    }
  }

  List<Map<String, dynamic>> get orders =>
      (visitData['orders'] as List<dynamic>?)
          ?.whereType<Map<String, dynamic>>()
          .toList() ??
      [];

  List<Map<String, dynamic>> get payments =>
      (visitData['payments'] as List<dynamic>?)
          ?.whereType<Map<String, dynamic>>()
          .toList() ??
      [];

  List<Map<String, dynamic>> get tickets =>
      (visitData['tickets'] as List<dynamic>?)
          ?.whereType<Map<String, dynamic>>()
          .toList() ??
      [];
}

// ─────────────────────────────────────────────────────────────────────────────
// Screen — Farmer Visits
// ─────────────────────────────────────────────────────────────────────────────

class ZonalFarmerVisitsScreen extends StatefulWidget {
  const ZonalFarmerVisitsScreen({super.key});

  @override
  State<ZonalFarmerVisitsScreen> createState() =>
      _ZonalFarmerVisitsScreenState();
}

class _ZonalFarmerVisitsScreenState extends State<ZonalFarmerVisitsScreen>
    with SingleTickerProviderStateMixin {
  static const _gradientStart = Color(0xFF52D494);
  static const _gradientEnd = Color(0xFF1AB69C);
  static const _accent = Color(0xFF1AB69C);

  bool _isLoading = true;
  String? _errorMessage;
  List<_FlatFarmerVisit> _flatVisits = [];
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _fetchVisits();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  // ── API ───────────────────────────────────────────────────────────────────

  Future<void> _fetchVisits() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final token = await SecureStorageService.getToken();
      if (token == null || token.isEmpty) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Authentication required. Please log in again.';
        });
        return;
      }

      final uri = AppConfig.u(AppConfig.zonalAllVisits);
      final response = await http
          .get(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;

      if (response.statusCode == 401) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Session expired. Please log in again.';
        });
        return;
      }

      if (response.statusCode != 200 && response.statusCode != 201) {
        setState(() {
          _isLoading = false;
          _errorMessage =
              'Failed to load visits (${response.statusCode}). Please try again.';
        });
        return;
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final dataList = decoded['data'] as List<dynamic>? ?? [];

      final List<_FlatFarmerVisit> flat = [];

      for (final item in dataList) {
        if (item is! Map<String, dynamic>) continue;
        final emp = item['employee'] as Map<String, dynamic>? ?? {};
        final farmerVisits =
            (item['farmerVisits'] as List<dynamic>?)
                ?.cast<Map<String, dynamic>>() ??
            [];

        if (farmerVisits.isEmpty) continue;

        final group = _FarmerVisitGroup(
          employeeId: emp['_id']?.toString() ?? '',
          firstName: emp['firstName']?.toString() ?? '',
          lastName: emp['lastName']?.toString() ?? '',
          empCode: emp['empCode']?.toString() ?? '',
          profilePhoto: emp['profilePhoto']?.toString() ?? '',
          visits: farmerVisits,
        );

        for (final v in farmerVisits) {
          flat.add(_FlatFarmerVisit(group: group, visitData: v));
        }
      }

      setState(() {
        _flatVisits = flat;
        _isLoading = false;
      });

      _fadeController.forward();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Network error. Please check your connection.';
      });
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F6F3),
      appBar: _buildAppBar(),
      body: _buildBody(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(60),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [_gradientStart, _gradientEnd],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
        ),
        child: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
          ),
          leading: IconButton(
            icon: const Icon(
              Icons.arrow_back_sharp,
              color: Colors.white,
              size: 20,
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: const Text(
            'Farmer Visits',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          actions: [
            if (!_isLoading && _errorMessage == null)
              Container(
                margin: const EdgeInsets.only(right: 16),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${_flatVisits.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return _buildLoader();
    if (_errorMessage != null) return _buildError();
    if (_flatVisits.isEmpty) return _buildEmpty();
    return _buildList();
  }

  Widget _buildLoader() {
    return const Center(
      child: CircularProgressIndicator(
        valueColor: AlwaysStoppedAnimation<Color>(_accent),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.wifi_off_rounded,
                size: 36,
                color: Colors.red.shade400,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                color: Colors.black54,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _fetchVisits,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.agriculture_outlined,
              size: 40,
              color: _accent,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'No farmer visits found',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Farmer visits made by your team\nwill appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        itemCount: _flatVisits.length,
        itemBuilder: (context, index) {
          return _FarmerVisitCard(flatVisit: _flatVisits[index], index: index);
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Farmer Visit Card
// ─────────────────────────────────────────────────────────────────────────────

class _FarmerVisitCard extends StatefulWidget {
  final _FlatFarmerVisit flatVisit;
  final int index;

  const _FarmerVisitCard({required this.flatVisit, required this.index});

  @override
  State<_FarmerVisitCard> createState() => _FarmerVisitCardState();
}

class _FarmerVisitCardState extends State<_FarmerVisitCard>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late AnimationController _expandController;
  late Animation<double> _expandAnimation;

  @override
  void initState() {
    super.initState();
    _expandController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _expandAnimation = CurvedAnimation(
      parent: _expandController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _expandController.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    _expanded ? _expandController.forward() : _expandController.reverse();
  }

  String _fmtAmount(dynamic v) {
    final d = double.tryParse(v?.toString() ?? '') ?? 0.0;
    if (d >= 1e5) return '₹${(d / 1e5).toStringAsFixed(2)}L';
    if (d >= 1e3) return '₹${(d / 1e3).toStringAsFixed(1)}K';
    return '₹${d.toStringAsFixed(0)}';
  }

  @override
  Widget build(BuildContext context) {
    final fv = widget.flatVisit;
    final hasDetails =
        fv.orders.isNotEmpty || fv.payments.isNotEmpty || fv.tickets.isNotEmpty;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 350 + widget.index * 60),
      curve: Curves.easeOut,
      builder: (context, val, child) {
        return Opacity(
          opacity: val,
          child: Transform.translate(
            offset: Offset(0, 24 * (1 - val)),
            child: child,
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          children: [
            // ── Main tappable area ───────────────────────────────────────
            InkWell(
              onTap: hasDetails ? _toggle : null,
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Employee row ───────────────────────────────────
                    _FarmerEmployeeRow(group: fv.group),
                    const SizedBox(height: 14),
                    const Divider(
                      height: 1,
                      thickness: 1,
                      color: Color(0xFFF0F0F0),
                    ),
                    const SizedBox(height: 14),

                    // ── Visit type + date ─────────────────────────────
                    Row(
                      children: [
                        _TypeBadge(
                          label: fv.visitType,
                          color: const Color(0xFF1B5E20),
                          bgColor: const Color(0xFFE8F5E9),
                        ),
                        const Spacer(),
                        Icon(
                          Icons.access_time_rounded,
                          size: 13,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          fv.formattedDate,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // ── Farmer name + phone ───────────────────────────
                    Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF388E3C,
                            ).withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.agriculture_outlined,
                            size: 20,
                            color: Color(0xFF388E3C),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                fv.customerName,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Icon(
                                    Icons.phone_outlined,
                                    size: 12,
                                    color: Colors.grey[500],
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    fv.customerMobile,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[500],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // ── Purpose ───────────────────────────────────────
                    _InfoRow(
                      icon: Icons.eco_outlined,
                      label: 'Purpose',
                      value: fv.purpose,
                    ),

                    // ── Stats row ─────────────────────────────────────
                    if (hasDetails) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _StatChip(
                            label: 'Orders',
                            count: fv.orders.length,
                            color: const Color(0xFF1565C0),
                          ),
                          const SizedBox(width: 8),
                          _StatChip(
                            label: 'Payments',
                            count: fv.payments.length,
                            color: const Color(0xFF2E7D32),
                          ),
                          const SizedBox(width: 8),
                          _StatChip(
                            label: 'Tickets',
                            count: fv.tickets.length,
                            color: const Color(0xFFE65100),
                          ),
                          const Spacer(),
                          AnimatedRotation(
                            turns: _expanded ? 0.5 : 0,
                            duration: const Duration(milliseconds: 260),
                            child: Icon(
                              Icons.keyboard_arrow_down_rounded,
                              color: Colors.grey[400],
                              size: 22,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // ── Expandable details ───────────────────────────────────────
            SizeTransition(
              sizeFactor: _expandAnimation,
              child: Column(
                children: [
                  const Divider(
                    height: 1,
                    thickness: 1,
                    color: Color(0xFFF0F0F0),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (fv.orders.isNotEmpty) ...[
                          _SectionHeader(
                            icon: Icons.shopping_bag_outlined,
                            label: 'Orders',
                          ),
                          const SizedBox(height: 8),
                          ...fv.orders.map(
                            (o) => _OrderTile(order: o, fmtAmount: _fmtAmount),
                          ),
                        ],
                        if (fv.payments.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          _SectionHeader(
                            icon: Icons.payment_outlined,
                            label: 'Payments',
                          ),
                          const SizedBox(height: 8),
                          ...fv.payments.map((p) => _PaymentTile(payment: p)),
                        ],
                        if (fv.tickets.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          _SectionHeader(
                            icon: Icons.support_agent_outlined,
                            label: 'Tickets',
                          ),
                          const SizedBox(height: 8),
                          ...fv.tickets.map((t) => _TicketTile(ticket: t)),
                        ],
                      ],
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
}

// ─────────────────────────────────────────────────────────────────────────────
// Farmer-specific employee row  (green tint vs teal in dealer screen)
// ─────────────────────────────────────────────────────────────────────────────

class _FarmerEmployeeRow extends StatelessWidget {
  final _FarmerVisitGroup group;
  const _FarmerEmployeeRow({required this.group});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [Color(0xFF66BB6A), Color(0xFF388E3C)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(
              color: const Color(0xFF388E3C).withValues(alpha: 0.3),
              width: 1.5,
            ),
          ),
          child: Center(
            child: Text(
              group.firstName.isNotEmpty
                  ? group.firstName[0].toUpperCase()
                  : '?',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                group.fullName,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
              Text(
                group.empCode,
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
            ],
          ),
        ),
        // Container(
        //   padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        //   decoration: BoxDecoration(
        //     color: const Color(0xFF388E3C).withValues(alpha: 0.10),
        //     borderRadius: BorderRadius.circular(20),
        //   ),
        //   child: const Text(
        //     'Field Rep',
        //     style: TextStyle(
        //       fontSize: 10,
        //       fontWeight: FontWeight.w700,
        //       color: Color(0xFF388E3C),
        //     ),
        //   ),
        // ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared sub-widgets (duplicated here so each file is fully self-contained)
// ─────────────────────────────────────────────────────────────────────────────

class _TypeBadge extends StatelessWidget {
  final String label;
  final Color color;
  final Color bgColor;

  const _TypeBadge({
    required this.label,
    required this.color,
    required this.bgColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: Colors.grey[400]),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.grey[500],
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
        ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _StatChip({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$count $label',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SectionHeader({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: const Color(0xFF1AB69C)),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }
}

class _OrderTile extends StatelessWidget {
  final Map<String, dynamic> order;
  final String Function(dynamic) fmtAmount;

  const _OrderTile({required this.order, required this.fmtAmount});

  Color _statusColor(String s) {
    switch (s.toLowerCase()) {
      case 'delivered':
        return const Color(0xFF2E7D32);
      case 'shipped':
        return const Color(0xFF1565C0);
      case 'confirmed':
        return const Color(0xFF1AB69C);
      case 'pending':
        return const Color(0xFFF59E0B);
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final orderId = order['orderId']?.toString() ?? '—';
    final status = order['status']?.toString() ?? '—';
    final totalAmount = order['totalAmount'];
    final items = (order['items'] as List<dynamic>?)?.length ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FFFE),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0F2F1)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFF1AB69C).withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.receipt_outlined,
              size: 17,
              color: Color(0xFF1AB69C),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  orderId,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$items item${items != 1 ? 's' : ''}  •  ${fmtAmount(totalAmount)}',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _statusColor(status).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              status,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: _statusColor(status),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentTile extends StatelessWidget {
  final Map<String, dynamic> payment;
  const _PaymentTile({required this.payment});

  @override
  Widget build(BuildContext context) {
    final id = payment['_id']?.toString() ?? '—';
    final amount = payment['amount']?.toString() ?? '0';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FFF4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFC8E6C9)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFF2E7D32).withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.currency_rupee_outlined,
              size: 17,
              color: Color(0xFF2E7D32),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              id,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.black54,
              ),
            ),
          ),
          Text(
            '₹$amount',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF2E7D32),
            ),
          ),
        ],
      ),
    );
  }
}

class _TicketTile extends StatelessWidget {
  final Map<String, dynamic> ticket;
  const _TicketTile({required this.ticket});

  @override
  Widget build(BuildContext context) {
    final id = ticket['_id']?.toString() ?? '—';
    final subject = ticket['subject']?.toString() ?? 'Support Ticket';
    final status = ticket['status']?.toString() ?? '—';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8F0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFCC80)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFFE65100).withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.support_agent_outlined,
              size: 17,
              color: Color(0xFFE65100),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  subject,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
                Text(
                  id,
                  style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                ),
              ],
            ),
          ),
          if (status != '—')
            Text(
              status,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFFE65100),
              ),
            ),
        ],
      ),
    );
  }
}
