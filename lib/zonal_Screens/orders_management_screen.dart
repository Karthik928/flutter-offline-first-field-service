import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:FieldService_app/zonal_services/zonal_employee_service.dart';
import 'package:FieldService_app/zonal_services/zonal_orders_service.dart';
import 'package:FieldService_app/zonal_Screens/order_detail_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────
enum OrderStatus {
  pending,
  confirmed,
  shipped,
  partiallyDelivered,
  delivered,
  cancelled,
}

extension OrderStatusX on OrderStatus {
  String get label {
    switch (this) {
      case OrderStatus.pending:
        return 'Pending';
      case OrderStatus.confirmed:
        return 'Confirmed';
      case OrderStatus.shipped:
        return 'Shipped';
      case OrderStatus.partiallyDelivered:
        return 'Partially Delivered';
      case OrderStatus.delivered:
        return 'Delivered';
      case OrderStatus.cancelled:
        return 'Cancelled';
    }
  }

  String get value => label.toLowerCase();
}

class OrdersManagementScreen extends StatefulWidget {
  const OrdersManagementScreen({super.key});

  @override
  State<OrdersManagementScreen> createState() => _OrdersManagementScreenState();
}

class _OrdersManagementScreenState extends State<OrdersManagementScreen> {
  // ── Design tokens ────────────────────────────────────────────────────────
  static const _gradientStart = Color(0xFF52D494);
  static const _gradientEnd = Color(0xFF1AB69C);
  static const _accentGreen = Color(0xFF1AB69C);
  static const _background = Color(0xFFF2F6F3);

  // ── Service & controllers ────────────────────────────────────────────────
  final ZonalOrdersService _service = ZonalOrdersService();
  final TextEditingController _searchController = TextEditingController();

  // ── UI state ─────────────────────────────────────────────────────────────
  String _searchQuery = '';
  String _selectedStatus = 'All';
  bool _isLoading = true;

  // ── Data ─────────────────────────────────────────────────────────────────
  List<OrderData> _orders = [];

  List<String> get _statusFilters => [
    'All',
    ...OrderStatus.values.map((e) => e.label),
  ];

  // ── Employee filter state ─────────────────────────────────────────────────
  List<Employee> _employees = [];
  bool _loadingEmployees = true;
  String? _selectedEmployeeId;
  String? _selfUserId;

  // ── Action loading guards (orderId → true while API in-flight) ───────────
  final Map<String, bool> _actionLoading = {};

  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    _selfUserId = prefs.getString('userId') ?? '';
    await _fetchEmployees();
    await _loadOrders();
  }

  Future<void> _fetchEmployees() async {
    if (mounted) setState(() => _loadingEmployees = true);
    try {
      final list = await ZonalEmployeeService().fetchEmployees();
      if (mounted) {
        setState(() {
          _employees = list;
          _loadingEmployees = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingEmployees = false);
    }
  }

  String? get _resolvedEmployeeId {
    if (_selectedEmployeeId == null) return null;
    if (_selectedEmployeeId == '__self__') return _selfUserId;
    return _selectedEmployeeId;
  }

  Future<void> _loadOrders() async {
    if (mounted) setState(() => _isLoading = true);
    final result = await _service.fetchOrders(employeeId: _resolvedEmployeeId);
    if (!mounted) return;

    if (result.error == 'UNAUTHORIZED') {
      Navigator.of(context).maybePop();
      return;
    }

    if (!result.success) {
      _showSnackBar(result.error ?? 'Failed to load orders', isError: true);
      setState(() => _isLoading = false);
      return;
    }

    setState(() {
      _orders = result.orders;
      _isLoading = false;
    });
  }

  // ── Approve flow ──────────────────────────────────────────────────────────
  Future<void> _onApprove(OrderData order) async {
    final confirmed = await _showApproveDialog(order);
    if (!confirmed || !mounted) return;

    setState(() => _actionLoading[order.orderId] = true);

    final result = await _service.approveOrder(order.orderId);

    if (!mounted) return;
    setState(() => _actionLoading.remove(order.orderId));

    if (result.error == 'UNAUTHORIZED') {
      Navigator.of(context).maybePop();
      return;
    }

    if (result.success) {
      _showSnackBar(result.message ?? 'Order approved successfully.');
      await _loadOrders();
    } else {
      _showSnackBar(result.error ?? 'Failed to approve order.', isError: true);
    }
  }

  // ── Reject flow ───────────────────────────────────────────────────────────
  Future<void> _onReject(OrderData order) async {
    final reason = await _showRejectDialog(order);
    if (reason == null || !mounted) return;

    setState(() => _actionLoading[order.orderId] = true);

    final result = await _service.rejectOrder(order.orderId, reason: reason);

    if (!mounted) return;
    setState(() => _actionLoading.remove(order.orderId));

    if (result.error == 'UNAUTHORIZED') {
      Navigator.of(context).maybePop();
      return;
    }

    if (result.success) {
      _showSnackBar(result.message ?? 'Order rejected successfully.');
      await _loadOrders();
    } else {
      _showSnackBar(result.error ?? 'Failed to reject order.', isError: true);
    }
  }

  // ── Approve confirmation dialog ───────────────────────────────────────────
  Future<bool> _showApproveDialog(OrderData order) async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => _ApproveDialog(order: order),
        ) ??
        false;
  }

  // ── Reject dialog with reason field ──────────────────────────────────────
  /// Returns the reason string on confirm, null on cancel.
  Future<String?> _showRejectDialog(OrderData order) async {
    return await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _RejectDialog(order: order),
    );
  }

  // ── SnackBar helper ───────────────────────────────────────────────────────
  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError
                  ? Icons.error_outline_rounded
                  : Icons.check_circle_outline_rounded,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: isError ? const Color(0xFFEF4444) : _accentGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ── Filtered orders ───────────────────────────────────────────────────────
  List<OrderData> get _filteredOrders {
    List<OrderData> list = List.from(_orders);

    // ✅ FILTER (only if not ALL)
    if (_selectedStatus != 'All') {
      list = list
          .where((o) => o.status.toLowerCase() == _selectedStatus.toLowerCase())
          .toList();
    }

    // ✅ SORT based on ENUM ORDER (THIS IS YOUR REQUIREMENT)
    list.sort((a, b) {
      int indexA = OrderStatus.values.indexWhere(
        (e) => e.value == a.status.toLowerCase(),
      );
      int indexB = OrderStatus.values.indexWhere(
        (e) => e.value == b.status.toLowerCase(),
      );

      return indexA.compareTo(indexB);
    });

    // ✅ SEARCH
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((o) {
        return o.orderId.toLowerCase().contains(q) ||
            o.customer.toLowerCase().contains(q) ||
            o.employee.toLowerCase().contains(q) ||
            o.type.toLowerCase().contains(q);
      }).toList();
    }

    return list;
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'delivered':
        return _accentGreen;
      case 'partially delivered':
        return const Color(0xFFF59E0B);
      case 'pending':
        return const Color(0xFF4D8AF0);
      case 'cancelled':
        return const Color(0xFFEF4444);
      default:
        return Colors.grey;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          _buildSearchBar(),
          _buildEmployeeFilter(),
          _buildStatusChips(),
          Expanded(child: _buildOrderList()),
        ],
      ),
    );
  }

  // ── App bar ───────────────────────────────────────────────────────────────
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
            'Orders Management',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  // ── Search bar ────────────────────────────────────────────────────────────
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
            hintText: 'Search by order ID, customer or employee...',
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

  // ── Employee filter ───────────────────────────────────────────────────────
  Widget _buildEmployeeFilter() {
    if (_loadingEmployees) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: SizedBox(
          height: 34,
          child: Center(
            child: LinearProgressIndicator(
              color: _accentGreen,
              backgroundColor: _accentGreen.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      );
    }

    final options = <_EmployeeOption>[
      const _EmployeeOption(id: null, label: 'All Employees'),
      const _EmployeeOption(id: '__self__', label: 'Self'),
      ..._employees.map((e) => _EmployeeOption(id: e.id, label: e.name)),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'FILTER BY EMPLOYEE',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Colors.black38,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: options.map((opt) {
                final isSelected = _selectedEmployeeId == opt.id;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () async {
                      setState(() => _selectedEmployeeId = opt.id);
                      await _loadOrders();
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected ? _accentGreen : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected
                              ? _accentGreen
                              : const Color(0xFFE5E7EB),
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: _accentGreen.withValues(alpha: 0.25),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ]
                            : [],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (opt.id == '__self__') ...[
                            Icon(
                              Icons.account_circle_rounded,
                              size: 14,
                              color: isSelected ? Colors.white : Colors.black38,
                            ),
                            const SizedBox(width: 4),
                          ] else if (opt.id == null) ...[
                            Icon(
                              Icons.people_alt_rounded,
                              size: 14,
                              color: isSelected ? Colors.white : Colors.black38,
                            ),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            opt.label,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isSelected ? Colors.white : Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // ── Status chips ──────────────────────────────────────────────────────────
  Widget _buildStatusChips() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _statusFilters.map((status) {
            final isSelected = _selectedStatus == status;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => setState(() => _selectedStatus = status),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected ? _accentGreen : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected
                          ? _accentGreen
                          : const Color(0xFFE5E7EB),
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: _accentGreen.withValues(alpha: 0.25),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : [],
                  ),
                  child: Text(
                    status,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white : Colors.black54,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // ── Order list ────────────────────────────────────────────────────────────
  Widget _buildOrderList() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: _accentGreen),
      );
    }

    final list = _filteredOrders;

    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 52,
              color: Colors.grey[300],
            ),
            const SizedBox(height: 12),
            Text(
              'No orders found',
              style: TextStyle(color: Colors.grey[400], fontSize: 14),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadOrders,
      color: _accentGreen,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: list.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final order = list[index];
          return _OrderCard(
            order: order,
            statusColor: _statusColor(order.status),
            isActionLoading: _actionLoading[order.orderId] ?? false,
            onViewDetails: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => OrderDetailScreen(
                    orderId: order.orderId,
                    initialData: order,
                  ),
                ),
              );
            },
            onApprove: () => _onApprove(order),
            onReject: () => _onReject(order),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Approve Confirmation Dialog
// ─────────────────────────────────────────────────────────────────────────────

class _ApproveDialog extends StatelessWidget {
  final OrderData order;

  const _ApproveDialog({required this.order});

  static const _accentGreen = Color(0xFF1AB69C);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: _accentGreen.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_outline_rounded,
                color: _accentGreen,
                size: 32,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Approve Order?',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Are you sure you want to approve order',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
            const SizedBox(height: 4),
            Text(
              order.orderId,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _accentGreen,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'for ${order.customer}?',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                // Cancel
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(false),
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF4F4F4),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.black54,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Approve
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(true),
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: _accentGreen,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: _accentGreen.withValues(alpha: 0.35),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        'Approve',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
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

// ─────────────────────────────────────────────────────────────────────────────
// Reject Dialog with Reason
// ─────────────────────────────────────────────────────────────────────────────

class _RejectDialog extends StatefulWidget {
  final OrderData order;

  const _RejectDialog({required this.order});

  @override
  State<_RejectDialog> createState() => _RejectDialogState();
}

class _RejectDialogState extends State<_RejectDialog> {
  static const _rejectRed = Color(0xFFEF4444);

  final TextEditingController _reasonController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  String _reasonError = '';

  @override
  void initState() {
    super.initState();
    // Auto-focus reason field after frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _reasonController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onConfirm() {
    final reason = _reasonController.text.trim();
    if (reason.isEmpty) {
      setState(() => _reasonError = 'Rejection reason is required.');
      return;
    }
    Navigator.of(context).pop(reason);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon + title row
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _rejectRed.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.cancel_outlined,
                    color: _rejectRed,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Reject Order',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // Subtitle
            RichText(
              text: TextSpan(
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                children: [
                  const TextSpan(text: 'Rejecting order '),
                  TextSpan(
                    text: widget.order.orderId,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: _rejectRed,
                    ),
                  ),
                  TextSpan(text: ' for ${widget.order.customer}.'),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // Reason label
            const Text(
              'Reason for Rejection',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.black54,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 8),
            // Reason input
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF8F8F8),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _reasonError.isNotEmpty
                      ? _rejectRed
                      : const Color(0xFFE5E7EB),
                  width: 1.2,
                ),
              ),
              child: TextField(
                controller: _reasonController,
                focusNode: _focusNode,
                maxLines: 3,
                minLines: 3,
                textInputAction: TextInputAction.done,
                onChanged: (_) {
                  if (_reasonError.isNotEmpty) {
                    setState(() => _reasonError = '');
                  }
                },
                style: const TextStyle(fontSize: 13, color: Colors.black87),
                decoration: InputDecoration(
                  hintText: 'e.g. Stock not available, incorrect pricing…',
                  hintStyle: TextStyle(fontSize: 12, color: Colors.grey[400]),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
            ),
            // Error message
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              child: _reasonError.isEmpty
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.info_outline_rounded,
                            size: 13,
                            color: _rejectRed,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            _reasonError,
                            style: const TextStyle(
                              fontSize: 12,
                              color: _rejectRed,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
            const SizedBox(height: 24),
            // Buttons
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(null),
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF4F4F4),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.black54,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: _onConfirm,
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: _rejectRed,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: _rejectRed.withValues(alpha: 0.30),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        'Reject',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
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

// ─────────────────────────────────────────────────────────────────────────────
// Employee filter option model
// ─────────────────────────────────────────────────────────────────────────────

class _EmployeeOption {
  final String? id;
  final String label;
  const _EmployeeOption({required this.id, required this.label});
}

// ─────────────────────────────────────────────────────────────────────────────
// Order Card
// ─────────────────────────────────────────────────────────────────────────────

class _OrderCard extends StatelessWidget {
  final OrderData order;
  final Color statusColor;
  final bool isActionLoading;
  final VoidCallback onViewDetails;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  static const _accentGreen = Color(0xFF1AB69C);
  static const _approveGreen = Color(0xFF22C55E);
  static const _rejectRed = Color(0xFFEF4444);

  const _OrderCard({
    required this.order,
    required this.statusColor,
    required this.isActionLoading,
    required this.onViewDetails,
    required this.onApprove,
    required this.onReject,
  });

  bool get _isPending => order.status.toLowerCase() == 'pending';

  String _money(num value) => '₹${value.toStringAsFixed(0)}';

  @override
  Widget build(BuildContext context) {
    final balancePct = order.amount == 0
        ? 0.0
        : (order.outstanding / order.amount).clamp(0.0, 1.0).toDouble();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
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
          // ── Top row: Order ID + Status badge ──────────────────────────
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: _accentGreen.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  order.orderId,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _accentGreen,
                  ),
                ),
              ),
              const Spacer(),
              // Approve + Reject icon buttons — only for Pending
              if (_isPending) ...[
                if (isActionLoading)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _accentGreen,
                    ),
                  )
                else ...[
                  _ActionIconButton(
                    icon: Icons.check_rounded,
                    color: _approveGreen,
                    tooltip: 'Approve',
                    onTap: onApprove,
                  ),
                  const SizedBox(width: 8),
                  _ActionIconButton(
                    icon: Icons.close_rounded,
                    color: _rejectRed,
                    tooltip: 'Reject',
                    onTap: onReject,
                  ),
                  const SizedBox(width: 10),
                ],
              ],
              // Status badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  order.status,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // ── Customer name ─────────────────────────────────────────────
          Text(
            order.customer,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${order.type} • ${order.employee}',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),

          const SizedBox(height: 10),
          const Divider(height: 1, thickness: 0.5, color: Color(0xFFF0F0F0)),
          const SizedBox(height: 10),

          // ── Amount / Paid / Outstanding ───────────────────────────────
          Row(
            children: [
              Expanded(
                child: _StatItem(label: 'AMOUNT', value: _money(order.amount)),
              ),
              Expanded(
                child: _StatItem(
                  label: 'PAID',
                  value: _money(order.paidAmount),
                ),
              ),
              Expanded(
                child: _StatItem(
                  label: 'OUTSTANDING',
                  value: _money(order.outstanding),
                  valueColor: order.outstanding > 0 ? _rejectRed : _accentGreen,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // ── Progress bar ──────────────────────────────────────────────
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: balancePct,
              minHeight: 6,
              backgroundColor: Colors.grey.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation<Color>(statusColor),
            ),
          ),

          const SizedBox(height: 10),

          // ── Date + View Details ───────────────────────────────────────
          Row(
            children: [
              const Icon(
                Icons.calendar_today_outlined,
                size: 13,
                color: Colors.black38,
              ),
              const SizedBox(width: 5),
              Text(
                order.dateLabel,
                style: const TextStyle(fontSize: 12, color: Colors.black45),
              ),
              const Spacer(),
              GestureDetector(
                onTap: onViewDetails,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'View Details',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _accentGreen,
                      ),
                    ),
                    SizedBox(width: 4),
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 14,
                      color: _accentGreen,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Action Icon Button (Approve / Reject)
// ─────────────────────────────────────────────────────────────────────────────

class _ActionIconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  const _ActionIconButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.3), width: 1.2),
          ),
          child: Icon(icon, size: 17, color: color),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stat Item
// ─────────────────────────────────────────────────────────────────────────────

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _StatItem({required this.label, required this.value, this.valueColor});

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
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: valueColor ?? Colors.black87,
          ),
        ),
      ],
    );
  }
}
