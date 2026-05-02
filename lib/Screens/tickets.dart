// tickets.dart
// Flutter page showing Dealer and Farmer tickets in two tabs.
// Requires packages: http, shared_preferences, intl
// Optional: url_launcher for phone call functionality.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:FieldService_app/Screens/main_page.dart';
import 'package:FieldService_app/config.dart';
import 'package:FieldService_app/services/secure_storage_service.dart';
import 'package:FieldService_app/widgets/shared_bottom_nav.dart';
import 'package:url_launcher/url_launcher.dart';

class TicketsPage extends StatefulWidget {
  final bool condition;
  const TicketsPage({super.key, required this.condition});

  @override
  State<TicketsPage> createState() => _TicketsPageState();
}

class _TicketsPageState extends State<TicketsPage>
    with TickerProviderStateMixin {
  late TabController _tabController;

  bool _loading = true;
  String? _error;

  List<DealerTicket> _dealerTickets = [];
  List<FarmerTicket> _farmerTickets = [];

  final String _dealerSearch = '';
  final String _farmerSearch = '';

  final DateFormat _dateFormat = DateFormat.yMMMd().add_jm();

  // Status filters
  static const String sAll = 'All';
  static const String sSolved = 'Solved';
  static const String sPending = 'Pending';
  static const String sInProgress = 'InProgress';

  // selected status filter
  String _selectedStatus = sAll;

  // small color constant used by chips (Trips-style)
  final Color appGreen = const Color(0xFF2E7D32);

  Color _warnColor(bool warn) =>
      warn ? Colors.red.shade600 : Colors.green.shade600;

  bool _warnRange(num? v, num min, num max) {
    if (v == null) return false;
    return v < min || v > max;
  }

  Widget _warnChip(String label, bool warn) {
    final c = _warnColor(warn);
    return Chip(
      label: Text(
        label,
        style: TextStyle(color: c, fontWeight: FontWeight.w600),
      ),
      backgroundColor: c.withValues(alpha: 0.12),
      side: BorderSide(color: c.withValues(alpha: 0.5)),
    );
  }

  final Set<int> _expandedPonds = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() => setState(() {}));
    _loadTickets();
  }

  Future<void> _loadTickets() async {
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
      final dealers = await fetchDealerTickets(userId);
      final farmers = await fetchFarmerTickets(userId);

      setState(() {
        _dealerTickets = dealers;
        _farmerTickets = farmers;
        _loading = false;
      });
    } catch (e) {
      debugPrint('⚠️ Error fetching tickets: $e');

      // Fallback to cached data
      final dealerCache = prefs.getString('dealerTicketsCache');
      final farmerCache = prefs.getString('farmerTicketsCache');

      if (dealerCache != null || farmerCache != null) {
        setState(() {
          _dealerTickets = dealerCache != null
              ? (json.decode(dealerCache) as List)
                    .map((e) => DealerTicket.fromJson(e))
                    .toList()
              : [];
          _farmerTickets = farmerCache != null
              ? (json.decode(farmerCache) as List)
                    .map((e) => FarmerTicket.fromJson(e))
                    .toList()
              : [];
          _error = 'Offline mode: showing last saved data.';
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'Failed to load tickets';
          _dealerTickets = [];
          _farmerTickets = [];

          _loading = false;
        });
      }
    }
  }

  Future<List<DealerTicket>> fetchDealerTickets(String employeeId) async {
    final baseurl = AppConfig.apiBase;
    final uri = Uri.parse('$baseurl/api/dealertickets/employee/$employeeId');
    final headers = await _buildHeaders();
    final prefs = await SharedPreferences.getInstance();

    try {
      final res = await http.get(uri, headers: headers);
      debugPrint('GET $uri -> ${res.statusCode}');

      if (res.statusCode == 200) {
        final List jsonList = json.decode(res.body) as List;
        await prefs.setString(
          'dealerTicketsCache',
          json.encode(jsonList),
        ); // ✅ cache
        return jsonList.map((e) => DealerTicket.fromJson(e)).toList();
      } else if (res.statusCode == 404) {
        await prefs.remove('dealerTicketsCache');
        return [];
      } else {
        throw Exception('Failed to load dealer tickets (${res.statusCode})');
      }
    } catch (e) {
      debugPrint('⚠️ Dealer API failed, using cache: $e');
      final cached = prefs.getString('dealerTicketsCache');
      if (cached != null) {
        final List jsonList = json.decode(cached) as List;
        return jsonList.map((e) => DealerTicket.fromJson(e)).toList();
      }
      rethrow;
    }
  }

  // Build request headers including optional Bearer token from SharedPreferences
  Future<Map<String, String>> _buildHeaders() async {
    // final prefs = await SharedPreferences.getInstance();
    // final token = prefs.getString('token');
    final token = await SecureStorageService.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  Future<List<FarmerTicket>> fetchFarmerTickets(String employeeId) async {
    final baseurl = AppConfig.apiBase;
    final uri = Uri.parse('$baseurl/api/farmertickets/employee/$employeeId');
    final headers = await _buildHeaders();
    final prefs = await SharedPreferences.getInstance();

    try {
      final res = await http.get(uri, headers: headers);
      debugPrint('GET $uri -> ${res.statusCode}');

      if (res.statusCode == 200) {
        final List jsonList = json.decode(res.body) as List;
        await prefs.setString(
          'farmerTicketsCache',
          json.encode(jsonList),
        ); // ✅ cache
        return jsonList.map((e) => FarmerTicket.fromJson(e)).toList();
      } else if (res.statusCode == 404) {
        await prefs.remove('farmerTicketsCache');
        return [];
      } else {
        throw Exception('Failed to load farmer tickets (${res.statusCode})');
      }
    } catch (e) {
      debugPrint('⚠️ Farmer API failed, using cache: $e');
      final cached = prefs.getString('farmerTicketsCache');
      if (cached != null) {
        final List jsonList = json.decode(cached) as List;
        return jsonList.map((e) => FarmerTicket.fromJson(e)).toList();
      }
      rethrow;
    }
  }

  List<DealerTicket> get _filteredDealers {
    List<DealerTicket> list;
    if (_dealerSearch.trim().isEmpty) {
      list = List.from(_dealerTickets);
    } else {
      final q = _dealerSearch.toLowerCase();
      list = _dealerTickets.where((t) {
        return t.dealerName.toLowerCase().contains(q) ||
            t.mobileNumber.contains(q) ||
            t.dealerLocation.toLowerCase().contains(q);
      }).toList();
    }

    // Apply status filter (case-insensitive)
    if (_selectedStatus != sAll) {
      list = list.where((t) {
        return t.status.toString().toLowerCase() ==
            _selectedStatus.toLowerCase();
      }).toList();
    }

    // Sort ascending by createdAt (oldest first)
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return list;
  }

  List<FarmerTicket> get _filteredFarmers {
    List<FarmerTicket> list;
    if (_farmerSearch.trim().isEmpty) {
      list = List.from(_farmerTickets);
    } else {
      final q = _farmerSearch.toLowerCase();
      list = _farmerTickets.where((t) {
        return t.farmerName.toLowerCase().contains(q) ||
            t.mobileNumber.contains(q) ||
            t.location.toLowerCase().contains(q);
      }).toList();
    }

    if (_selectedStatus != sAll) {
      list = list.where((t) {
        return t.status.toString().toLowerCase() ==
            _selectedStatus.toLowerCase();
      }).toList();
    }

    // Sort ascending by createdAt (oldest first)
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return list;
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !widget.condition,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;

        if (widget.condition) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  const MainPage(initialMenu: MenuState.homedashboard),
            ),
            (route) => false,
          );
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: const Text(
            'Queries',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),
          centerTitle: true,
          backgroundColor: const Color(0xFF1AB69C),
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_sharp, color: Colors.white),
            onPressed: () {
              if (widget.condition) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const MainPage(initialMenu: MenuState.homedashboard),
                  ),
                  (route) => false,
                );
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
                unselectedLabelColor: Colors.white,
                indicatorWeight: 3,
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Colors.white,
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
            : NestedScrollView(
                headerSliverBuilder: (context, innerBoxIsScrolled) {
                  return [
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _StickyFiltersHeader(
                        child: _buildStatusFiltersRow(),
                      ),
                    ),
                  ];
                },
                body: TabBarView(
                  controller: _tabController,
                  children: [
                    Container(
                      color: const Color(0xFF10B981).withValues(alpha: 0.02),
                      child: _dealerListView(),
                    ),
                    Container(
                      color: Colors.green.withValues(alpha: 0.02),
                      child: _farmerListView(),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildStatusFiltersRow() {
    final filters = [sAll, sSolved, sPending, sInProgress];
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: filters.map((filter) {
            final isSelected = _selectedStatus == filter;
            return Container(
              margin: const EdgeInsets.only(right: 12),
              child: GestureDetector(
                onTap: () => _onStatusTap(filter),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFF2EB9AC) : Colors.white,
                    borderRadius: BorderRadius.circular(25),
                    border: Border.all(
                      color: isSelected ? appGreen : Colors.grey[300]!,
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    filter,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white : Colors.grey[700],
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

  void _onStatusTap(String status) {
    if (_selectedStatus == status) return;
    setState(() {
      _selectedStatus = status;
    });
  }

  Widget _dealerListView() {
    final dealers = _filteredDealers;
    return RefreshIndicator(
      onRefresh: _loadTickets,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const SizedBox(height: 12),
          if (dealers.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 180),
              child: Center(child: Text('No dealer tickets found')),
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
      onRefresh: _loadTickets,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const SizedBox(height: 12),
          if (farmers.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 180),
              child: Center(child: Text('No farmer tickets found')),
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
            ElevatedButton(onPressed: _loadTickets, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  Widget _dealerCard(DealerTicket t) {
    String initials(String s) {
      final parts = s.trim().split(RegExp(r'\s+'));
      if (parts.isEmpty) return '?';
      if (parts.length == 1) return parts[0][0].toUpperCase();
      return (parts[0][0] + parts.last[0]).toUpperCase();
    }

    const primary = Color(0xFF1AB69C);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(18),
        shadowColor: primary.withValues(alpha: 0.20),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _openDealerBottomSheet(t),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ▌ Top strip (Name + Status)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                decoration: const BoxDecoration(
                  color: primary,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(18),
                    topRight: Radius.circular(18),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      t.dealerName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),

                    // ► Status moved here
                    statusBadge(t.status),
                  ],
                ),
              ),

              // ▌ White body
              Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(18),
                    bottomRight: Radius.circular(18),
                  ),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: primary,
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
                          /// Name removed here (since it's in the strip)
                          Text(
                            _dateFormat.format(t.createdAt.toLocal()),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            t.dealerLocation,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.black87,
                              height: 1.3,
                            ),
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

  Widget statusBadge(String status) {
    Color bg;
    if (status == "Solved") {
      bg = Colors.green.shade600;
    } else if (status == "InProgress") {
      bg = Colors.blue.shade600;
    } else {
      bg = Colors.orange.shade600;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        status,
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }

  Widget statusChip(String status) {
    Color c;
    switch (status) {
      case "Solved":
        c = Colors.green;
        break;
      case "InProgress":
        c = Colors.blue;
        break;
      default:
        c = Colors.orange;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(50),
      ),
      child: Text(
        status,
        style: TextStyle(color: c, fontWeight: FontWeight.bold, fontSize: 12),
      ),
    );
  }

  void _openDealerBottomSheet(DealerTicket t) {
    final primary = const Color(0xFF1AB69C);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Container(
            padding: const EdgeInsets.only(bottom: 16),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),

            // NO SCROLL
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // HEADER WITH AVATAR
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
                          const SizedBox(width: 68), // space for avatar
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
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
                                  _dateFormat.format(t.createdAt.toLocal()),
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          statusBadge(t.status),
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

                // BODY CONTENT
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // PHONE
                      if (t.mobileNumber.isNotEmpty) ...[
                        const Text(
                          "Phone Number",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(t.mobileNumber),
                        const SizedBox(height: 14),
                      ],

                      // LOCATION
                      const Text(
                        "Location",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(t.dealerLocation),
                      const SizedBox(height: 14),

                      // REMARKS
                      if ((t.remarks ?? '').isNotEmpty) ...[
                        const Text(
                          "Remarks",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(t.remarks!),
                        const SizedBox(height: 14),
                      ],

                      // SOLUTION
                      if ((t.solution ?? '').isNotEmpty) ...[
                        const Text(
                          "Solution",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(t.solution!),
                        const SizedBox(height: 14),
                      ],

                      const Divider(height: 24),

                      // ACTION BUTTONS
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: primary,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: () async {
                                final Uri callUri = Uri(
                                  scheme: 'tel',
                                  path: t.mobileNumber,
                                );
                                if (await canLaunchUrl(callUri)) {
                                  await launchUrl(callUri);
                                }
                              },
                              icon: const Icon(
                                Icons.phone,
                                color: Colors.white,
                              ),
                              label: const Text(
                                'Call',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: primary),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: () async {
                                final Uri mapUri = Uri.parse(
                                  'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(t.dealerLocation)}',
                                );
                                if (await canLaunchUrl(mapUri)) {
                                  await launchUrl(
                                    mapUri,
                                    mode: LaunchMode.externalApplication,
                                  );
                                }
                              },
                              icon: Icon(Icons.map, color: primary),
                              label: Text(
                                'Navigate',
                                style: TextStyle(color: primary),
                              ),
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
      },
    );
  }

  Widget _farmerCard(FarmerTicket t) {
    String initials(String s) {
      final parts = s.trim().split(RegExp(r'\s+'));
      if (parts.isEmpty) return '?';
      if (parts.length == 1) return parts[0][0].toUpperCase();
      return (parts[0][0] + parts.last[0]).toUpperCase();
    }

    const primary = Color(0xFF1AB69C); // use your green

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),

      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(18),
        shadowColor: primary.withValues(alpha: 0.20),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _openFarmerBottomSheet(t),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Top green strip (name + status)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: const BoxDecoration(
                  color: primary,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(18),
                    topRight: Radius.circular(18),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Name in the strip
                    Expanded(
                      child: Text(
                        t.farmerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),

                    // Status moved here (align right)
                    statusBadge(t.status),
                  ],
                ),
              ),

              // White body
              Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(18),
                    bottomRight: Radius.circular(18),
                  ),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Avatar
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: primary,
                      child: Text(
                        initials(t.farmerName),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),

                    const SizedBox(width: 14),

                    // Details
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // date row
                          Text(
                            _dateFormat.format(t.createdAt.toLocal()),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                          const SizedBox(height: 8),

                          // location
                          Text(
                            t.location,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13.5,
                              color: Colors.black87,
                              height: 1.3,
                            ),
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

  void _openFarmerBottomSheet(FarmerTicket t) {
    final primary = const Color(0xFF1AB69C);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Container(
                padding: const EdgeInsets.only(bottom: 16),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: DraggableScrollableSheet(
                  expand: false,
                  initialChildSize: 0.75,
                  minChildSize: 0.55,
                  maxChildSize: 0.9,
                  builder: (_, controller) {
                    return SingleChildScrollView(
                      controller: controller,
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
                                    const SizedBox(
                                      width: 68,
                                    ), // space for avatar
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
                                    statusBadge(t.status),
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
                                // PHONE
                                if (t.mobileNumber.isNotEmpty) ...[
                                  const Text(
                                    "Phone Number",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(t.mobileNumber),
                                  const SizedBox(height: 14),
                                ],

                                // LOCATION
                                const Text(
                                  "Location",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(t.location),
                                const SizedBox(height: 14),

                                // If server returned ponds[], render each pond's details
                                if (t.ponds != null && t.ponds!.isNotEmpty) ...[
                                  const Text(
                                    "Ponds",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  // For each pond show its details
                                  // Replace .map((pond) { ... }).toList() with asMap().entries.map(...)
                                  ...t.ponds!.asMap().entries.map((entry) {
                                    final idx = entry.key;
                                    final pond = entry.value;
                                    final expanded = _expandedPonds.contains(
                                      idx,
                                    );

                                    return GestureDetector(
                                      onTap: () {
                                        // Use setSheetState (you already wrapped sheet with StatefulBuilder)
                                        setSheetState(() {
                                          if (expanded) {
                                            _expandedPonds.remove(idx);
                                          } else {
                                            _expandedPonds.add(idx);
                                          }
                                        });
                                      },
                                      child: Container(
                                        margin: const EdgeInsets.only(
                                          bottom: 12,
                                        ),
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.withValues(
                                            alpha: 0.04,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          border: Border.all(
                                            color: Colors.grey.withValues(
                                              alpha: 0.12,
                                            ),
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            // HEADER (always visible)
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Text(
                                                  pond.pondName ?? 'Pond',
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),

                                                // Rotating arrow — smooth implicit animation
                                                AnimatedRotation(
                                                  turns: expanded
                                                      ? 0.5
                                                      : 0.0, // 0.5 = 180°
                                                  duration: const Duration(
                                                    milliseconds: 300,
                                                  ),
                                                  curve: Curves.easeInOut,
                                                  child: const Icon(
                                                    Icons.keyboard_arrow_down,
                                                  ),
                                                ),
                                              ],
                                            ),

                                            const SizedBox(height: 6),

                                            // Short summary always visible
                                            Text(
                                              'Area: ${pond.culturedArea ?? '-'} acres • ${pond.culturedSpecies ?? '-'}',
                                            ),

                                            const SizedBox(height: 8),

                                            // DETAILS — animate show/hide using cross-fade (smooth height + fade)
                                            AnimatedCrossFade(
                                              firstChild:
                                                  const SizedBox.shrink(),
                                              secondChild: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  // Physical readings
                                                  if (pond.physicalReadings !=
                                                          null &&
                                                      pond
                                                          .physicalReadings!
                                                          .isNotEmpty) ...[
                                                    const Text(
                                                      "Physical Readings",
                                                      style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 6),
                                                    ...pond.physicalReadings!.map((
                                                      pr,
                                                    ) {
                                                      final isFish =
                                                          (pond.culturedSpecies ??
                                                                  '')
                                                              .toLowerCase()
                                                              .trim() ==
                                                          'fish';
                                                      return Padding(
                                                        padding:
                                                            const EdgeInsets.only(
                                                              bottom: 6,
                                                            ),
                                                        child: Wrap(
                                                          spacing: 10,
                                                          runSpacing: 6,
                                                          children: [
                                                            _warnChip(
                                                              "Stocking PL: ${pr.stockingPL ?? '-'}",
                                                              false,
                                                            ),
                                                            _warnChip(
                                                              "DOC: ${pr.doc ?? '-'}",
                                                              _warnRange(
                                                                pr.doc,
                                                                1,
                                                                150,
                                                              ),
                                                            ),
                                                            _warnChip(
                                                              "Feed/day: ${pr.feedIntakePerDay ?? '-'}",
                                                              _warnRange(
                                                                pr.feedIntakePerDay,
                                                                0,
                                                                100,
                                                              ),
                                                            ),
                                                            _warnChip(
                                                              "Count: ${pr.count ?? '-'}",
                                                              false,
                                                            ),
                                                            if (isFish)
                                                              _warnChip(
                                                                "Avg Wt (g): ${pr.avgWeight ?? '-'}",
                                                                _warnRange(
                                                                  pr.avgWeight,
                                                                  1,
                                                                  200,
                                                                ),
                                                              ),
                                                          ],
                                                        ),
                                                      );
                                                    }),
                                                    const SizedBox(height: 8),
                                                  ],

                                                  // Chemical readings
                                                  if (pond.chemicalReadings !=
                                                          null &&
                                                      pond
                                                          .chemicalReadings!
                                                          .isNotEmpty) ...[
                                                    const Text(
                                                      "Chemical Readings",
                                                      style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 6),
                                                    ...pond.chemicalReadings!.map((
                                                      cr,
                                                    ) {
                                                      return Padding(
                                                        padding:
                                                            const EdgeInsets.only(
                                                              bottom: 6,
                                                            ),
                                                        child: Wrap(
                                                          spacing: 8,
                                                          runSpacing: 6,
                                                          children: [
                                                            if (cr.salinity !=
                                                                null)
                                                              _warnChip(
                                                                "Salinity: ${cr.salinity} ppt",
                                                                _warnRange(
                                                                  cr.salinity,
                                                                  0,
                                                                  40,
                                                                ),
                                                              ),
                                                            if (cr.ph != null)
                                                              _warnChip(
                                                                "pH: ${cr.ph}",
                                                                _warnRange(
                                                                  cr.ph,
                                                                  6.5,
                                                                  8.5,
                                                                ),
                                                              ),
                                                            if (cr.alkalinity !=
                                                                null)
                                                              _warnChip(
                                                                "Alk: ${cr.alkalinity}",
                                                                _warnRange(
                                                                  cr.alkalinity,
                                                                  80,
                                                                  200,
                                                                ),
                                                              ),
                                                            if (cr.ammonia !=
                                                                null)
                                                              _warnChip(
                                                                "NH3: ${cr.ammonia} mg/L",
                                                                _warnRange(
                                                                  cr.ammonia,
                                                                  0,
                                                                  0.5,
                                                                ),
                                                              ),
                                                            if (cr.nitrite !=
                                                                null)
                                                              _warnChip(
                                                                "NO2: ${cr.nitrite} mg/L",
                                                                _warnRange(
                                                                  cr.nitrite,
                                                                  0,
                                                                  1,
                                                                ),
                                                              ),
                                                            if (cr.dissolvedOxygen !=
                                                                null)
                                                              _warnChip(
                                                                "DO: ${cr.dissolvedOxygen} mg/L",
                                                                _warnRange(
                                                                  cr.dissolvedOxygen,
                                                                  4,
                                                                  20,
                                                                ),
                                                              ),
                                                          ],
                                                        ),
                                                      );
                                                    }),
                                                    const SizedBox(height: 8),
                                                  ],

                                                  // Disease readings
                                                  if (pond.diseaseReadings !=
                                                          null &&
                                                      pond
                                                          .diseaseReadings!
                                                          .isNotEmpty) ...[
                                                    const Text(
                                                      "Disease Readings",
                                                      style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 6),
                                                    ...pond.diseaseReadings!.map((
                                                      dr,
                                                    ) {
                                                      final vib = dr.vibrios;
                                                      String vibText;
                                                      if (vib == null) {
                                                        vibText = '-';
                                                      } else if (vib is num) {
                                                        vibText =
                                                            '${vib.toInt()} CFU/ml';
                                                      } else {
                                                        vibText = vib
                                                            .toString();
                                                      }
                                                      return Padding(
                                                        padding:
                                                            const EdgeInsets.only(
                                                              bottom: 6,
                                                            ),
                                                        child: Wrap(
                                                          spacing: 8,
                                                          children: [
                                                            _warnChip(
                                                              "Vibrios: $vibText",
                                                              vib is num &&
                                                                  vib > 1000000,
                                                            ),
                                                          ],
                                                        ),
                                                      );
                                                    }),
                                                    const SizedBox(height: 6),
                                                  ],
                                                ],
                                              ),
                                              crossFadeState: expanded
                                                  ? CrossFadeState.showSecond
                                                  : CrossFadeState.showFirst,
                                              duration: const Duration(
                                                milliseconds: 300,
                                              ),
                                              firstCurve: Curves.easeInOut,
                                              secondCurve: Curves.easeInOut,
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  }),

                                  const SizedBox(height: 14),
                                ],

                                // If no ponds array but older fields exist, keep previous UI
                                if ((t.ponds == null || t.ponds!.isEmpty) &&
                                    (t.pondName ?? '').isNotEmpty) ...[
                                  const Text(
                                    "Pond Details",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    "Name: ${t.pondName} | Size: ${t.pondSize ?? '-'} Acres",
                                  ),
                                  const SizedBox(height: 14),
                                ],

                                // WATER PARAMETERS (legacy single pondParameters)
                                if (t.pondParameters != null) ...[
                                  const Text(
                                    "Water Parameters",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 8,
                                    children: [
                                      Chip(
                                        label: Text(
                                          "pH: ${t.pondParameters!.pH}",
                                        ),
                                      ),
                                      Chip(
                                        label: Text(
                                          "NH3: ${t.pondParameters!.ammonia}",
                                        ),
                                      ),
                                      Chip(
                                        label: Text(
                                          "NO2: ${t.pondParameters!.nitrite}",
                                        ),
                                      ),
                                      if (t.pondParameters!.alkalinity != null)
                                        Chip(
                                          label: Text(
                                            "Alk: ${t.pondParameters!.alkalinity}",
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 14),
                                ],

                                // REMARKS
                                if ((t.remarks ?? '').isNotEmpty) ...[
                                  const Text(
                                    "Remarks",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(t.remarks ?? "-"),
                                  const SizedBox(height: 14),
                                ],

                                // SOLUTION
                                if ((t.solution ?? '').isNotEmpty) ...[
                                  const Text(
                                    "Solution",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(t.solution!),
                                  const SizedBox(height: 14),
                                ],

                                // ✅ MULTIPLE IMAGES
                                if (t.images != null &&
                                    t.images!.isNotEmpty) ...[
                                  const Text(
                                    "Images",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 8),

                                  SizedBox(
                                    height: 110,
                                    child: ListView.separated(
                                      scrollDirection: Axis.horizontal,
                                      itemCount: t.images!.length,
                                      separatorBuilder: (_, _) =>
                                          const SizedBox(width: 10),
                                      itemBuilder: (context, index) {
                                        final img = t.images![index];

                                        return ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          child: Image.network(
                                            '${AppConfig.apiBase}$img',
                                            width: 110,
                                            height: 110,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, _, _) =>
                                                const Icon(Icons.broken_image),
                                          ),
                                        );
                                      },
                                    ),
                                  ),

                                  const SizedBox(height: 14),
                                ],

                                const Divider(height: 24),

                                // ACTION BUTTONS
                                Row(
                                  children: [
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: primary,
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 14,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                        ),
                                        onPressed: () async {
                                          final Uri callUri = Uri(
                                            scheme: 'tel',
                                            path: t.mobileNumber,
                                          );
                                          if (await canLaunchUrl(callUri)) {
                                            await launchUrl(callUri);
                                          }
                                        },
                                        icon: const Icon(
                                          Icons.phone,
                                          color: Colors.white,
                                        ),
                                        label: const Text(
                                          "Call",
                                          style: TextStyle(color: Colors.white),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        style: OutlinedButton.styleFrom(
                                          side: BorderSide(color: primary),
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 14,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                        ),
                                        onPressed: () async {
                                          final Uri mapUri = Uri.parse(
                                            "https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(t.location)}",
                                          );
                                          if (await canLaunchUrl(mapUri)) {
                                            await launchUrl(
                                              mapUri,
                                              mode: LaunchMode
                                                  .externalApplication,
                                            );
                                          }
                                        },
                                        icon: Icon(Icons.map, color: primary),
                                        label: Text(
                                          "Navigate",
                                          style: TextStyle(color: primary),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 18),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _StickyFiltersHeader extends SliverPersistentHeaderDelegate {
  final Widget child;

  _StickyFiltersHeader({required this.child});

  @override
  double get minExtent => 64;

  @override
  double get maxExtent => 64;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Material(
      color: Colors.white,
      elevation: overlapsContent ? 4 : 0,
      child: child,
    );
  }

  @override
  bool shouldRebuild(covariant _StickyFiltersHeader oldDelegate) => true;
}

// --- Models ---

class DealerTicket {
  final String id;
  final String companyId;
  final String dealerId;
  final String employeeId;
  final String tripId;
  final String dealerName;
  final String mobileNumber;
  final String dealerLocation;
  final String? remarks;
  final String status; // NEW
  final String? solution; // NEW
  final DateTime createdAt;

  DealerTicket({
    required this.id,
    required this.companyId,
    required this.dealerId,
    required this.employeeId,
    required this.tripId,
    required this.dealerName,
    required this.mobileNumber,
    required this.dealerLocation,
    required this.remarks,
    required this.status,
    required this.solution,
    required this.createdAt,
  });

  factory DealerTicket.fromJson(Map<String, dynamic> json) {
    return DealerTicket(
      id: json['_id'] ?? '',
      companyId: json['companyId'] ?? '',
      dealerId: json['dealerId'] ?? '',
      employeeId: json['employeeId'] ?? '',
      tripId: json['tripId'] ?? '',
      dealerName: json['dealerName'] ?? '-',
      mobileNumber: json['mobileNumber'] ?? '-',
      dealerLocation: json['dealerLocation'] ?? '-',
      remarks: json['remarks'],
      status: json['status'] ?? 'Pending',
      solution: json['solution'], // may be null
      createdAt: DateTime.parse(json['createdAt']),
    );
  }
}

class FarmerTicket {
  final List<Pond>? ponds; // NEW: list of ponds (if backend provides)
  final PondParameters? pondParameters; // legacy single pondParameters
  final String id;
  final String companyId;
  final String tripId;
  final String employeeId;
  final String farmerId;
  final String farmerName;
  final String mobileNumber;
  final String location;
  final String? pondName; // legacy single
  final String? pondSize; // legacy single
  final String? species; // legacy single
  final bool? vibriosis; // legacy boolean (may be null)
  final String? remarks;
  final String status;
  final String? solution;
  final List<String>? images; // ✅ NEW (multiple images)
  final DateTime createdAt;

  FarmerTicket({
    required this.ponds,
    required this.pondParameters,
    required this.id,
    required this.companyId,
    required this.tripId,
    required this.employeeId,
    required this.farmerId,
    required this.farmerName,
    required this.mobileNumber,
    required this.location,
    required this.pondName,
    required this.pondSize,
    required this.species,
    required this.vibriosis,
    required this.remarks,
    required this.status,
    required this.solution,
    this.images,
    required this.createdAt,
  });

  factory FarmerTicket.fromJson(Map<String, dynamic> json) {
    // parse ponds[] if present
    List<Pond>? ponds;
    try {
      if (json['ponds'] != null && json['ponds'] is List) {
        ponds = (json['ponds'] as List)
            .map((p) => Pond.fromJson(p as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint('⚠️ Error parsing ponds: $e');
      ponds = null;
    }

    return FarmerTicket(
      ponds: ponds,
      pondParameters: json['pondParameters'] != null
          ? PondParameters.fromJson(json['pondParameters'])
          : null,
      id: json['_id'] ?? '',
      companyId: json['companyId'] ?? '',
      tripId: json['tripId'] ?? '',
      employeeId: json['employeeId'] ?? '',
      farmerId: json['farmerId'] ?? '',
      farmerName: json['farmerName'] ?? '-',
      mobileNumber: json['mobileNumber'] ?? '-',
      location: json['address'] ?? '-',
      pondName: json['pondName'],
      pondSize: json['pondSize'],
      species: json['species'],
      vibriosis: json['vibriosis'],
      remarks: json['remarks'],
      status: json['status'] ?? 'Pending',
      solution: json['solution'],
      images: (json['images'] as List?)?.map((e) => e.toString()).toList(),
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
    );
  }
}

class Pond {
  final String? pondName;
  final num? culturedArea;
  final String? culturedSpecies;
  final List<PhysicalReading>? physicalReadings;
  final List<ChemicalReading>? chemicalReadings;
  final List<DiseaseReading>? diseaseReadings;

  Pond({
    this.pondName,
    this.culturedArea,
    this.culturedSpecies,
    this.physicalReadings,
    this.chemicalReadings,
    this.diseaseReadings,
  });

  factory Pond.fromJson(Map<String, dynamic> json) {
    List<PhysicalReading>? phys;
    List<ChemicalReading>? chem;
    List<DiseaseReading>? dis;

    try {
      if (json['physicalReadings'] != null &&
          json['physicalReadings'] is List) {
        phys = (json['physicalReadings'] as List)
            .map((e) => PhysicalReading.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint('⚠️ error parsing physicalReadings: $e');
    }

    try {
      if (json['chemicalReadings'] != null &&
          json['chemicalReadings'] is List) {
        chem = (json['chemicalReadings'] as List)
            .map((e) => ChemicalReading.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint('⚠️ error parsing chemicalReadings: $e');
    }

    try {
      if (json['diseaseReadings'] != null && json['diseaseReadings'] is List) {
        dis = (json['diseaseReadings'] as List)
            .map((e) => DiseaseReading.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint('⚠️ error parsing diseaseReadings: $e');
    }

    return Pond(
      pondName: json['pondName'],
      culturedArea: json['culturedArea'],
      culturedSpecies: json['culturedSpecies'],
      physicalReadings: phys,
      chemicalReadings: chem,
      diseaseReadings: dis,
    );
  }
}

class PhysicalReading {
  final int? stockingPL;
  final int? doc;
  final double? feedIntakePerDay;
  final int? count;
  final double? avgWeight;

  PhysicalReading({
    this.stockingPL,
    this.doc,
    this.feedIntakePerDay,
    this.count,
    this.avgWeight,
  });

  factory PhysicalReading.fromJson(Map<String, dynamic> json) {
    return PhysicalReading(
      stockingPL: json['stockingPL'] is num
          ? (json['stockingPL'] as num).toInt()
          : null,
      doc: json['doc'] is num ? (json['doc'] as num).toInt() : null,
      feedIntakePerDay: json['feedIntakePerDay'] is num
          ? (json['feedIntakePerDay'] as num).toDouble()
          : null,
      count: json['count'] is num ? (json['count'] as num).toInt() : null,
      avgWeight: json['avgWeight'] is num
          ? (json['avgWeight'] as num).toDouble()
          : null,
    );
  }
}

class ChemicalReading {
  final double? salinity;
  final num? ph;
  final int? alkalinity;
  final double? ammonia;
  final double? nitrite;
  final double? dissolvedOxygen;

  ChemicalReading({
    this.salinity,
    this.ph,
    this.alkalinity,
    this.ammonia,
    this.nitrite,
    this.dissolvedOxygen,
  });

  factory ChemicalReading.fromJson(Map<String, dynamic> json) {
    return ChemicalReading(
      salinity: json['salinity'] is num
          ? (json['salinity'] as num).toDouble()
          : null,
      ph: json['ph'],
      alkalinity: json['alkalinity'] is num
          ? (json['alkalinity'] as num).toInt()
          : null,
      ammonia: json['ammonia'] is num
          ? (json['ammonia'] as num).toDouble()
          : null,
      nitrite: json['nitrite'] is num
          ? (json['nitrite'] as num).toDouble()
          : null,
      dissolvedOxygen: json['dissolvedOxygen'] is num
          ? (json['dissolvedOxygen'] as num).toDouble()
          : null,
    );
  }
}

class DiseaseReading {
  // vibrios can be numeric (CFU/ml) or textual
  final dynamic vibrios;

  DiseaseReading({this.vibrios});

  factory DiseaseReading.fromJson(Map<String, dynamic> json) {
    return DiseaseReading(vibrios: json['vibrios']);
  }
}

class PondParameters {
  final num? pH;
  final num? ammonia;
  final num? nitrite;
  final num? alkalinity;

  PondParameters({this.pH, this.ammonia, this.nitrite, this.alkalinity});

  factory PondParameters.fromJson(Map<String, dynamic> json) {
    return PondParameters(
      pH: json['pH'],
      ammonia: json['ammonia'],
      nitrite: json['nitrite'],
      alkalinity: json['alkalinity'],
    );
  }
}
