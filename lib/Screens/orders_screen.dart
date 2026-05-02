import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:FieldService_app/Screens/order_full_detail_screen.dart';
import 'package:FieldService_app/Screens/main_page.dart';
import 'package:FieldService_app/config.dart';
import 'package:FieldService_app/main.dart';
import 'package:FieldService_app/widgets/shared_bottom_nav.dart';

class OrdersScreen extends StatefulWidget {
  final bool condition;
  const OrdersScreen({super.key, required this.condition});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen>
    with SingleTickerProviderStateMixin {
  bool _isLoading = false;
  String? _error;

  late TabController _tabController;

  List<Map<String, dynamic>> _dealerOrders = [];
  List<Map<String, dynamic>> _farmerOrders = [];
  static const Color _primary = Color(0xFF1AB69C);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchOrders();
  }

  Future<void> _fetchOrders() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final employeeId = prefs.getString('userId') ?? '';

      if (employeeId.isEmpty) {
        setState(() {
          _error = "Employee ID missing.";
          _isLoading = false;
        });
        return;
      }

      // 🔥 Use CACHED GET with TTL 30 min
      final result = await apiClient.getJsonCached(
        path: AppConfig.ordersById.replaceAll('{employeeid}', employeeId),
        cacheKey: 'orders_$employeeId',
        ttl: const Duration(minutes: 30),
      );

      final data = result.data;

      if (data is Map && data["orders"] is List) {
        final list = List<Map<String, dynamic>>.from(data["orders"]);
        // sort newest first
        list.sort((a, b) {
          final da = DateTime.tryParse(a["createdAt"] ?? "") ?? DateTime(2000);
          final db = DateTime.tryParse(b["createdAt"] ?? "") ?? DateTime(2000);
          return db.compareTo(da);
        });

        final dealers = <Map<String, dynamic>>[];
        final farmers = <Map<String, dynamic>>[];

        for (final o in list) {
          final type = o["customerId"]?["type"]?.toString();
          if (type == "Dealer") {
            dealers.add(o);
          } else if (type == "Farmer") {
            farmers.add(o);
          }
        }

        setState(() {
          _dealerOrders = dealers;
          _farmerOrders = farmers;
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = data?["message"]?.toString() ?? "Failed to load orders";
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = "Network error: $e";
        _isLoading = false;
      });
    }
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case "pending":
        return Color(0xFF1AB69C);
      case "confirmed":
      case "placed":
        return Color(0xFF1AB69C);
      case "shipped":
      case "delivered":
        return Color(0xFF1AB69C);
      case "paid":
        return Color(0xFF1AB69C);
      default:
        return Color(0xFF1AB69C);
    }
  }

  Widget _buildDashedLine() {
    return SizedBox(
      height: 12,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final boxWidth = constraints.constrainWidth();
          const dashWidth = 6.0;
          const dashSpace = 6.0;
          final dashCount = (boxWidth / (dashWidth + dashSpace)).floor();
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(dashCount, (_) {
              return SizedBox(
                width: dashWidth,
                height: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: Colors.grey.shade400),
                ),
              );
            }),
          );
        },
      ),
    );
  }

  Widget _buildOrderItemCard(Map<String, dynamic> order, int index) {
    final orderId = order["orderId"]?.toString() ?? order["_id"] ?? "";
    final status =
        order["orderStatus"]?.toString() ??
        order["status"]?.toString() ??
        "New";
    final totalAmount = order["totalAmount"]?.toString() ?? "--";
    final customer = order["customerId"]?["id"] as Map<String, dynamic>?;

    final customerName =
        customer?["dealerName"] ??
        customer?["farmerName"] ??
        customer?["shopName"] ??
        "Customer";

    final items = order["items"] as List<dynamic>? ?? [];
    final itemCount = items.length;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => OrderFullDetailScreen(
              orderId: orderId,
              initial: order, // <<<<<< ADD
            ),
          ),
        );
      },

      child: Card(
        elevation: 3,
        margin: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Column(
          children: [
            // top strip: left circle index overlapping + blue header
            Stack(
              clipBehavior: Clip.none,
              children: [
                // Blue header area
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Color(0xFF1AB69C),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(56, 12, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // order id + status
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              orderId,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),

                          // status pill
                        ],
                      ),
                      const SizedBox(height: 8),
                      // dealer row
                      Row(
                        children: [
                          const Icon(
                            Icons.person,
                            size: 18,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              customerName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              status,
                              style: TextStyle(
                                color: _statusColor(status),
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // circular index on left (overlapping)
                Positioned(
                  left: 10,
                  top: 8,
                  child: CircleAvatar(
                    radius: 20,
                    backgroundColor: Colors.white,
                    // add subtle border
                    foregroundColor: Colors.black,
                    child: Text(
                      (index + 1).toString().padLeft(2, '0'),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // body details
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                children: [
                  // No.of Products / Order Date row
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              "No.of Products:",
                              style: TextStyle(fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            itemCount.toString(),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text("Order Date:", style: TextStyle(fontSize: 14)),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            _formatDate(order["createdAt"]?.toString()),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),
                  // dashed divider
                  _buildDashedLine(),
                  const SizedBox(height: 8),

                  // bottom row: left Pre Pay, right amount
                  Row(
                    children: [
                      const Text(
                        "Total Amount",
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const Spacer(),
                      Text(
                        "₹$totalAmount",
                        style: const TextStyle(
                          color: Color(0xFF1AB69C),
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
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
    );
  }

  static String _formatDate(String? dateStr) {
    if (dateStr == null) return "--";
    try {
      final dt =
          DateTime.tryParse(dateStr) ?? DateTime.fromMillisecondsSinceEpoch(0);
      return "${dt.day.toString().padLeft(2, '0')} ${_monthName(dt.month)} ${dt.year}";
    } catch (_) {
      return dateStr.split('T').first;
    }
  }

  static String _monthName(int m) {
    const names = [
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
    return names[(m - 1).clamp(0, 11)];
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !widget.condition, // allow pop only when condition is false
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;

        if (widget.condition) {
          _goToHome(); // block pop & go home
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,

        appBar: AppBar(
          title: const Text(
            'Orders',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),
          centerTitle: true,
          backgroundColor: _primary,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_sharp, color: Colors.white),
            onPressed: () {
              if (widget.condition) {
                _goToHome();
              } else {
                Navigator.pop(context);
              }
            },
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(65),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Colors.white, width: 0.5),
                ),
              ),
              child: TabBar(
                controller: _tabController,
                indicatorColor: Colors.white,
                indicatorWeight: 3,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white,
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
                tabs: const [
                  Tab(
                    icon: Icon(Icons.store, color: Colors.white),
                    text: 'Dealers',
                  ),
                  Tab(
                    icon: Icon(Icons.people, color: Colors.white),
                    text: 'Farmers',
                  ),
                ],
              ),
            ),
          ),
        ),

        body: Column(
          children: [
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildOrdersList(_dealerOrders),
                  _buildOrdersList(_farmerOrders),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrdersList(List<Map<String, dynamic>> list) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Text(
          _error!,
          style: const TextStyle(color: Colors.red, fontSize: 16),
        ),
      );
    }

    if (list.isEmpty) {
      return const Center(
        child: Text("No orders found.", style: TextStyle(fontSize: 16)),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchOrders,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: list.length,
        itemBuilder: (context, i) {
          return _buildOrderItemCard(list[i], i);
        },
      ),
    );
  }

  void _goToHome() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => const MainPage(initialMenu: MenuState.homedashboard),
      ),
      (route) => false,
    );
  }
}
