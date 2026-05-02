import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:FieldService_app/config.dart';
import 'package:FieldService_app/zonal_services/zonal_orders_service.dart';

class OrderDetailScreen extends StatefulWidget {
  final String orderId;
  final dynamic initialData;

  const OrderDetailScreen({super.key, required this.orderId, this.initialData});

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  final ZonalOrdersService _service = ZonalOrdersService();

  Map<String, dynamic>? _order;
  bool _loading = true;
  String? _error;

  bool _showDetails = true;
  bool _showProducts = true;

  @override
  void initState() {
    super.initState();

    if (widget.initialData != null) {
      _order = _convertInitial(widget.initialData);
      _loading = false;
    }

    _loadOrder(); // background refresh
  }

  Map<String, dynamic> _convertInitial(dynamic data) {
    return {
      "orderId": data.orderId,
      "status": data.status,
      "totalAmount": data.amount,
      "finalAmount": data.amount,
    };
  }

  Future<void> _loadOrder() async {
    try {
      setState(() {
        _loading = true;
        _error = null;
      });

      final res = await _service.fetchOrderById(widget.orderId);

      if (!mounted) return;

      if (res == null) {
        setState(() {
          _error = 'Order not found for ${widget.orderId}';
          _loading = false;
        });
        return;
      }

      setState(() {
        _order = res;
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

  String _formatDate(String? iso) {
    if (iso == null) return '--';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '--';

    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');

    return '${dt.day} ${_month(dt.month)} ${dt.year}, $hour:$minute';
  }

  String _month(int m) => [
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
  ][m - 1];

  String _money(dynamic value) {
    final n = num.tryParse(value?.toString() ?? '') ?? 0;
    return '₹${n.toStringAsFixed(0)}';
  }

  String _safeText(dynamic value, {String fallback = '--'}) {
    final text = value?.toString().trim();
    return (text == null || text.isEmpty) ? fallback : text;
  }

  Color _statusBg(String status) {
    switch (status.toLowerCase()) {
      case 'delivered':
        return const Color(0xFFE6F7F2);
      case 'partially delivered':
        return const Color(0xFFFFF4E5);
      case 'pending':
        return const Color(0xFFEAF2FF);
      case 'cancelled':
        return const Color(0xFFFDECEC);
      default:
        return const Color(0xFFF2F6F3);
    }
  }

  Color _statusFg(String status) {
    switch (status.toLowerCase()) {
      case 'delivered':
        return const Color(0xFF14977A);
      case 'partially delivered':
        return const Color(0xFFE6A23C);
      case 'pending':
        return const Color(0xFF4D8AF0);
      case 'cancelled':
        return const Color(0xFFEF4444);
      default:
        return const Color(0xFF6B7280);
    }
  }

  Widget _roundedCard({required Widget child}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5F7F2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _sectionHeader({
    required String title,
    Widget? trailing,
    BorderRadius? radius,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF2EC7A6),
        borderRadius: radius ?? BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ),
          trailing ?? const SizedBox.shrink(),
        ],
      ),
    );
  }

  Widget _infoRow(String label, dynamic value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 15),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Colors.black54, fontSize: 13),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dashedDivider() {
    return LayoutBuilder(
      builder: (ctx, c) {
        const dash = 6.0;
        const space = 6.0;
        final count = (c.maxWidth / (dash + space)).floor();

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(
            count,
            (_) =>
                Container(width: dash, height: 1, color: Colors.grey.shade300),
          ),
        );
      },
    );
  }

  String? _pickProductImage(dynamic item) {
    final product = item?['productId'];
    if (product is! Map) return null;

    final images = product['productImages'];
    if (images is List && images.isNotEmpty) {
      final first = images.first;
      if (first != null && first.toString().isNotEmpty) {
        return AppConfig.imageUrl(first.toString());
      }
    }

    final image = item['image'];
    if (image != null && image.toString().isNotEmpty) {
      return AppConfig.imageUrl(image.toString());
    }
    return null;
  }

  Widget _buildHeaderCard() {
    final order = _order ?? {};
    final customerWrap = order['customerId'];
    final customerType = customerWrap?['type']?.toString();
    final customer = customerWrap?['id'];

    final status = _safeText(order['status'], fallback: 'Pending');
    final createdAt = _formatDate(order['createdAt']);
    final updatedAt = _formatDate(order['updatedAt']);

    final remarks = _safeText(order['remarks']);
    final deliveryAddress = _safeText(order['deliveryAddress']);
    final totalAmount = _money(order['totalAmount']);
    final finalAmount = _money(order['finalAmount']);
    final companyDiscount = '${_safeText(order['companyDiscountPercentage'])}%';
    final additionalDiscount =
        '${_safeText(order['additionalDiscountPercentage'])}%';

    return _roundedCard(
      child: Column(
        children: [
          _sectionHeader(
            title: _safeText(order['orderId'], fallback: widget.orderId),
            trailing: GestureDetector(
              onTap: () => setState(() => _showDetails = !_showDetails),
              child: RotatedBox(
                quarterTurns: _showDetails ? 2 : 0,
                child: const Icon(Icons.expand_more, color: Colors.white),
              ),
            ),
            radius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          if (_showDetails) ...[
            const SizedBox(height: 12),
            _infoRow('Order Date', createdAt),
            _infoRow('Updated', updatedAt),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 15),
              child: Row(
                children: [
                  const Text(
                    'Status',
                    style: TextStyle(color: Colors.black54, fontSize: 13),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _statusBg(status),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      status,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _statusFg(status),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            _dashedDivider(),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.center,
              child: Text(
                customerType == 'Farmer' ? 'Farmer Details' : 'Dealer Details',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (customerType == 'Farmer') ...[
              _infoRow('Name', customer?['name']),
              _infoRow('Mobile', customer?['mobileNumber']),
              _infoRow('Address', customer?['address']),
              _infoRow('Farmer ID', customer?['farmerId']),
              _infoRow('Land', '${customer?['totalCultureArea']} Acres'),
            ] else if (customerType == 'Dealer') ...[
              _infoRow('Dealer Name', customer?['dealerName']),
              _infoRow('Shop Name', customer?['shopName']),
              _infoRow('Mobile', customer?['mobileNumber']),
              _infoRow('Address', customer?['address']),
            ],
            const SizedBox(height: 10),
            _dashedDivider(),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.center,
              child: Text(
                'Handled By',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(height: 8),
            _infoRow('Employee', order['employeeId']?['firstName']),
            _infoRow('Email', order['employeeId']?['email']),
            _infoRow('Contact', order['employeeId']?['contactNumber']),
            _infoRow('Emp Code', order['employeeId']?['empCode']),
            const SizedBox(height: 10),
            _dashedDivider(),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.center,
              child: Column(
                children: [
                  const Text(
                    'Remarks',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF6FFFB),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE5F7F2)),
                    ),
                    child: Text(
                      remarks,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: const [
                SizedBox(width: 15),
                Icon(Icons.location_on, color: Color(0xFF2EC7A6)),
                SizedBox(width: 6),
                Text(
                  'Shipped To',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 20.0, right: 20),
              child: Text(
                deliveryAddress.isEmpty ? '--' : deliveryAddress,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade700),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(
                left: 15.0,
                right: 15,
                bottom: 12,
                top: 4,
              ),
              child: Row(
                children: [
                  const Text(
                    'Total Amount',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const Spacer(),
                  Text(
                    totalAmount,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 15, right: 15, bottom: 12),
              child: Row(
                children: [
                  const Text(
                    'Final Amount',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const Spacer(),
                  Text(
                    finalAmount,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF14977A),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 15, right: 15, bottom: 12),
              child: Row(
                children: [
                  const Text(
                    'Company Discount',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const Spacer(),
                  Text(companyDiscount),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 15, right: 15, bottom: 12),
              child: Row(
                children: [
                  const Text(
                    'Additional Discount',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const Spacer(),
                  Text(additionalDiscount),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProductsCard() {
    final items = (_order?['items'] is List) ? _order!['items'] as List : [];

    return _roundedCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            title: 'Product Details (${items.length}) Items',
            trailing: GestureDetector(
              onTap: () => setState(() => _showProducts = !_showProducts),
              child: RotatedBox(
                quarterTurns: _showProducts ? 2 : 0,
                child: const Icon(Icons.expand_more, color: Colors.white),
              ),
            ),
            radius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          if (_showProducts)
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                children: List.generate(items.length, (i) {
                  return _productTile(items[i]);
                }),
              ),
            ),
        ],
      ),
    );
  }

  Widget _productTile(dynamic item) {
    final product = item['productId'] ?? {};
    final imageUrl = _pickProductImage(item);

    final productName = _safeText(product['productName'], fallback: 'Product');
    final qty = _safeText(item['quantity'], fallback: '1');
    final deliveredQty = _safeText(item['deliveredQty'], fallback: '0');
    final pendingQty = _safeText(item['pendingQty'], fallback: '0');

    final price = item['price'];
    final subtotal = item['subtotal'];
    final displayAmount = subtotal ?? price ?? '--';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE5F7F2)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: imageUrl == null
                ? Container(
                    width: 64,
                    height: 64,
                    color: Colors.grey.shade200,
                    child: const Icon(Icons.inventory_2_outlined),
                  )
                : CachedNetworkImage(
                    imageUrl: imageUrl,
                    width: 64,
                    height: 64,
                    fit: BoxFit.cover,
                    placeholder: (_, _) => Container(
                      width: 64,
                      height: 64,
                      color: Colors.grey.shade200,
                    ),
                    errorWidget: (_, _, _) => Container(
                      width: 64,
                      height: 64,
                      color: Colors.grey.shade200,
                      child: const Icon(Icons.broken_image),
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  productName,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  'Qty : $qty',
                  style: TextStyle(color: Colors.grey.shade800),
                ),
                Text(
                  'Delivered : $deliveredQty',
                  style: TextStyle(color: Colors.grey.shade800),
                ),
                Text(
                  'Pending : $pendingQty',
                  style: TextStyle(color: Colors.grey.shade800),
                ),
              ],
            ),
          ),
          Text(
            '₹$displayAmount',
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _order == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _order == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.red),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadOrder,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 30),
        child: Column(
          children: [
            const SizedBox(height: 6),
            _buildHeaderCard(),
            _buildProductsCard(),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(60),
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
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_sharp, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: const Text(
            'Order Details',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.white,
              fontSize: 20,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4FBF8),
      appBar: _buildAppBar(),
      body: SafeArea(child: _buildBody()),
    );
  }
}
