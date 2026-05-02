// ---------------------------------------------------------
// ORDER DETAILS SCREEN — FULL COLOR-MATCHED UI VERSION
// ---------------------------------------------------------

import 'dart:async';
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:FieldService_app/config.dart';
import 'package:FieldService_app/main.dart';
import 'package:FieldService_app/offline/cache_store.dart';
import 'package:FieldService_app/services/secure_storage_service.dart';

class OrderFullDetailScreen extends StatefulWidget {
  final String orderId;
  final Map<String, dynamic>? initial;

  const OrderFullDetailScreen({super.key, required this.orderId, this.initial});

  @override
  State<OrderFullDetailScreen> createState() => _OrderFullDetailScreenState();
}

class _OrderFullDetailScreenState extends State<OrderFullDetailScreen> {
  Map<String, dynamic>? _order;
  bool _loading = false;
  String? _error;

  bool _showDetails = true;
  bool _showProducts = true;

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) {
      _order = Map<String, dynamic>.from(widget.initial!);
      unawaited(_loadOrder(silent: true));
    } else {
      _loadOrder();
    }
  }

  String _orderCacheKey(String orderId) {
    return 'order:detail:$orderId';
  }

  // ---------------------------------------------------------------------------
  // API LOAD
  // ---------------------------------------------------------------------------
  Future<void> _loadOrder({bool retry = false, bool silent = false}) async {
    if (!silent) setState(() => _loading = true);

    final cacheKey = _orderCacheKey(widget.orderId);
    bool hadCache = false;

    try {
      // -------------------- STEP 1: Serve CACHE immediately --------------------
      final cached = apiClient.cache?.get(cacheKey);
      if (cached != null && cached.body.isNotEmpty) {
        try {
          final decoded = jsonDecode(cached.body);
          if (decoded is Map && decoded["order"] is Map) {
            _order = Map<String, dynamic>.from(decoded["order"]);
            hadCache = true;
            if (mounted) setState(() {});
            _prefetchProductImages(_order); // 🔥 important
          }
        } catch (_) {}
      }

      // -------------------- STEP 2: Network refresh --------------------
      //final prefs = await SharedPreferences.getInstance();
      //final token = prefs.getString("token");
      final token = await SecureStorageService.getToken();
      final uri = AppConfig.uriT("/api/order/{orderId}", {
        "orderId": widget.orderId,
      });

      final resp = await http
          .get(
            uri,
            headers: {
              "Accept": "application/json",
              if (token != null) "Authorization": "Bearer $token",
            },
          )
          .timeout(const Duration(seconds: 10));

      final body = jsonDecode(resp.body);

      if (resp.statusCode == 200 && body["order"] is Map) {
        // Save to cache
        await apiClient.cache?.put(
          cacheKey,
          CacheEntry(
            body: resp.body,
            statusCode: resp.statusCode,
            storedAtMillis: DateTime.now().millisecondsSinceEpoch,
          ),
        );

        _order = Map<String, dynamic>.from(body["order"]);
        if (mounted) setState(() {});
        _prefetchProductImages(_order); // 🔥 important
      } else if (!hadCache && !silent) {
        setState(() {
          _error = body["message"] ?? "Unexpected Server Error.";
        });
      }
    } catch (e) {
      if (!hadCache && !silent) {
        setState(() {
          _error = e.toString().contains("SocketException")
              ? "No Internet Connection"
              : "$e";
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? _resolveProductImagePath(dynamic product) {
    if (product == null || product is! Map<String, dynamic>) return null;

    final dynamic images = product['productImages'];
    if (images is List && images.isNotEmpty) {
      final first = images.first;
      if (first is String && first.isNotEmpty) return first;
    }

    final dynamic single = product['productImage'];
    if (single is String && single.isNotEmpty) return single;

    return null;
  }

  void _prefetchProductImages(Map<String, dynamic>? order) {
    if (order == null) return;

    final items = order["items"];
    if (items is! List) return;

    for (final it in items) {
      final p = it["productId"];
      final imgPath = _resolveProductImagePath(p);
      if (imgPath == null) continue;

      final url = AppConfig.imageUrl(imgPath);

      // Pre-download & store in disk cache
      CachedNetworkImageProvider(url).resolve(const ImageConfiguration());
    }
  }

  // ---------------------------------------------------------------------------
  // CARD WRAPPER
  // ---------------------------------------------------------------------------
  Widget _roundedCard({required Widget child}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5F7F2)), // mint border
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

  // ---------------------------------------------------------------------------
  // HEADER CARD — STATUS STYLE UPDATED
  // ---------------------------------------------------------------------------
  Widget _buildHeaderCard() {
    final order = _order ?? {};
    final id = order["orderId"] ?? order["_id"] ?? widget.orderId;
    final status = (order["status"] ?? "Delivered").toString();
    final customer = order["customerId"];
    final customerType = customer?["type"];
    final customerData = customer?["id"];

    final created = _formatDate(order["createdAt"]);

    return _roundedCard(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 1),
        child: Column(
          children: [
            _sectionHeader(
              title: id,
              trailing: GestureDetector(
                onTap: () => setState(() => _showDetails = !_showDetails),
                child: RotatedBox(
                  quarterTurns: _showDetails ? 2 : 0,
                  child: const Icon(Icons.expand_more, color: Colors.white),
                ),
              ),
            ),

            if (_showDetails) ...[
              const SizedBox(height: 12),

              _infoRow("Order Date", created),
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 6,
                  horizontal: 15,
                ),
                child: Row(
                  children: [
                    const Text(
                      "Status",
                      style: TextStyle(color: Colors.black54),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: status.toLowerCase() == "pending"
                            ? const Color(0xFFFFF4E5)
                            : const Color(0xFFE6F7F2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        status,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: status.toLowerCase() == "pending"
                              ? const Color(0xFFE6A23C)
                              : const Color(0xFF14977A),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // _infoRow("Trip ID", order["tripId"]),
              const SizedBox(height: 10),
              _dashedDivider(),
              const SizedBox(height: 12),

              Align(
                alignment: Alignment.center,
                child: Text(
                  customerType == "Farmer"
                      ? "Farmer Details"
                      : "Dealer Details",
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),

              const SizedBox(height: 8),

              if (customerType == "Dealer") ...[
                _infoRow("Dealer Name", customerData?["dealerName"]),
                _infoRow("Shop Name", customerData?["shopName"]),
                _infoRow("Mobile", customerData?["mobileNumber"]),
              ] else if (customerType == "Farmer") ...[
                _infoRow("Farmer Name", customerData?["name"]),
                _infoRow("Mobile", customerData?["mobileNumber"]),
                _infoRow("Address", customerData?["shopAddress"]),
              ],

              const SizedBox(height: 10),

              // _dashedDivider(),
              // const SizedBox(height: 12),

              // const Align(
              //   alignment: Alignment.centerLeft,
              //   child: Text(
              //     "Employee Details",
              //     style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              //   ),
              // ),
              // const SizedBox(height: 8),

              // _infoRow("Employee", order["employeeId"]?["firstName"]),
              // _infoRow("Emp Code", order["employeeId"]?["empCode"]),
              const SizedBox(height: 10),
              _dashedDivider(),
              const SizedBox(height: 12),

              Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(width: 10),
                  const Text(
                    "Remarks",
                    style: TextStyle(
                      //color: Colors.black54,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: 300,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF6FFFB),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE5F7F2)),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      order["remarks"]?.toString().isNotEmpty == true
                          ? order["remarks"].toString()
                          : "--",
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              Row(
                children: const [
                  SizedBox(width: 6),
                  Icon(Icons.location_on, color: Color(0xFF2EC7A6)),
                  SizedBox(width: 6),
                  Text(
                    "Shipped To",
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              Padding(
                padding: const EdgeInsets.only(left: 20.0),
                child: Align(
                  alignment: Alignment.center,
                  //widthFactor: 50,
                  child: Text(
                    order["deliveryAddress"]?.toString() ?? "",
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ),
              ),

              const SizedBox(height: 10),

              Padding(
                padding: const EdgeInsets.only(
                  left: 15.0,
                  right: 15,
                  bottom: 10,
                ),
                child: Row(
                  children: [
                    const Text(
                      "Total Amount",
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const Spacer(),
                    Text(
                      "₹${order["totalAmount"] ?? '--'}",
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, dynamic value) {
    if (value == null || value.toString().isEmpty) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 15),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(color: Colors.black54)),
          ),
          Expanded(
            child: Text(
              value.toString(),
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // PRODUCT CARD LIST — UPDATED HEADER COLORS
  // ---------------------------------------------------------------------------
  Widget _buildProductsCard() {
    final items = (_order?["items"] is List) ? _order!["items"] : [];

    return _roundedCard(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Green header bar
            _sectionHeader(
              title: "Product Details (${items.length}) Items",
              radius: const BorderRadius.vertical(top: Radius.circular(16)),
              trailing: GestureDetector(
                onTap: () => setState(() => _showProducts = !_showProducts),
                child: RotatedBox(
                  quarterTurns: _showProducts ? 2 : 0,
                  child: const Icon(Icons.expand_more, color: Colors.white),
                ),
              ),
            ),

            if (_showProducts)
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  children: List.generate(items.length, (i) {
                    final item = items[i];
                    return _productTile(item);
                  }),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // PRODUCT TILE COLORS UPDATED
  Widget _productTile(dynamic it) {
    final p = it["productId"];
    final productImagePath = _resolveProductImagePath(p);
    final img = (productImagePath != null)
        ? AppConfig.imageUrl(productImagePath)
        : null;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE5F7F2)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: img != null
                ? CachedNetworkImage(
                    imageUrl: img,
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
                  )
                : Container(
                    width: 64,
                    height: 64,
                    color: Colors.grey.shade200,
                    child: const Icon(Icons.image_not_supported),
                  ),
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p?["productName"]?.toString() ?? "Product",
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  "Qty : ${it["quantity"] ?? 1}",
                  style: TextStyle(color: Colors.grey.shade800),
                ),
              ],
            ),
          ),

          Text(
            "₹${it["subtotal"] ?? it["price"] ?? '--'}",
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }

  // dashed divider
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

  // Formatting
  String _formatDate(String? iso) {
    if (iso == null) return "--";
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return "--";
    return "${dt.day} ${_month(dt.month)} ${dt.year}, ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}";
  }

  String _month(int m) => [
    "Jan",
    "Feb",
    "Mar",
    "Apr",
    "May",
    "Jun",
    "Jul",
    "Aug",
    "Sep",
    "Oct",
    "Nov",
    "Dec",
  ][m - 1];

  // ---------------------------------------------------------------------------
  // MAIN BUILD
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4FBF8),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: Container(
          decoration: const BoxDecoration(
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
            gradient: LinearGradient(
              colors: [
                Color(0xFF52D494), // top gradient
                Color(0xFF1AB69C), // bottom gradient
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: AppBar(
            backgroundColor: Colors.transparent, // IMPORTANT
            elevation: 0,
            automaticallyImplyLeading: false,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
            ),
            title: const Text(
              'Order Details',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
                fontSize: 20,
              ),
            ),
            centerTitle: true,

            leading: IconButton(
              icon: const Icon(Icons.arrow_back_sharp, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),

            // Optional right-side spacing / future actions
            actions: [
              Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ],
          ),
        ),
      ),

      body: SafeArea(child: _buildBody()),
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
          ?trailing,
        ],
      ),
    );
  }

  Widget _buildBody() {
    return Column(
      children: [
        Expanded(
          child: _loading && _order == null
              ? const Center(child: CircularProgressIndicator())
              : _error != null && _order == null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _loadOrder,
                  child: SingleChildScrollView(
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
                ),
        ),
      ],
    );
  }
}
