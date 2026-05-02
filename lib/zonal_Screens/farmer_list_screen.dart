import 'package:flutter/material.dart';
import 'package:FieldService_app/zonal_Screens/zonal_add_farmer_screen.dart';
import 'package:FieldService_app/zonal_services/zonal_farmers_service.dart';
import 'package:url_launcher/url_launcher.dart';

class FarmerListScreen extends StatefulWidget {
  const FarmerListScreen({super.key});

  @override
  State<FarmerListScreen> createState() => _FarmerListScreenState();
}

class _FarmerListScreenState extends State<FarmerListScreen> {
  // ─── Theme ────────────────────────────────────────────────────────────────
  static const _gradientStart = Color(0xFF52D494);
  static const _gradientEnd = Color(0xFF1AB69C);
  static const _accentGreen = Color(0xFF1AB69C);
  static const _background = Color(0xFFF2F6F3);

  // ─── State ────────────────────────────────────────────────────────────────
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  late final ZonalFarmersService _service;

  List<_FarmerData> _farmers = [];
  bool _isLoading = true;

  // Track which farmer IDs are being approved
  final Set<String> _approvingIds = {};

  // ─── Lifecycle ────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _service = ZonalFarmersService();
    _fetchFarmers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ─── Data ─────────────────────────────────────────────────────────────────

  Future<void> _fetchFarmers() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    final res = await _service.fetchFarmers();

    if (!mounted) return;

    if (res.error == 'UNAUTHORIZED') {
      Navigator.pop(context);
      return;
    }

    if (!res.success) {
      _showSnackBar(res.error ?? 'Error loading farmers');
      setState(() => _isLoading = false);
      return;
    }

    setState(() {
      _farmers = res.data!
          .map<_FarmerData>((e) => _FarmerData.fromApi(e))
          .toList();
      _isLoading = false;
    });
  }

  List<_FarmerData> get _filtered {
    List<_FarmerData> list = List.from(_farmers);

    // 🔍 SEARCH
    if (_searchQuery.isNotEmpty) {
      list = list.where((f) {
        return f.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            f.address.toLowerCase().contains(_searchQuery.toLowerCase());
      }).toList();
    }

    // ✅ SORTING (CORE LOGIC)
    list.sort((a, b) {
      final statusA = a.status.toLowerCase();
      final statusB = b.status.toLowerCase();

      // 🔥 Pending first
      if (statusA == 'pending' && statusB != 'pending') return -1;
      if (statusA != 'pending' && statusB == 'pending') return 1;

      // 🔥 Latest first (using ID timestamp fallback)
      int extractTime(String id) {
        if (id.length < 8) return 0;
        return int.tryParse(id.substring(0, 8), radix: 16) ?? 0;
      }

      final timeA = extractTime(a.id);
      final timeB = extractTime(b.id);

      return timeB.compareTo(timeA);
    });

    return list;
  }

  // ─── Approve Flow ─────────────────────────────────────────────────────────

  Future<void> _onApproveFarmer(_FarmerData farmer) async {
    final confirmed = await _showApproveConfirmDialog(farmer.name);
    if (!confirmed || !mounted) return;

    // Validate that farmer has a valid ID
    if (farmer.id.isEmpty) {
      _showSnackBar(
        'Error: Farmer ID is missing from server response. Please contact support.',
      );
      return;
    }

    setState(() => _approvingIds.add(farmer.id));

    final result = await _service.approveFarmer(farmer.id);

    if (!mounted) return;

    setState(() => _approvingIds.remove(farmer.id));

    if (result.error == 'UNAUTHORIZED') {
      Navigator.pop(context);
      return;
    }

    if (!result.success) {
      if (result.error == 'FARMER_ID_MISSING') {
        _showSnackBar(
          'Error: Farmer ID is missing from server response. Please contact support.',
        );
      } else {
        _showSnackBar(result.error ?? 'Failed to approve farmer');
      }
      return;
    }

    _showSnackBar('${farmer.name} approved successfully!');

    // Optimistically update local list
    setState(() {
      final idx = _farmers.indexWhere((f) => f.id == farmer.id);
      if (idx != -1) {
        final updated = _farmers[idx];
        _farmers[idx] = _FarmerData(
          id: updated.id,
          name: updated.name,
          address: updated.address,
          latitude: updated.latitude,
          longitude: updated.longitude,
          employee: updated.employee,
          status: 'Active',
          land: updated.land,
          lastOrderDays: updated.lastOrderDays,
          phone: updated.phone,
        );
      }
    });
  }

  Future<bool> _showApproveConfirmDialog(String farmerName) async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => _ApproveConfirmDialog(
            title: 'Approve Farmer',
            subtitle: 'Are you sure you want to approve',
            name: farmerName,
            confirmLabel: 'Approve',
            confirmColor: _accentGreen,
            icon: Icons.verified_outlined,
          ),
        ) ??
        false;
  }

  // ─── Details Bottom Sheet ─────────────────────────────────────────────────

  void _showFarmerDetails(_FarmerData farmer) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FarmerDetailsSheet(farmer: farmer),
    );
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: _accentGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _openAddFarmer() async {
    final refreshed = await ZonalAddFarmerScreen.show(context);
    if (refreshed == true) {
      await _fetchFarmers();
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: _buildAppBar(),
      body: RefreshIndicator(
        color: _accentGreen,
        onRefresh: _fetchFarmers,
        child: Column(
          children: [
            _buildSearchBar(),
            Expanded(child: _buildFarmerList()),
          ],
        ),
      ),
    );
  }

  // ─── App Bar ──────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(60),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [_gradientStart, _gradientEnd],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
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
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(
              Icons.arrow_back_sharp,
              color: Colors.white,
              size: 20,
            ),
          ),
          title: const Text(
            'Farmers List',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: _accentGreen,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                icon: const Icon(Icons.add, size: 16),
                label: const Text(
                  'Add',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
                onPressed: _openAddFarmer,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Search Bar ───────────────────────────────────────────────────────────

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 46,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: TextField(
                controller: _searchController,
                onChanged: (val) => setState(() => _searchQuery = val),
                style: const TextStyle(fontSize: 14, color: Colors.black87),
                decoration: InputDecoration(
                  hintText: 'Search by name or village...',
                  hintStyle: TextStyle(fontSize: 13, color: Colors.grey[400]),
                  prefixIcon: const Icon(
                    Icons.search,
                    size: 20,
                    color: _accentGreen,
                  ),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(
                            Icons.close,
                            size: 18,
                            color: Colors.grey,
                          ),
                          onPressed: () => setState(() {
                            _searchController.clear();
                            _searchQuery = '';
                          }),
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 13,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // GestureDetector(
          //   onTap: _showFilterSheet,
          //   child: Container(
          //     width: 46,
          //     height: 46,
          //     decoration: BoxDecoration(
          //       color: Colors.white,
          //       borderRadius: BorderRadius.circular(14),
          //       boxShadow: [
          //         BoxShadow(
          //           color: Colors.black.withValues(alpha: 0.05),
          //           blurRadius: 10,
          //           offset: const Offset(0, 4),
          //         ),
          //       ],
          //     ),
          //     child: const Icon(
          //       Icons.filter_list,
          //       color: _accentGreen,
          //       size: 22,
          //     ),
          //   ),
          // ),
        ],
      ),
    );
  }

  // ─── Farmer List ──────────────────────────────────────────────────────────

  Widget _buildFarmerList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final list = _filtered;

    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.agriculture_outlined, size: 52, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text(
              'No farmers found',
              style: TextStyle(color: Colors.grey[500], fontSize: 15),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: list.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, index) {
        final farmer = list[index];
        final isPending = farmer.status.toLowerCase() == 'pending';
        final isApproving = _approvingIds.contains(farmer.id);

        return _FarmerCard(
          farmer: farmer,
          isPending: isPending,
          isApproving: isApproving,
          onDetails: () => _showFarmerDetails(farmer),
          onApprove: () => _onApproveFarmer(farmer),
        );
      },
    );
  }
}

// ─── Data Model ───────────────────────────────────────────────────────────────

class _FarmerData {
  final String id;
  final String name;
  final String address;
  final double? latitude;
  final double? longitude;
  final String employee;
  final String status;
  final String land;
  final int? lastOrderDays;
  final String phone;

  const _FarmerData({
    required this.id,
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.employee,
    required this.status,
    required this.land,
    required this.lastOrderDays,
    required this.phone,
  });

  factory _FarmerData.fromApi(Map<String, dynamic> json) {
    final loc = json['location'];
    final extractedId = (json['farmerId'] ?? json['_id'] ?? json['id'] ?? '')
        .toString();

    return _FarmerData(
      id: extractedId,
      name: json['name'] ?? '',
      address: json['address'] ?? '',
      latitude: loc != null ? (loc['latitude'] as num?)?.toDouble() : null,
      longitude: loc != null ? (loc['longitude'] as num?)?.toDouble() : null,
      employee: json['employee'] ?? '',
      status: json['status'] ?? '',
      land: json['land'] ?? '0',
      lastOrderDays: json['lastOrderDays'] as int?,
      phone: json['phone'] ?? '',
    );
  }

  Color get statusColor {
    switch (status.toLowerCase()) {
      case 'active':
      case 'approved':
        return const Color(0xFF1AB69C);
      case 'pending':
        return const Color(0xFFF59E0B);
      default:
        return Colors.grey;
    }
  }

  String get lastOrderText {
    if (lastOrderDays == null) return 'No Orders';
    return '$lastOrderDays days ago';
  }
}

// ─── Farmer Card ──────────────────────────────────────────────────────────────

class _FarmerCard extends StatelessWidget {
  final _FarmerData farmer;
  final bool isPending;
  final bool isApproving;
  final VoidCallback onDetails;
  final VoidCallback onApprove;

  static const _accentGreen = Color(0xFF1AB69C);
  static const _pendingAmber = Color(0xFFF59E0B);

  const _FarmerCard({
    required this.farmer,
    required this.isPending,
    required this.isApproving,
    required this.onDetails,
    required this.onApprove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        // Pending cards get a subtle amber left border accent
        border: isPending
            ? const Border(left: BorderSide(color: _pendingAmber, width: 4))
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── HEADER ──
          Row(
            children: [
              CircleAvatar(
                backgroundColor: _accentGreen.withValues(alpha: 0.15),
                child: Text(
                  farmer.name.isNotEmpty ? farmer.name[0].toUpperCase() : '?',
                  style: const TextStyle(
                    color: _accentGreen,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      farmer.name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      farmer.address.isNotEmpty
                          ? farmer.address
                          : 'No address provided',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),

              // Status badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: farmer.statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  farmer.status,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: farmer.statusColor,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 10),

          // ── DETAILS ──
          Row(
            children: [
              Expanded(
                child: _StatItem(label: 'LAND', value: farmer.land),
              ),
              Expanded(
                child: _StatItem(label: 'HANDLED BY', value: farmer.employee),
              ),
            ],
          ),

          const SizedBox(height: 8),

          Text(
            'Last Order: ${farmer.lastOrderText}',
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),

          const SizedBox(height: 14),

          // ── ACTIONS ──
          if (isPending)
            _PendingActions(
              isApproving: isApproving,
              entityLabel: 'Farmer',
              onDetails: onDetails,
              onApprove: onApprove,
            ),
        ],
      ),
    );
  }
}

// ─── Pending Actions ──────────────────────────────────────────────────────────

class _PendingActions extends StatelessWidget {
  final bool isApproving;
  final String entityLabel;
  final VoidCallback onDetails;
  final VoidCallback onApprove;

  static const _pendingAmber = Color(0xFFF59E0B);
  static const _accentGreen = Color(0xFF1AB69C);

  const _PendingActions({
    required this.isApproving,
    required this.entityLabel,
    required this.onDetails,
    required this.onApprove,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: isApproving ? null : onDetails,
            icon: const Icon(Icons.info_outline, size: 17),
            label: const Text('View Details'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _pendingAmber,
              side: const BorderSide(color: _pendingAmber),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),

        const SizedBox(width: 10),

        Expanded(
          child: ElevatedButton.icon(
            onPressed: isApproving ? null : onApprove,
            icon: isApproving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(
                    Icons.check_circle_outline,
                    size: 17,
                    color: Colors.white,
                  ),
            label: Text(
              isApproving ? 'Approving...' : 'Approve $entityLabel',
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _accentGreen,
              disabledBackgroundColor: _accentGreen.withValues(alpha: 0.6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Approve Confirm Dialog ───────────────────────────────────────────────────

class _ApproveConfirmDialog extends StatelessWidget {
  final String title;
  final String subtitle;
  final String name;
  final String confirmLabel;
  final Color confirmColor;
  final IconData icon;

  const _ApproveConfirmDialog({
    required this.title,
    required this.subtitle,
    required this.name,
    required this.confirmLabel,
    required this.confirmColor,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: confirmColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: confirmColor, size: 32),
            ),

            const SizedBox(height: 18),

            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),

            const SizedBox(height: 10),

            RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                  height: 1.5,
                ),
                children: [
                  TextSpan(text: '$subtitle\n'),
                  TextSpan(
                    text: name,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Colors.grey[800],
                    ),
                  ),
                  const TextSpan(text: '?'),
                ],
              ),
            ),

            const SizedBox(height: 24),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey[600],
                      side: BorderSide(color: Colors.grey[300]!),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: confirmColor,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(
                      confirmLabel,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Farmer Details Bottom Sheet ──────────────────────────────────────────────

class _FarmerDetailsSheet extends StatelessWidget {
  final _FarmerData farmer;

  static const _accentGreen = Color(0xFF1AB69C);
  static const _gradientStart = Color(0xFF52D494);
  static const _gradientEnd = Color(0xFF1AB69C);

  const _FarmerDetailsSheet({required this.farmer});

  Future<void> _makeCall() async {
    if (farmer.phone.isEmpty) return;
    final Uri uri = Uri(scheme: 'tel', path: farmer.phone);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _openMap() async {
    if (farmer.latitude == null || farmer.longitude == null) return;
    final Uri uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${farmer.latitude},${farmer.longitude}',
    );
    await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              // ── Header ──
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_gradientStart, _gradientEnd],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    Row(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.4),
                              width: 1.5,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              farmer.name.isNotEmpty
                                  ? farmer.name[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(width: 14),

                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                farmer.name,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  farmer.status,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // ── Scrollable body ──
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                  children: [
                    // Stats row
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFA),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _SheetStatItem(
                              icon: Icons.landscape_outlined,
                              label: 'Land',
                              value: farmer.land,
                              valueColor: Colors.black87,
                            ),
                          ),
                          Container(
                            width: 1,
                            height: 40,
                            color: const Color(0xFFE8E8E8),
                            margin: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                          Expanded(
                            child: _SheetStatItem(
                              icon: Icons.shopping_bag_outlined,
                              label: 'Last Order',
                              value: farmer.lastOrderText,
                              valueColor: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    const _SectionLabel(label: 'Contact Info'),
                    const SizedBox(height: 12),

                    _DetailRow(
                      icon: Icons.phone_outlined,
                      label: 'Phone',
                      value: farmer.phone.isNotEmpty
                          ? farmer.phone
                          : 'Not provided',
                    ),
                    _DetailRow(
                      icon: Icons.location_on_outlined,
                      label: 'Address',
                      value: farmer.address.isNotEmpty
                          ? farmer.address
                          : 'Not provided',
                    ),

                    const SizedBox(height: 20),

                    const _SectionLabel(label: 'Farm Info'),
                    const SizedBox(height: 12),

                    _DetailRow(
                      icon: Icons.badge_outlined,
                      label: 'Handled By',
                      value: farmer.employee.isNotEmpty
                          ? farmer.employee
                          : 'Not assigned',
                    ),

                    const SizedBox(height: 28),

                    // Action buttons
                    if (farmer.phone.isNotEmpty)
                      ElevatedButton.icon(
                        onPressed: _makeCall,
                        icon: const Icon(Icons.phone, color: Colors.white),
                        label: Text(
                          'Call ${farmer.phone}',
                          style: const TextStyle(color: Colors.white),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _accentGreen,
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),

                    if (farmer.latitude != null &&
                        farmer.longitude != null) ...[
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: _openMap,
                        icon: const Icon(
                          Icons.map_outlined,
                          color: _accentGreen,
                        ),
                        label: const Text(
                          'View on Map',
                          style: TextStyle(color: _accentGreen),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: _accentGreen),
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Sheet helpers ────────────────────────────────────────────────────────────

class _SheetStatItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color valueColor;

  const _SheetStatItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 20, color: Colors.grey[400]),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: Colors.grey[500],
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: Colors.grey[500],
        letterSpacing: 0.8,
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  static const _accentGreen = Color(0xFF1AB69C);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _accentGreen.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: _accentGreen),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[500],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Stat Item ────────────────────────────────────────────────────────────────

class _StatItem extends StatelessWidget {
  final String label;
  final String value;

  const _StatItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: Colors.grey[500],
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }
}
