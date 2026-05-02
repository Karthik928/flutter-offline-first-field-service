// clients.dart
// Flutter page showing Dealers and Farmers (clients) in two tabs.
// Mirrors style, color scheme and caching/error behavior from tickets.dart
// Requires packages: http, shared_preferences, intl
// Optional: url_launcher for phone call / navigation functionality.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:FieldService_app/config.dart';
import 'package:FieldService_app/services/secure_storage_service.dart';
import 'package:url_launcher/url_launcher.dart';

class ClientsPage extends StatefulWidget {
  const ClientsPage({super.key});

  @override
  State<ClientsPage> createState() => _ClientsPageState();
}

class _ClientsPageState extends State<ClientsPage>
    with TickerProviderStateMixin {
  late TabController _tabController;

  bool _loading = true;
  String? _error;

  List<DealerClient> _dealerClients = [];
  List<FarmerClient> _farmerClients = [];

  String _dealerSearch = '';
  String _farmerSearch = '';

  final DateFormat _dateFormat = DateFormat.yMMMd().add_jm();
  static const Color _primary = Color(0xFF1AB69C);

  final Map<String, Future<List<VisitActivity>>> _visitFutureCache = {};

  // add near top of class (you already import intl)
  final NumberFormat _moneyFormat = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );

  // returns "Today", "1 day ago", "7 days ago", "1 month ago", "3 months ago"
  // String _relativeTimeText(DateTime? dt) {
  //   if (dt == null) return 'Unknown';
  //   final now = DateTime.now();
  //   final then = dt.toLocal();
  //   final diff = now.difference(then);
  //   if (diff.inDays == 0) {
  //     if (diff.inHours == 0) return 'Just now';
  //     return '${diff.inHours} ${diff.inHours == 1 ? "hour" : "hours"} ago';
  //   }
  //   if (diff.inDays < 30) {
  //     return '${diff.inDays} ${diff.inDays == 1 ? "day" : "days"} ago';
  //   }
  //   final months = (diff.inDays / 30).floor();
  //   if (months == 1) return '1 month ago';
  //   return '$months months ago';
  // }

  String _formatMoney(num amount) {
    try {
      return _moneyFormat.format(amount);
    } catch (e) {
      return amount.toString();
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() => setState(() {}));
    _loadClients();
  }

  Future<void> _loadClients() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('userId');

    if (userId == null || userId.isEmpty) {
      setState(() {
        _error = 'No employee id found in SharedPreferences (key: userId)';
        _loading = false;
      });
      return;
    }

    try {
      final dealers = await fetchDealerClients(userId);
      final farmers = await fetchFarmerClients(userId);

      // Only keep approved items
      setState(() {
        _dealerClients = dealers
            .where((d) => d.status.toLowerCase() == 'approved')
            .toList();
        _farmerClients = farmers
            .where((f) => f.status.toLowerCase() == 'approved')
            .toList();
        _loading = false;
      });
    } catch (e) {
      debugPrint('⚠️ Error fetching clients: $e');

      // Fallback to cached data
      final dealerCache = prefs.getString('dealerClientsCache');
      final farmerCache = prefs.getString('farmerClientsCache');

      if (dealerCache != null || farmerCache != null) {
        setState(() {
          _dealerClients = dealerCache != null
              ? (json.decode(dealerCache) as List)
                    .map((e) => DealerClient.fromJson(e))
                    .where((d) => d.status.toLowerCase() == 'approved')
                    .toList()
              : [];
          _farmerClients = farmerCache != null
              ? (json.decode(farmerCache) as List)
                    .map((e) => FarmerClient.fromJson(e))
                    .where((f) => f.status.toLowerCase() == 'approved')
                    .toList()
              : [];
          _error = 'Offline mode: showing last saved data.';
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'Failed to load clients';
          _dealerClients = [];
          _farmerClients = [];
          _loading = false;
        });
      }
    }
  }

  Color statusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'pending':
        return Colors.orange;
      case 'completed':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  Future<Map<String, String>> _buildHeaders({bool json = false}) async {
    //final prefs = await SharedPreferences.getInstance();
    final token = await SecureStorageService.getToken();
    return {
      'Accept': 'application/json',
      if (json) 'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  Future<List<DealerClient>> fetchDealerClients(String employeeId) async {
    final baseurl = AppConfig.apiBase;
    // AppConfig.dealerByEmployee is expected to contain '/api/dealers/employee/{id}'
    final endpoint = AppConfig.dealerByEmployee.replaceFirst(
      '{id}',
      employeeId,
    );
    final uri = Uri.parse('$baseurl$endpoint');
    final headers = await _buildHeaders();
    final prefs = await SharedPreferences.getInstance();

    try {
      final res = await http.get(uri, headers: headers);
      debugPrint('GET $uri -> ${res.statusCode}');

      if (res.statusCode == 200) {
        final Map<String, dynamic> body =
            json.decode(res.body) as Map<String, dynamic>;
        final List jsonList = (body['dealers'] ?? []) as List;
        await prefs.setString('dealerClientsCache', json.encode(jsonList));
        return jsonList.map((e) => DealerClient.fromJson(e)).toList();
      } else if (res.statusCode == 404) {
        await prefs.remove('dealerClientsCache');
        return [];
      } else {
        throw Exception('Failed to load dealer clients (${res.statusCode})');
      }
    } catch (e) {
      debugPrint('⚠️ Dealers API failed, using cache: $e');
      final cached = prefs.getString('dealerClientsCache');
      if (cached != null) {
        final List jsonList = json.decode(cached) as List;
        return jsonList.map((e) => DealerClient.fromJson(e)).toList();
      }
      rethrow;
    }
  }

  // Fetch visit activities for a single dealer by id
  Future<List<VisitActivity>> fetchDealerVisitActivities(
    String dealerId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = 'dealer_visit_cache_$dealerId';

    final baseurl = AppConfig.apiBase;
    final endpoint = AppConfig.dealerByID.replaceFirst('{id}', dealerId);
    final uri = Uri.parse('$baseurl$endpoint');
    final headers = await _buildHeaders();

    try {
      final res = await http.get(uri, headers: headers);
      debugPrint('GET $uri -> ${res.statusCode}');

      if (res.statusCode == 200) {
        final Map<String, dynamic> body =
            json.decode(res.body) as Map<String, dynamic>;
        final dealer = body['dealer'] as Map<String, dynamic>?;

        final List raw = (dealer?['visitActivities'] ?? []) as List;

        // Parse
        final activities = raw
            .map(
              (e) => VisitActivity.fromJson((e as Map).cast<String, dynamic>()),
            )
            .toList();

        // 🔽 SORT: latest-first
        activities.sort((a, b) {
          final da = a.date ?? DateTime.fromMillisecondsSinceEpoch(0);
          final db = b.date ?? DateTime.fromMillisecondsSinceEpoch(0);
          return db.compareTo(da);
        });

        // 💾 CACHE
        await prefs.setString(cacheKey, json.encode(raw));

        return activities;
      }

      throw Exception('Dealer visit API failed');
    } catch (e) {
      debugPrint('⚠️ Using cached visit activities for dealer $dealerId');

      // 🔁 FALLBACK TO CACHE
      final cached = prefs.getString(cacheKey);
      if (cached != null) {
        final List raw = json.decode(cached) as List;

        final activities = raw
            .map(
              (e) => VisitActivity.fromJson((e as Map).cast<String, dynamic>()),
            )
            .toList();

        // ensure sorted even from cache
        activities.sort((a, b) {
          final da = a.date ?? DateTime.fromMillisecondsSinceEpoch(0);
          final db = b.date ?? DateTime.fromMillisecondsSinceEpoch(0);
          return db.compareTo(da);
        });

        return activities;
      }

      rethrow;
    }
  }

  Future<List<VisitActivity>> fetchFarmerVisitActivities(
    String farmerId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = 'farmer_visit_cache_$farmerId';

    final baseurl = AppConfig.apiBase;
    final endpoint = AppConfig.farmerByID.replaceFirst('{id}', farmerId);
    final uri = Uri.parse('$baseurl$endpoint');
    final headers = await _buildHeaders();

    try {
      final res = await http.get(uri, headers: headers);
      debugPrint('GET $uri -> ${res.statusCode}');

      if (res.statusCode == 200) {
        final Map<String, dynamic> body =
            json.decode(res.body) as Map<String, dynamic>;
        final farmer = body['farmer'] as Map<String, dynamic>?;

        final List raw = (farmer?['visitActivities'] ?? []) as List;

        final activities = raw
            .map(
              (e) => VisitActivity.fromJson((e as Map).cast<String, dynamic>()),
            )
            .toList();

        // latest-first
        activities.sort((a, b) {
          final da = a.date ?? DateTime.fromMillisecondsSinceEpoch(0);
          final db = b.date ?? DateTime.fromMillisecondsSinceEpoch(0);
          return db.compareTo(da);
        });

        await prefs.setString(cacheKey, json.encode(raw));
        return activities;
      }

      throw Exception('Farmer visit API failed');
    } catch (e) {
      debugPrint('⚠️ Using cached visit activities for farmer $farmerId');

      final cached = prefs.getString(cacheKey);
      if (cached != null) {
        final List raw = json.decode(cached) as List;

        final activities = raw
            .map(
              (e) => VisitActivity.fromJson((e as Map).cast<String, dynamic>()),
            )
            .toList();

        activities.sort((a, b) {
          final da = a.date ?? DateTime.fromMillisecondsSinceEpoch(0);
          final db = b.date ?? DateTime.fromMillisecondsSinceEpoch(0);
          return db.compareTo(da);
        });

        return activities;
      }

      rethrow;
    }
  }

  Future<List<FarmerClient>> fetchFarmerClients(String employeeId) async {
    final baseurl = AppConfig.apiBase;
    final endpoint = AppConfig.farmersByEmployee.replaceFirst(
      '{id}',
      employeeId,
    );
    final uri = Uri.parse('$baseurl$endpoint');
    final headers = await _buildHeaders();
    final prefs = await SharedPreferences.getInstance();

    try {
      final res = await http.get(uri, headers: headers);
      debugPrint('GET $uri -> ${res.statusCode}');

      if (res.statusCode == 200) {
        final Map<String, dynamic> body =
            json.decode(res.body) as Map<String, dynamic>;
        final List jsonList = (body['farmers'] ?? []) as List;
        await prefs.setString('farmerClientsCache', json.encode(jsonList));
        return jsonList.map((e) => FarmerClient.fromJson(e)).toList();
      } else if (res.statusCode == 404) {
        await prefs.remove('farmerClientsCache');
        return [];
      } else {
        throw Exception('Failed to load farmer clients (${res.statusCode})');
      }
    } catch (e) {
      debugPrint('⚠️ Farmers API failed, using cache: $e');
      final cached = prefs.getString('farmerClientsCache');
      if (cached != null) {
        final List jsonList = json.decode(cached) as List;
        return jsonList.map((e) => FarmerClient.fromJson(e)).toList();
      }
      rethrow;
    }
  }

  List<DealerClient> get _filteredDealers {
    if (_dealerSearch.trim().isEmpty) return _dealerClients;
    final q = _dealerSearch.toLowerCase();
    return _dealerClients.where((t) {
      return t.dealerName.toLowerCase().contains(q) ||
          t.mobileNumber.contains(q) ||
          t.shopAddress.toLowerCase().contains(q) ||
          t.shopName.toLowerCase().contains(q);
    }).toList();
  }

  List<FarmerClient> get _filteredFarmers {
    if (_farmerSearch.trim().isEmpty) return _farmerClients;
    final q = _farmerSearch.toLowerCase();
    return _farmerClients.where((t) {
      return t.farmerName.toLowerCase().contains(q) ||
          t.mobileNumber.contains(q) ||
          t.address.toLowerCase().contains(q);
    }).toList();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Clients',
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
          onPressed: () => Navigator.pop(context),
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
              unselectedLabelColor: Colors.white,
              indicatorWeight: 3,
              labelStyle: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
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
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _buildError()
          : TabBarView(
              controller: _tabController,
              children: [
                Container(
                  color: _primary.withValues(alpha: 0.02),
                  child: _dealerListView(),
                ),
                Container(
                  color: Colors.green.withValues(alpha: 0.02),
                  child: _farmerListView(),
                ),
              ],
            ),
    );
  }

  Widget _dealerListView() {
    final dealers = _filteredDealers;
    return RefreshIndicator(
      onRefresh: _loadClients,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search by name, phone, shop or address',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => _dealerSearch = v),
          ),
          const SizedBox(height: 12),
          if (dealers.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 80),
              child: Center(child: Text('No dealer clients found')),
            )
          else
            ...dealers.map(_dealerCard),
        ],
      ),
    );
  }

  Widget _farmerListView() {
    final farmers = _filteredFarmers;
    return RefreshIndicator(
      onRefresh: _loadClients,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search by farmer name, phone or address',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => _farmerSearch = v),
          ),
          const SizedBox(height: 12),
          if (farmers.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 80),
              child: Center(child: Text('No farmer clients found')),
            )
          else
            ...farmers.map(_farmerCard),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Error: $_error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red),
            ),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _loadClients, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  Widget _dealerCard(DealerClient t) {
    String initials(String s) {
      final parts = s.trim().split(RegExp(r'\s+'));
      if (parts.isEmpty) return '?';
      if (parts.length == 1) return parts[0][0].toUpperCase();
      return (parts[0][0] + parts.last[0]).toUpperCase();
    }

    final rt = _relativeTimeWithColor(t.lastActivity!.date);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Material(
        elevation: 3, // slightly softer
        borderRadius: BorderRadius.circular(18),
        shadowColor: Colors.black.withValues(alpha: 0.15),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _openDealerBottomSheet(t),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ▌ Header (Shop Name)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: _primary,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(18),
                  ),
                ),
                child: Text(
                  t.shopName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),

              // ▌ Body
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: _primary.withValues(alpha: 0.9),
                      child: Text(
                        initials(t.dealerName),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),

                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Dealer name
                          Text(
                            t.dealerName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),

                          const SizedBox(height: 6),

                          //Phone (tap hint)
                          Row(
                            children: [
                              const Icon(
                                Icons.phone,
                                size: 15,
                                color: Color(0xFF50C6B4),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                t.mobileNumber,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),

                          // const SizedBox(height: 6),

                          // // Address (softer)
                          // Row(
                          //   crossAxisAlignment: CrossAxisAlignment.start,
                          //   children: [
                          //     const Icon(
                          //       Icons.location_on,
                          //       size: 15,
                          //       color: Colors.grey,
                          //     ),
                          //     const SizedBox(width: 6),
                          //     Expanded(
                          //       child: Text(
                          //         t.shopAddress,
                          //         maxLines: 2,
                          //         overflow: TextOverflow.ellipsis,
                          //         style: const TextStyle(
                          //           fontSize: 13,
                          //           color: Colors.black54,
                          //         ),
                          //       ),
                          //     ),
                          //   ],
                          // ),
                          const SizedBox(height: 6),

                          // Bottom row: Due + Last visit
                          Row(
                            children: [
                              Expanded(
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.account_balance_wallet,
                                      size: 15,
                                      color: Color(0xFF50C6B4),
                                    ),
                                    const SizedBox(width: 6),
                                    t.pendingAmount > 0
                                        ? Text(
                                            'Due: ${_formatMoney(t.pendingAmount)}',
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.red,
                                            ),
                                          )
                                        : const Text(
                                            'No Due',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFF50C6B4),
                                            ),
                                          ),
                                  ],
                                ),
                              ),
                              if (t.lastActivity?.date != null)
                                Text(
                                  rt.text,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: rt.color,
                                    fontWeight: FontWeight.w600,
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _farmerCard(FarmerClient t) {
    String initials(String s) {
      final parts = s.trim().split(RegExp(r'\s+'));
      if (parts.isEmpty) return '?';
      if (parts.length == 1) return parts[0][0].toUpperCase();
      return (parts[0][0] + parts.last[0]).toUpperCase();
    }

    final rt = _relativeTimeWithColor(t.lastActivity!.date);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Material(
        elevation: 3,
        borderRadius: BorderRadius.circular(18),
        shadowColor: Colors.black.withValues(alpha: 0.15),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _openFarmerBottomSheet(t),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 🔷 Header (Farmer Name)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: _primary,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(18),
                  ),
                ),
                child: Text(
                  t.farmerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),

              // 🔷 Body
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: _primary.withValues(alpha: 0.9),
                      child: Text(
                        initials(t.farmerName),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),

                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Phone
                          Row(
                            children: [
                              const Icon(
                                Icons.phone,
                                size: 15,
                                color: Color(0xFF50C6B4),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                t.mobileNumber,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 6),

                          // Address
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.location_on,
                                size: 15,
                                color: Color(0xFF50C6B4),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  t.address,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Colors.black54,
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 6),

                          // 🔥 SAME AS DEALER → Due + Last Visit
                          Row(
                            children: [
                              Expanded(
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.account_balance_wallet,
                                      size: 15,
                                      color: Color(0xFF50C6B4),
                                    ),
                                    const SizedBox(width: 6),
                                    t.pendingAmount > 0
                                        ? Text(
                                            'Due: ${_formatMoney(t.pendingAmount)}',
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.red,
                                            ),
                                          )
                                        : const Text(
                                            'No Due',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFF50C6B4),
                                            ),
                                          ),
                                  ],
                                ),
                              ),

                              if (t.lastActivity?.date != null)
                                Text(
                                  rt.text,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: rt.color,
                                    fontWeight: FontWeight.w600,
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
            ],
          ),
        ),
      ),
    );
  }

  void _openDealerBottomSheet(DealerClient t) {
    bool showVisitActivities = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        _visitFutureCache[t.id] ??= fetchDealerVisitActivities(t.id);

        return StatefulBuilder(
          builder: (context, setModalState) {
            return FutureBuilder<List<VisitActivity>>(
              future: _visitFutureCache[t.id],
              builder: (context, snap) {
                final activities = snap.data ?? [];
                final isLoading =
                    snap.connectionState == ConnectionState.waiting;
                final hasError = snap.hasError;

                return SafeArea(
                  child: SingleChildScrollView(
                    child: Container(
                      padding: const EdgeInsets.only(bottom: 16),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(20),
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // ---------------- HEADER ----------------
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 18,
                                ),
                                decoration: BoxDecoration(
                                  color: _primary,
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(20),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const SizedBox(width: 68),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            t.dealerName,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 18,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            _dateFormat.format(
                                              t.createdAt.toLocal(),
                                            ),
                                            style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Positioned(
                                left: 28,
                                bottom: -20,
                                child: CircleAvatar(
                                  radius: 28,
                                  backgroundColor: _primary,
                                  child: Text(
                                    t.dealerName.isNotEmpty
                                        ? t.dealerName[0].toUpperCase()
                                        : "?",
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 26,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 36),

                          // ---------------- BODY ----------------
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (t.mobileNumber.isNotEmpty) ...[
                                  const Text(
                                    "Phone Number",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(t.mobileNumber),
                                  const SizedBox(height: 14),
                                ],

                                if (t.shopName.isNotEmpty) ...[
                                  const Text(
                                    "Shop Name",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(t.shopName),
                                  const SizedBox(height: 14),
                                ],

                                const Text(
                                  "Address",
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 4),
                                Text(t.shopAddress),
                                const SizedBox(height: 14),

                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            "Pending Amount",
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            t.pendingAmount != 0
                                                ? _formatMoney(t.pendingAmount)
                                                : 'No Due',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              color: t.pendingAmount != 0
                                                  ? Colors.red
                                                  : Colors.green,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            "Delivered Orders",
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            _formatMoney(
                                              t.deliveredOrdersAmount,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 14),

                                // ---------------- VISIT ACTIVITIES ----------------
                                if (isLoading) ...[
                                  const SizedBox(height: 12),
                                  const Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                  const SizedBox(height: 12),
                                ] else if (hasError) ...[
                                  const Text(
                                    "Failed to load visit activities.",
                                    style: TextStyle(color: Colors.red),
                                  ),
                                  const SizedBox(height: 12),
                                ] else if (activities.isNotEmpty) ...[
                                  InkWell(
                                    onTap: () {
                                      setModalState(() {
                                        showVisitActivities =
                                            !showVisitActivities;
                                      });
                                    },
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            "Visit Activities (${activities.length})",
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        AnimatedRotation(
                                          turns: showVisitActivities
                                              ? 0.5
                                              : 0.0,
                                          duration: const Duration(
                                            milliseconds: 250,
                                          ),
                                          child: const Icon(
                                            Icons.keyboard_arrow_down,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  const SizedBox(height: 8),

                                  AnimatedSize(
                                    duration: const Duration(milliseconds: 300),
                                    curve: Curves.easeInOut,
                                    child: showVisitActivities
                                        ? SizedBox(
                                            height: 260,
                                            child: ListView.builder(
                                              physics:
                                                  const BouncingScrollPhysics(),
                                              itemCount: activities.length,
                                              itemBuilder: (context, index) {
                                                final act = activities[index];
                                                final dt = act.date?.toLocal();
                                                final isLast =
                                                    index ==
                                                    activities.length - 1;

                                                return Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        bottom: 12,
                                                      ),
                                                  child: Row(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      SizedBox(
                                                        width: 24,
                                                        child: Column(
                                                          children: [
                                                            Container(
                                                              width: 22,
                                                              height: 22,
                                                              decoration: BoxDecoration(
                                                                color: _primary
                                                                    .withValues(
                                                                      alpha:
                                                                          0.12,
                                                                    ),
                                                                shape: BoxShape
                                                                    .circle,
                                                              ),
                                                              child: Icon(
                                                                act.totalAmount !=
                                                                        null
                                                                    ? Icons
                                                                          .shopping_bag
                                                                    : Icons
                                                                          .location_on,
                                                                size: 14,
                                                                color: _primary,
                                                              ),
                                                            ),
                                                            if (!isLast)
                                                              Container(
                                                                width: 2,
                                                                height: 36,
                                                                margin:
                                                                    const EdgeInsets.only(
                                                                      top: 4,
                                                                    ),
                                                                color: Colors
                                                                    .grey
                                                                    .shade300,
                                                              ),
                                                          ],
                                                        ),
                                                      ),
                                                      Expanded(
                                                        child: Padding(
                                                          padding:
                                                              const EdgeInsets.only(
                                                                left: 8,
                                                              ),
                                                          child: Column(
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .start,
                                                            children: [
                                                              Column(
                                                                crossAxisAlignment:
                                                                    CrossAxisAlignment
                                                                        .start,
                                                                children: [
                                                                  Text(
                                                                    act.status ??
                                                                        'Visit',
                                                                    style: TextStyle(
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w600,
                                                                      color: statusColor(
                                                                        act.status,
                                                                      ),
                                                                    ),
                                                                  ),

                                                                  if (act.totalAmount !=
                                                                      null)
                                                                    Text(
                                                                      'Amount: ${_formatMoney(act.totalAmount!)}',
                                                                      style: const TextStyle(
                                                                        fontSize:
                                                                            12,
                                                                        color: Colors
                                                                            .green,
                                                                        fontWeight:
                                                                            FontWeight.w600,
                                                                      ),
                                                                    ),

                                                                  if (dt !=
                                                                      null)
                                                                    Text(
                                                                      DateFormat(
                                                                        'dd MMM yyyy, hh:mm a',
                                                                      ).format(
                                                                        dt,
                                                                      ),
                                                                      style: const TextStyle(
                                                                        fontSize:
                                                                            12,
                                                                        color: Colors
                                                                            .black54,
                                                                      ),
                                                                    ),
                                                                ],
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                              },
                                            ),
                                          )
                                        : const SizedBox.shrink(),
                                  ),
                                ] else ...[
                                  const Text(
                                    "No visit activities found",
                                    style: TextStyle(color: Colors.black54),
                                  ),
                                ],

                                const Divider(height: 24),

                                // ---------------- ACTIONS ----------------
                                _actionButtons(
                                  phone: t.mobileNumber,
                                  address: t.shopAddress,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  void _openFarmerBottomSheet(FarmerClient t) {
    final primary = _primary;
    bool showVisitActivities = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        // cache farmer visit API call
        _visitFutureCache[t.id] ??= fetchFarmerVisitActivities(t.id);

        return StatefulBuilder(
          builder: (context, setModalState) {
            return FutureBuilder<List<VisitActivity>>(
              future: _visitFutureCache[t.id],
              builder: (context, snap) {
                final activities = snap.data ?? [];

                final isLoading =
                    snap.connectionState == ConnectionState.waiting;
                final hasError = snap.hasError;

                return SafeArea(
                  child: SingleChildScrollView(
                    child: Container(
                      padding: const EdgeInsets.only(bottom: 16),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(20),
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // ---------------- HEADER ----------------
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 18,
                                ),
                                decoration: BoxDecoration(
                                  color: primary,
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(20),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const SizedBox(width: 68),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            t.farmerName,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 18,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            _dateFormat.format(
                                              t.createdAt.toLocal(),
                                            ),
                                            style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Positioned(
                                left: 28,
                                bottom: -20,
                                child: CircleAvatar(
                                  radius: 28,
                                  backgroundColor: primary,
                                  child: Text(
                                    t.farmerName.isNotEmpty
                                        ? t.farmerName[0].toUpperCase()
                                        : '?',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 26,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 36),

                          // ---------------- BODY ----------------
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (t.mobileNumber.isNotEmpty) ...[
                                  const Text(
                                    "Phone Number",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(t.mobileNumber),
                                  const SizedBox(height: 14),
                                ],

                                const Text(
                                  "Address",
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 4),
                                Text(t.address),
                                const SizedBox(height: 14),

                                if (t.totalCultureArea != null) ...[
                                  const Text(
                                    "Total Culture Area",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text('${t.totalCultureArea} Acres'),
                                  const SizedBox(height: 14),
                                ],

                                // ---------------- FINANCIAL SUMMARY (NEW) ----------------
                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            "Pending Amount",
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            t.pendingAmount != 0
                                                ? _formatMoney(t.pendingAmount)
                                                : 'No Due',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              color: t.pendingAmount != 0
                                                  ? Colors.red
                                                  : Colors.green,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            "Delivered Orders",
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            _formatMoney(
                                              t.deliveredOrdersAmount,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 14),

                                // ---------------- VISIT ACTIVITIES ----------------
                                if (isLoading) ...[
                                  const Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                  const SizedBox(height: 12),
                                ] else if (hasError) ...[
                                  const Text(
                                    "Failed to load visit activities.",
                                    style: TextStyle(color: Colors.red),
                                  ),
                                  const SizedBox(height: 12),
                                ] else if (activities.isNotEmpty) ...[
                                  InkWell(
                                    onTap: () {
                                      setModalState(() {
                                        showVisitActivities =
                                            !showVisitActivities;
                                      });
                                    },
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            "Visit Activities (${activities.length})",
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        AnimatedRotation(
                                          turns: showVisitActivities
                                              ? 0.5
                                              : 0.0,
                                          duration: const Duration(
                                            milliseconds: 250,
                                          ),
                                          child: const Icon(
                                            Icons.keyboard_arrow_down,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  const SizedBox(height: 8),
                                  AnimatedSize(
                                    duration: const Duration(milliseconds: 300),
                                    curve: Curves.easeInOut,
                                    child: showVisitActivities
                                        ? SizedBox(
                                            height: 260,
                                            child: ListView.builder(
                                              physics:
                                                  const BouncingScrollPhysics(),
                                              itemCount: activities.length,
                                              itemBuilder: (context, index) {
                                                final act = activities[index];
                                                final dt = act.date?.toLocal();
                                                final isLast =
                                                    index ==
                                                    activities.length - 1;

                                                return Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        bottom: 12,
                                                      ),
                                                  child: Row(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      SizedBox(
                                                        width: 24,
                                                        child: Column(
                                                          children: [
                                                            Container(
                                                              width: 22,
                                                              height: 22,
                                                              decoration: BoxDecoration(
                                                                color: _primary
                                                                    .withValues(
                                                                      alpha:
                                                                          0.12,
                                                                    ),
                                                                shape: BoxShape
                                                                    .circle,
                                                              ),
                                                              child: Icon(
                                                                act.totalAmount !=
                                                                        null
                                                                    ? Icons
                                                                          .shopping_bag
                                                                    : Icons
                                                                          .location_on,
                                                                size: 14,
                                                                color: _primary,
                                                              ),
                                                            ),
                                                            if (!isLast)
                                                              Container(
                                                                width: 2,
                                                                height: 36,
                                                                margin:
                                                                    const EdgeInsets.only(
                                                                      top: 4,
                                                                    ),
                                                                color: Colors
                                                                    .grey
                                                                    .shade300,
                                                              ),
                                                          ],
                                                        ),
                                                      ),
                                                      Expanded(
                                                        child: Padding(
                                                          padding:
                                                              const EdgeInsets.only(
                                                                left: 8,
                                                              ),
                                                          child: Column(
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .start,
                                                            children: [
                                                              Column(
                                                                crossAxisAlignment:
                                                                    CrossAxisAlignment
                                                                        .start,
                                                                children: [
                                                                  Text(
                                                                    act.status ??
                                                                        'Visit',
                                                                    style: TextStyle(
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w600,
                                                                      color: statusColor(
                                                                        act.status,
                                                                      ),
                                                                    ),
                                                                  ),

                                                                  if (act.totalAmount !=
                                                                      null)
                                                                    Text(
                                                                      'Amount: ${_formatMoney(act.totalAmount!)}',
                                                                      style: const TextStyle(
                                                                        fontSize:
                                                                            12,
                                                                        color: Colors
                                                                            .green,
                                                                        fontWeight:
                                                                            FontWeight.w600,
                                                                      ),
                                                                    ),

                                                                  if (dt !=
                                                                      null)
                                                                    Text(
                                                                      DateFormat(
                                                                        'dd MMM yyyy, hh:mm a',
                                                                      ).format(
                                                                        dt,
                                                                      ),
                                                                      style: const TextStyle(
                                                                        fontSize:
                                                                            12,
                                                                        color: Colors
                                                                            .black54,
                                                                      ),
                                                                    ),
                                                                ],
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                              },
                                            ),
                                          )
                                        : const SizedBox.shrink(),
                                  ),
                                ] else ...[
                                  const Text(
                                    "No visit activities found",
                                    style: TextStyle(color: Colors.black54),
                                  ),
                                  const SizedBox(height: 12),
                                ],

                                const Divider(height: 24),

                                // ---------------- ACTIONS ----------------
                                _actionButtons(
                                  phone: t.mobileNumber,
                                  address: t.address,
                                ),

                                const SizedBox(height: 18),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _actionButtons({required String phone, required String address}) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _primary,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () async {
                final Uri callUri = Uri(scheme: 'tel', path: phone);
                if (await canLaunchUrl(callUri)) {
                  await launchUrl(callUri);
                }
              },
              icon: const Icon(Icons.phone, size: 18, color: Colors.white),
              label: const Text(
                'Call',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: _primary),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () async {
                final Uri mapUri = Uri.parse(
                  'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(address)}',
                );
                if (await canLaunchUrl(mapUri)) {
                  await launchUrl(mapUri, mode: LaunchMode.externalApplication);
                }
              },
              icon: Icon(Icons.map, size: 18, color: _primary),
              label: Text(
                'Navigate',
                style: TextStyle(color: _primary, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// --- Models ---

class DealerClient {
  final String id;
  final String companyId;
  final dynamic employeeId;
  final String dealerName;
  final String shopName;
  final String mobileNumber;
  final String shopAddress;
  final String location;
  final String status;
  final String? dealerImage;
  final String? remarks;
  final String dealerId;
  final DateTime createdAt;
  final List<VisitActivity> visitActivities;

  // NEW
  final num pendingAmount;
  final num deliveredOrdersAmount;
  final LastActivity? lastActivity;

  DealerClient({
    required this.id,
    required this.companyId,
    required this.employeeId,
    required this.dealerName,
    required this.shopName,
    required this.mobileNumber,
    required this.shopAddress,
    required this.location,
    required this.status,
    required this.dealerImage,
    required this.remarks,
    required this.dealerId,
    required this.createdAt,
    // NEW
    required this.pendingAmount,
    required this.deliveredOrdersAmount,
    required this.lastActivity,
    required this.visitActivities,
  });

  factory DealerClient.fromJson(Map<String, dynamic> json) {
    // parse lastActivity safely
    LastActivity? parseLastActivity(Map<String, dynamic>? j) {
      if (j == null) return null;

      final dateStr = j['updatedAt'] ?? j['date'] ?? j['createdAt'];

      return LastActivity(
        type: (j['status'] ?? j['type'] ?? '').toString(),
        date: dateStr != null ? DateTime.tryParse(dateStr) : null,
      );
    }

    return DealerClient(
      id: json['_id'] ?? '',
      companyId: json['companyId'] ?? '',
      employeeId: json['employeeId'],
      dealerName: json['dealerName'] ?? json['shopName'] ?? '-',
      shopName: json['shopName'] ?? '-',
      mobileNumber: (json['mobileNumber'] ?? '').toString().trim(),
      shopAddress: json['shopAddress'] ?? '-',
      location: json['location'] ?? '-',
      status: (json['status'] ?? 'pending').toString(),
      dealerImage: json['dealerImage'],
      remarks: json['remarks'],
      dealerId: json['dealerId'] ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
      // NEW fields with safe fallbacks
      pendingAmount: json['pendingAmount'] ?? 0,
      deliveredOrdersAmount: json['deliveredOrdersAmount'] ?? 0,
      lastActivity: parseLastActivity(
        (json['lastActivity'] is Map)
            ? (json['lastActivity'] as Map).cast<String, dynamic>()
            : null,
      ),
      visitActivities:
          (json['visitActivities'] as List?)
              ?.map((e) => VisitActivity.fromJson(e))
              .toList() ??
          [],
    );
  }
}

// NEW helper class for lastActivity
class LastActivity {
  final String type;
  final DateTime? date;
  LastActivity({required this.type, required this.date});
}

class FarmerClient {
  final String id;
  final String companyId;
  final dynamic employeeId;
  final String farmerName;
  final String mobileNumber;
  final String address;
  final String location;
  final num? totalCultureArea;
  final String status;
  final String? remarks;
  final String farmerId;
  final DateTime createdAt;
  final List<VisitActivity> visitActivities;

  // ✅ NEW (MATCH DEALER)
  final num pendingAmount;
  final num deliveredOrdersAmount;
  final LastActivity? lastActivity;

  FarmerClient({
    required this.id,
    required this.companyId,
    required this.employeeId,
    required this.farmerName,
    required this.mobileNumber,
    required this.address,
    required this.location,
    required this.totalCultureArea,
    required this.status,
    required this.remarks,
    required this.farmerId,
    required this.createdAt,
    required this.visitActivities,

    // ✅ NEW
    required this.pendingAmount,
    required this.deliveredOrdersAmount,
    required this.lastActivity,
  });

  factory FarmerClient.fromJson(Map<String, dynamic> json) {
    LastActivity? parseLastActivity(Map<String, dynamic>? j) {
      if (j == null) return null;

      final dateStr = j['date'] ?? j['updatedAt'] ?? j['createdAt'];

      return LastActivity(
        type: (j['type'] ?? j['status'] ?? '').toString(),
        date: dateStr != null ? DateTime.tryParse(dateStr) : null,
      );
    }

    return FarmerClient(
      id: json['_id'] ?? '',
      companyId: json['companyId'] ?? '',
      employeeId: json['employeeId'],
      farmerName: json['name'] ?? '-',
      mobileNumber: (json['mobileNumber'] ?? '').toString().trim(),
      address: json['address'] ?? '-',
      location: json['location'] ?? '-',
      totalCultureArea: json['totalCultureArea'],
      status: (json['status'] ?? 'pending').toString(),
      remarks: json['remarks'],
      farmerId: json['farmerId'] ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),

      visitActivities:
          (json['visitActivities'] as List?)
              ?.map((e) => VisitActivity.fromJson(e))
              .toList() ??
          [],

      // ✅ NEW
      pendingAmount: json['pendingAmount'] ?? 0,
      deliveredOrdersAmount: json['deliveredOrdersAmount'] ?? 0,
      lastActivity: parseLastActivity(
        (json['lastActivity'] is Map)
            ? (json['lastActivity'] as Map).cast<String, dynamic>()
            : null,
      ),
    );
  }
}

// Model for visit activity
class VisitActivity {
  final String id;
  final String? tripId;
  final String? status;
  final String? type;
  final DateTime? date;
  final num? totalAmount; // ✅ ADD THIS

  VisitActivity({
    required this.id,
    this.tripId,
    this.status,
    this.type,
    this.date,
    this.totalAmount,
  });

  factory VisitActivity.fromJson(Map<String, dynamic> json) {
    final dateStr = json['updatedAt'] ?? json['date'] ?? json['createdAt'];

    return VisitActivity(
      id: json['_id'] ?? '',
      tripId: json['tripId']?.toString(),
      status: json['status']?.toString(),
      type: json['type']?.toString(),
      date: dateStr != null ? DateTime.tryParse(dateStr) : null,
      totalAmount: json['totalAmount'], // ✅ ADD THIS
    );
  }
}

class RelativeTimeResult {
  final String text;
  final Color color;

  RelativeTimeResult(this.text, this.color);
}

RelativeTimeResult _relativeTimeWithColor(DateTime? dt) {
  if (dt == null) return RelativeTimeResult('Unknown', Colors.grey);

  final now = DateTime.now();
  final diff = now.difference(dt.toLocal());

  // 🔴 > 15 days → RED
  if (diff.inDays > 15) {
    return RelativeTimeResult('${diff.inDays} days ago', Colors.red);
  }

  // 🟡 7–15 days → ORANGE (optional but recommended)
  if (diff.inDays > 7) {
    return RelativeTimeResult('${diff.inDays} days ago', Colors.orange);
  }

  // 🟢 recent → GREEN
  if (diff.inDays > 0) {
    return RelativeTimeResult('${diff.inDays} days ago', Colors.green);
  }

  if (diff.inHours > 0) {
    return RelativeTimeResult('${diff.inHours} hours ago', Colors.green);
  }

  return RelativeTimeResult('Just now', Colors.green);
}
