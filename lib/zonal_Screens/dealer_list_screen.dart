import 'package:flutter/material.dart';
import 'package:FieldService_app/zonal_Screens/zonal_add_dealer_screen.dart';
import 'package:FieldService_app/zonal_services/zonal_dealers_service.dart';
import 'package:url_launcher/url_launcher.dart';

class DealerListScreen extends StatefulWidget {
  const DealerListScreen({super.key});

  @override
  State<DealerListScreen> createState() => _DealerListScreenState();
}

class _DealerListScreenState extends State<DealerListScreen> {
  // ─── Theme ────────────────────────────────────────────────────────────────
  static const _gradientStart = Color(0xFF52D494);
  static const _gradientEnd = Color(0xFF1AB69C);
  static const _accentGreen = Color(0xFF1AB69C);
  static const _background = Color(0xFFF2F6F3);

  // ─── State ────────────────────────────────────────────────────────────────
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  late final ZonalDealersService _dealersService;

  List<dynamic> dealers = [];
  bool _isLoading = true;

  // Track which dealer IDs are currently being approved (to show loader)
  final Set<String> _approvingIds = {};

  // ─── Lifecycle ────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _dealersService = ZonalDealersService();
    _loadDealers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ─── Data ─────────────────────────────────────────────────────────────────

  Future<void> _loadDealers() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    final result = await _dealersService.fetchDealers();

    if (!mounted) return;

    if (result.error == 'UNAUTHORIZED') {
      Navigator.pop(context);
      return;
    }

    if (!result.success) {
      _showSnackBar(result.error ?? 'Error loading dealers');
      setState(() => _isLoading = false);
      return;
    }

    setState(() {
      dealers = result.data ?? [];
      _isLoading = false;
    });
  }

  List<dynamic> get _filtered {
    List<dynamic> list = List.from(dealers);

    // 🔍 SEARCH
    if (_searchQuery.isNotEmpty) {
      list = list.where((d) {
        final name = (d['name'] ?? '').toString().toLowerCase();
        final shop = (d['shopName'] ?? '').toString().toLowerCase();
        final address = (d['address'] ?? '').toString().toLowerCase();
        final q = _searchQuery.toLowerCase();
        return name.contains(q) || shop.contains(q) || address.contains(q);
      }).toList();
    }

    // ✅ SORTING (CORE REQUIREMENT)
    list.sort((a, b) {
      final statusA = (a['status'] ?? '').toString().toLowerCase();
      final statusB = (b['status'] ?? '').toString().toLowerCase();

      // 🔥 Pending first
      if (statusA == 'pending' && statusB != 'pending') return -1;
      if (statusA != 'pending' && statusB == 'pending') return 1;

      // 🔥 Optional: latest first (if backend gives date)
      final dateA = DateTime.tryParse(a['createdAt'] ?? '') ?? DateTime(1970);
      final dateB = DateTime.tryParse(b['createdAt'] ?? '') ?? DateTime(1970);

      return dateB.compareTo(dateA);
    });

    return list;
  }

  // ─── Approve Flow ─────────────────────────────────────────────────────────

  Future<void> _onApproveDealer(_DealerData dealer) async {
    final confirmed = await _showApproveConfirmDialog(dealer.name);
    if (!confirmed || !mounted) return;

    // Validate that dealer has a valid ID
    if (dealer.id.isEmpty) {
      _showSnackBar(
        'Error: Dealer ID is missing from server response. Please contact support.',
      );
      return;
    }

    setState(() => _approvingIds.add(dealer.id));

    final result = await _dealersService.approveDealer(dealer.id);

    if (!mounted) return;

    setState(() => _approvingIds.remove(dealer.id));

    if (result.error == 'UNAUTHORIZED') {
      Navigator.pop(context);
      return;
    }

    if (!result.success) {
      if (result.error == 'DEALER_ID_MISSING') {
        _showSnackBar(
          'Error: Dealer ID is missing from server response. Please contact support.',
        );
      } else {
        _showSnackBar(result.error ?? 'Failed to approve dealer');
      }
      return;
    }

    _showSnackBar('${dealer.name} approved successfully!');

    // Optimistically update the local list so UI refreshes instantly
    setState(() {
      final idx = dealers.indexWhere((d) => (d['_id'] ?? d['id']) == dealer.id);
      if (idx != -1) {
        dealers[idx] = Map<String, dynamic>.from(dealers[idx])
          ..['status'] = 'Approved';
      }
    });
  }

  Future<bool> _showApproveConfirmDialog(String dealerName) async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => _ApproveConfirmDialog(
            title: 'Approve Dealer',
            subtitle: 'Are you sure you want to approve',
            name: dealerName,
            confirmLabel: 'Approve',
            confirmColor: _accentGreen,
            icon: Icons.verified_outlined,
          ),
        ) ??
        false;
  }

  // ─── Details Bottom Sheet ─────────────────────────────────────────────────

  void _showDealerDetails(_DealerData dealer) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DealerDetailsSheet(dealer: dealer),
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

  Future<void> _openAddDealer() async {
    final refreshed = await ZonalAddDealerScreen.show(context);
    if (refreshed == true) {
      await _loadDealers();
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
        onRefresh: _loadDealers,
        child: Column(
          children: [
            _buildSearchBar(),
            Expanded(child: _buildDealerList()),
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
            'Dealers List',
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
                onPressed: _openAddDealer,
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
            hintText: 'Search by name or location...',
            hintStyle: TextStyle(fontSize: 13, color: Colors.grey[400]),
            prefixIcon: const Icon(Icons.search, size: 20, color: _accentGreen),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.close, size: 18, color: Colors.grey),
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
    );
  }

  // ─── Dealer List ──────────────────────────────────────────────────────────

  Widget _buildDealerList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final list = _filtered;

    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.store_mall_directory_outlined,
              size: 52,
              color: Colors.grey[300],
            ),
            const SizedBox(height: 12),
            Text(
              'No dealers found',
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
      itemBuilder: (context, index) {
        final dealer = _DealerData.fromApi(list[index]);
        final isPending = dealer.status.toLowerCase() == 'pending';
        final isApproving = _approvingIds.contains(dealer.id);

        return _DealerCard(
          dealer: dealer,
          isPending: isPending,
          isApproving: isApproving,
          onCall: () {},
          onDetails: () => _showDealerDetails(dealer),
          onApprove: () => _onApproveDealer(dealer),
        );
      },
    );
  }
}

// ─── Data Model ───────────────────────────────────────────────────────────────

class _DealerData {
  final String id;
  final String name;
  final String address;
  final double? latitude;
  final double? longitude;
  final String outstanding;
  final String lastOrder;
  final String status;
  final Color statusColor;
  final String regionBadge;
  final String phone;
  final String email;
  final String gstNumber;
  final String shopName;

  const _DealerData({
    required this.id,
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.outstanding,
    required this.lastOrder,
    required this.status,
    required this.statusColor,
    required this.regionBadge,
    required this.phone,
    required this.email,
    required this.gstNumber,
    required this.shopName,
  });

  factory _DealerData.fromApi(Map<String, dynamic> json) {
    final status = json['status'] ?? 'Unknown';

    Color statusColor;
    switch (status.toString().toLowerCase()) {
      case 'active':
      case 'approved':
        statusColor = const Color(0xFF1AB69C);
        break;
      case 'inactive':
        statusColor = Colors.grey;
        break;
      case 'pending':
        statusColor = const Color(0xFFF59E0B);
        break;
      default:
        statusColor = const Color(0xFFF59E0B);
    }

    final outstanding = json['outstanding'] ?? 0;

    String lastOrder;
    if (json['lastOrderDays'] == null) {
      lastOrder = 'No orders';
    } else {
      lastOrder = '${json['lastOrderDays']} days ago';
    }

    final loc = json['location'];

    return _DealerData(
      id: (json['dealerId'] ?? json['_id'] ?? json['id'] ?? '').toString(),
      name: json['shopName'] ?? json['name'] ?? '',
      shopName: json['shopName'] ?? '',
      address: json['address'] ?? '',
      latitude: loc != null ? (loc['latitude'] as num?)?.toDouble() : null,
      longitude: loc != null ? (loc['longitude'] as num?)?.toDouble() : null,
      outstanding: '₹$outstanding',
      lastOrder: lastOrder,
      status: status.toString(),
      statusColor: statusColor,
      regionBadge: json['employee'] ?? 'Self',
      phone: json['phone'] ?? '',
      email: json['email'] ?? '',
      gstNumber: json['gstNumber'] ?? json['gst'] ?? '',
    );
  }
}

// ─── Dealer Card ──────────────────────────────────────────────────────────────

class _DealerCard extends StatelessWidget {
  final _DealerData dealer;
  final bool isPending;
  final bool isApproving;
  final VoidCallback onDetails;
  final VoidCallback onCall;
  final VoidCallback onApprove;

  static const _accentGreen = Color(0xFF1AB69C);
  static const _pendingAmber = Color(0xFFF59E0B);

  const _DealerCard({
    required this.dealer,
    required this.isPending,
    required this.isApproving,
    required this.onDetails,
    required this.onCall,
    required this.onApprove,
  });

  Future<void> _makeCall() async {
    if (dealer.phone.isEmpty) return;
    final Uri uri = Uri(scheme: 'tel', path: dealer.phone);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _openDirections(BuildContext context) async {
    if (dealer.latitude == null || dealer.longitude == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Location not available')));
      return;
    }
    final Uri uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=${dealer.latitude},${dealer.longitude}',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isOverdue =
        dealer.outstanding != '₹0' && dealer.status == 'Overdue';

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
          // ───── TOP ROW ─────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _accentGreen.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    dealer.name.isNotEmpty ? dealer.name[0].toUpperCase() : '?',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _accentGreen,
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 10),

              // Name + Location
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dealer.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.location_on_outlined,
                          size: 14,
                          color: Colors.black38,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            dealer.address.isNotEmpty
                                ? dealer.address
                                : 'No address provided',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black45,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),

                    // Region badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: _accentGreen.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        dealer.regionBadge,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: _accentGreen,
                        ),
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
                  color: dealer.statusColor.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  dealer.status,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: dealer.statusColor,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),
          const Divider(),
          const SizedBox(height: 12),

          // ───── STATS ─────
          Row(
            children: [
              Expanded(
                child: _StatItem(
                  label: 'OUTSTANDING',
                  value: dealer.outstanding,
                  valueColor: dealer.outstanding == '₹0'
                      ? _accentGreen
                      : isOverdue
                      ? const Color(0xFFEF4444)
                      : const Color(0xFFF59E0B),
                ),
              ),
              Container(
                width: 1,
                height: 32,
                color: const Color(0xFFF0F0F0),
                margin: const EdgeInsets.symmetric(horizontal: 12),
              ),
              Expanded(
                child: _StatItem(
                  label: 'LAST ORDER',
                  value: dealer.lastOrder,
                  valueColor: Colors.black54,
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // ───── ACTIONS ─────
          if (isPending) ...[
            _PendingActions(
              isApproving: isApproving,
              onDetails: onDetails,
              onApprove: onApprove,
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _makeCall,
                    icon: const Icon(Icons.phone_outlined, size: 17),
                    label: const Text('Call'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _accentGreen,
                      side: const BorderSide(color: _accentGreen),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _openDirections(context),
                    icon: const Icon(
                      Icons.directions,
                      size: 17,
                      color: Colors.white,
                    ),
                    label: const Text(
                      'Directions',
                      style: TextStyle(color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accentGreen,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Pending Actions ──────────────────────────────────────────────────────────

class _PendingActions extends StatelessWidget {
  final bool isApproving;
  final VoidCallback onDetails;
  final VoidCallback onApprove;

  static const _pendingAmber = Color(0xFFF59E0B);
  static const _accentGreen = Color(0xFF1AB69C);

  const _PendingActions({
    required this.isApproving,
    required this.onDetails,
    required this.onApprove,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // View Details
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

        // Approve
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
              isApproving ? 'Approving...' : 'Approve Dealer',
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
            // Icon circle
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
                // Cancel
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

                // Confirm
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

// ─── Dealer Details Bottom Sheet ──────────────────────────────────────────────

class _DealerDetailsSheet extends StatelessWidget {
  final _DealerData dealer;

  static const _accentGreen = Color(0xFF1AB69C);
  static const _gradientStart = Color(0xFF52D494);
  static const _gradientEnd = Color(0xFF1AB69C);

  const _DealerDetailsSheet({required this.dealer});

  Future<void> _makeCall() async {
    if (dealer.phone.isEmpty) return;
    final Uri uri = Uri(scheme: 'tel', path: dealer.phone);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
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
                    // Drag handle
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
                        // Large avatar
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
                              dealer.name.isNotEmpty
                                  ? dealer.name[0].toUpperCase()
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
                                dealer.name,
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
                                  dealer.status,
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
                              icon: Icons.account_balance_wallet_outlined,
                              label: 'Outstanding',
                              value: dealer.outstanding,
                              valueColor: dealer.outstanding == '₹0'
                                  ? _accentGreen
                                  : const Color(0xFFF59E0B),
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
                              value: dealer.lastOrder,
                              valueColor: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Details section
                    const _SectionLabel(label: 'Contact Info'),
                    const SizedBox(height: 12),

                    _DetailRow(
                      icon: Icons.phone_outlined,
                      label: 'Phone',
                      value: dealer.phone.isNotEmpty
                          ? dealer.phone
                          : 'Not provided',
                    ),
                    _DetailRow(
                      icon: Icons.email_outlined,
                      label: 'Email',
                      value: dealer.email.isNotEmpty
                          ? dealer.email
                          : 'Not provided',
                    ),
                    _DetailRow(
                      icon: Icons.location_on_outlined,
                      label: 'Address',
                      value: dealer.address.isNotEmpty
                          ? dealer.address
                          : 'Not provided',
                    ),

                    const SizedBox(height: 20),

                    const _SectionLabel(label: 'Business Info'),
                    const SizedBox(height: 12),

                    _DetailRow(
                      icon: Icons.store_outlined,
                      label: 'Shop Name',
                      value: dealer.shopName.isNotEmpty
                          ? dealer.shopName
                          : dealer.name,
                    ),
                    _DetailRow(
                      icon: Icons.receipt_long_outlined,
                      label: 'GST Number',
                      value: dealer.gstNumber.isNotEmpty
                          ? dealer.gstNumber
                          : 'Not provided',
                    ),
                    _DetailRow(
                      icon: Icons.badge_outlined,
                      label: 'Assigned To',
                      value: dealer.regionBadge,
                    ),

                    const SizedBox(height: 28),

                    // Call button (only if phone exists and not pending)
                    if (dealer.phone.isNotEmpty &&
                        dealer.status.toLowerCase() != 'pending')
                      ElevatedButton.icon(
                        onPressed: _makeCall,
                        icon: const Icon(Icons.phone, color: Colors.white),
                        label: Text(
                          'Call ${dealer.phone}',
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
  final Color valueColor;

  const _StatItem({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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
        const SizedBox(height: 5),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}
