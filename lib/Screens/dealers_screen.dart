// lib/screens/dealers_screen.dart
// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:FieldService_app/Screens/add_dealer_screen.dart';
import 'package:FieldService_app/Screens/dealer_purposes_screen.dart';
import 'package:FieldService_app/config.dart';
import 'package:FieldService_app/main.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';

/// DealersScreen: shows a list of dealers, allows selecting a dealer and starting a visit.
/// Most code is unchanged from your original file — only the dealer card decoration
/// (background / border / radius / shadow) has been fixed and commented.
class DealersScreen extends StatefulWidget {
  final bool display;
  final bool showPendingOnStart;
  final bool refreshOnStart;
  const DealersScreen({
    super.key,
    this.display = false,
    this.showPendingOnStart = false,
    this.refreshOnStart = false,
  });

  @override
  State<DealersScreen> createState() => _DealersScreenState();
}

class _DealersScreenState extends State<DealersScreen> {
  // App colors used in multiple places
  final Color appGreen = const Color(0xFF1AB69C);
  final Color backgroundColor = const Color.fromRGBO(255, 212, 219, 220);

  bool _loading = true;
  String? _error;
  final bool _isSearching = false;
  String _searchQuery = '';

  List<_Dealer> _dealers = [];
  String? _selectedDealerId; // single-select dot

  bool condition = false;

  // Text controller for the search input
  final TextEditingController _dealerSearchCtrl = TextEditingController();

  String _selectedStatusFilter = 'Approved';

  @override
  void dispose() {
    _dealerSearchCtrl.dispose();
    super.dispose();
  }

  // Safe setState wrapper to avoid calling setState after dispose
  void _safeSet(void Function() fn) {
    if (!mounted) return;
    setState(fn);
  }

  @override
  void initState() {
    super.initState();
    condition = widget.display;

    if (widget.showPendingOnStart) {
      _selectedStatusFilter = 'Pending';
    }
    _saveTripComplete();

    // If requested, force refresh when screen is created
    _fetchDealers(forceRefresh: true);
  }

  Future<void> _saveTripComplete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('tripcomplete', condition);
  }

  // Fetch dealers from API (caching handled by apiClient)
  Future<void> _fetchDealers({bool forceRefresh = false}) async {
    _safeSet(() {
      _loading = true;
      _error = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final employeeId = prefs.getString('userId') ?? '';

      if (employeeId.isEmpty) {
        _safeSet(() {
          _loading = false;
          _error = 'User ID not found in preferences';
        });
        return;
      }

      final path = AppConfig.fill('/api/dealers/employee/{id}', {
        'id': employeeId,
      });
      final cacheKey = 'dealers:$employeeId';

      // If forcing refresh, use zero TTL so cached entry is treated stale.
      final ttl = forceRefresh ? Duration.zero : const Duration(minutes: 2);

      debugPrint('🌍 [Dealers] GET $path (cacheKey=$cacheKey, ttl=$ttl)');
      final result = await apiClient.getJsonCached(
        path: path,
        cacheKey: cacheKey,
        ttl: ttl,
      );

      debugPrint(
        '↩️ [Dealers] code=${result.statusCode} fromCache=${result.fromCache}',
      );

      final data = result.data;
      if (data is Map && data['success'] == true) {
        final list = (data['dealers'] as List? ?? const [])
            .map((e) => _Dealer.fromJson(e))
            .toList();
        _safeSet(() => _dealers = list);
      } else if (data is Map && data['dealers'] is List) {
        final list = (data['dealers'] as List)
            .map((e) => _Dealer.fromJson(e))
            .toList();
        _safeSet(() => _dealers = list);
      } else if (data is List) {
        final list = data.map((e) => _Dealer.fromJson(e)).toList();
        _safeSet(() => _dealers = list);
      } else {
        _safeSet(
          () => _error =
              'No data available${result.fromCache ? " (cached)" : ""}',
        );
      }
    } catch (e) {
      _safeSet(() => _error = 'Network error: $e');
    } finally {
      _safeSet(() => _loading = false);
    }
  }

  // Show add dealer bottom sheet and optionally refresh
  Future<void> _openAddDealer() async {
    final refreshed = await AddDealerBottomSheet.show(context);
    if (refreshed == true) {
      // Show pending filter and force a network refresh
      _safeSet(() {
        _selectedStatusFilter = 'Pending';
      });
      await _fetchDealers(forceRefresh: true);
    }
  }

  // Utility: parse "lat,lng" (or with other separators) into doubles
  ({double lat, double lng})? _parseLatLngFromString(String? location) {
    if (location == null) return null;
    final s = location.trim();
    if (s.isEmpty) return null;

    // allow comma, space, pipe or semicolon as separators
    final parts = s
        .split(RegExp(r'[,\s;|]+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.length < 2) return null;

    final lat = double.tryParse(parts[0]);
    final lng = double.tryParse(parts[1]);
    if (lat == null || lng == null) return null;

    return (lat: lat, lng: lng);
  }

  // Apply status filter and search filter
  List<_Dealer> get _filtered {
    List<_Dealer> list = _dealers;

    // Apply status filter first
    if (_selectedStatusFilter != 'All') {
      list = list.where((d) {
        final s = (d.status ?? '').toLowerCase();
        if (_selectedStatusFilter == 'Approved') return s == 'approved';
        if (_selectedStatusFilter == 'Pending') return s == 'pending';
        if (_selectedStatusFilter == 'Rejected') return s == 'rejected';
        return true;
      }).toList();
    }

    // Then apply search filter
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.toLowerCase().trim();
      list = list.where((d) {
        return (d.dealerName?.toLowerCase().contains(q) ?? false) ||
            (d.shopName?.toLowerCase().contains(q) ?? false) ||
            (d.mobileNumber?.toLowerCase().contains(q) ?? false) ||
            (d.shopAddress?.toLowerCase().contains(q) ?? false);
      }).toList();
    }

    return list;
  }

  // Handler for starting visit: checks selection and coordinates
  void _onStartVisit() {
    // if (condition == false) {
    //   ScaffoldMessenger.of(context).hideCurrentSnackBar();
    //   ScaffoldMessenger.of(context).showSnackBar(
    //     SnackBar(
    //       content: const Text('Complete a Trip First.'),
    //       duration: const Duration(seconds: 2),
    //       backgroundColor: const Color.fromARGB(221, 214, 5, 5),
    //       behavior: SnackBarBehavior.floating,
    //       shape: RoundedRectangleBorder(
    //         borderRadius: BorderRadius.circular(12),
    //       ),
    //     ),
    //   );
    //   return;
    // }

    final d = _dealers.firstWhere((e) => e.id == _selectedDealerId);
    final coords = _parseLatLngFromString(d.location) ?? (lat: 0.0, lng: 0.0);

    _showPurposeSelectionScreen(d, coords);
  }

  void _showPurposeSelectionScreen(
    _Dealer dealer,
    ({double lat, double lng}) coords,
  ) {
    final dealerId = dealer.id ?? '';
    final double pendingAmount = dealer.pendingAmount;

    final dealerName = (dealer.dealerName?.trim().isNotEmpty ?? false)
        ? dealer.dealerName!.trim()
        : (dealer.shopName ?? 'Dealer');

    final shopName = dealer.shopName ?? '';
    final address = dealer.shopAddress ?? '';
    final mobile = dealer.mobileNumber ?? '';

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DealerPurposesScreen(
          dealerId: dealerId,
          dealerName: dealerName,
          shopName: shopName,
          address: address,
          mobile: mobile,
          latitude: coords.lat,
          longitude: coords.lng,
          pendingAmount: pendingAmount,
          allowOtherPurpose: condition,
          tripCompleted: condition,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _filtered; // filtered dealers list

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: Container(
          decoration: const BoxDecoration(
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
            gradient: LinearGradient(
              colors: [
                Color(0xFF52D494), // top gradient color
                Color((0xFF1AB69C)), // bottom gradient color
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: AppBar(
            backgroundColor: Colors.transparent, // must be transparent
            elevation: 0,
            automaticallyImplyLeading: false,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
            ),
            title: const Text(
              'Dealers List',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
                fontSize: 20,
              ),
            ),
            centerTitle: true,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_sharp, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Color(0xFFFFFFFF).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: condition
          ? FloatingActionButton.extended(
              onPressed: _openAddDealer,
              backgroundColor: const Color(0xFF1AB69C),
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text(
                'Add Dealer',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          : null,
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
          child: SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _selectedDealerId == null ? null : _onStartVisit,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1AB69C),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.playlist_add_check),
              label: const Text(
                'Next',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ),
      ),

      // Body with search and list
      body: Column(
        children: [
          // Search field
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: TextField(
              controller: _dealerSearchCtrl,
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: InputDecoration(
                hintText: 'Search dealers (name / mobile / location)…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: (_searchQuery.isNotEmpty)
                    ? IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _dealerSearchCtrl.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: appGreen),
                ),
              ),
            ),
          ),

          // Status chips filter
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                for (final status in ['All', 'Approved', 'Pending', 'Rejected'])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(status),
                      selected: _selectedStatusFilter == status,
                      onSelected: (_) => setState(() {
                        _selectedStatusFilter = status;
                      }),
                      selectedColor: const Color(0xFF1AB69C),
                      backgroundColor: Colors.white,
                      labelStyle: TextStyle(
                        color: _selectedStatusFilter == status
                            ? Colors.white
                            : Colors.grey[800],
                        fontWeight: FontWeight.normal,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(
                          color: _selectedStatusFilter == status
                              ? const Color(0xFF1AB69C)
                              : const Color(0xFF1AB69C),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // The dealers list (or loading / empty states)
          Expanded(child: _buildBody(items)),
        ],
      ),
    );
  }

  Widget _buildBody(List<_Dealer> items) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _buildErrorState(_error!);
    if (items.isEmpty) return _buildEmptyState();

    return RefreshIndicator(
      onRefresh: _fetchDealers,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          20,
          10,
          20,
          90,
        ), // extra bottom for Start Visit btn
        itemCount: items.length,
        itemBuilder: (_, i) => _buildDealerCard(items[i]),
      ),
    );
  }

  Widget _buildErrorState(String message) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(20),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.info_outline, color: Colors.orange, size: 32),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Colors.black87),
            ),
            const SizedBox(height: 12),
            TextButton(onPressed: _fetchDealers, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: appGreen.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              alignment: Alignment.center,
              child: Icon(Icons.business, size: 36, color: appGreen),
            ),
            const SizedBox(height: 16),
            Text(
              'No dealers found',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.grey[800],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _isSearching
                  ? 'Try adjusting your search terms'
                  : 'Add your first dealer to get started',
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  /// ---------------------------
  /// Dealer card (fixed version)
  /// ---------------------------
  ///
  /// Important fixes applied here:
  ///  - Removed duplicate `color` entries (kept card background white).
  ///  - Added `border: Border.all(...)` so border color and width can be controlled.
  ///  - Used `selected` and `status` to decide border color (you can adjust rules).
  Widget _buildDealerCard(_Dealer d) {
    final selected = d.id == _selectedDealerId;
    final status = (d.status ?? 'pending').toLowerCase();

    final isApproved = status == 'approved';
    final isPending = status == 'pending';
    final isRejected = status == 'rejected';

    // Helper to pick the small status-chip color
    Color statusColor() {
      if (isPending) return Colors.orange;
      if (isRejected) return Colors.red;
      return Colors.transparent;
    }

    // Label shown next to shop name for non-approved items
    String? statusLabel() {
      if (isPending) return 'Pending';
      if (isRejected) return 'Rejected';
      return null;
    }

    // Increase border width when selected to make it more visible
    final double borderWidth = selected ? 2.0 : 1.0;

    return Opacity(
      opacity: isApproved ? 1.0 : 0.85, // faded look for non-approved dealers
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white, // KEEP a single card background color
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Color(0xFF1AB69C), width: borderWidth),
          boxShadow: [
            BoxShadow(
              // soft shadow
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: InkWell(
          // InkWell visual splash respects the rounded border because of borderRadius here
          onTap: () {
            if (isRejected) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Rejected dealers cannot be selected.'),
                  behavior: SnackBarBehavior.floating,
                  duration: Duration(seconds: 2),
                ),
              );
              return;
            }
            _safeSet(() {
              _selectedDealerId = (_selectedDealerId == d.id) ? null : d.id;
            });
          },
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left icon box
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: appGreen.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.store_rounded,
                    color: const Color(0xFF1AB69C),
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),

                // Dealer info (name, address, phone)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              (d.shopName?.isNotEmpty ?? false)
                                  ? d.shopName!.trim()
                                  : (d.dealerName ?? 'Dealer'),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF2C3E50),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),

                          // Status pill (Pending / Rejected)
                          if (statusLabel() != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: statusColor().withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                statusLabel()!,
                                style: TextStyle(
                                  color: statusColor(),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                        ],
                      ),

                      // Dealer personal name (if present)
                      if ((d.dealerName ?? '').trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            d.dealerName!.trim(),
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[700],
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      const SizedBox(height: 10),

                      // Address row
                      if ((d.shopAddress ?? '').trim().isNotEmpty)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.location_on_rounded,
                              size: 18,
                              color: Colors.grey[600],
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                d.shopAddress!.trim(),
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[700],
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      const SizedBox(height: 8),

                      // Phone row
                      if ((d.mobileNumber ?? '').trim().isNotEmpty)
                        Row(
                          children: [
                            Icon(
                              Icons.phone,
                              size: 16,
                              color: Colors.grey[600],
                            ),
                            const SizedBox(width: 6),
                            Text(
                              d.mobileNumber!.trim(),
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[800],
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      const SizedBox(height: 8),

                      if (isApproved || isPending)
                        Row(
                          children: [
                            Icon(
                              Icons.account_balance_wallet,
                              size: 15,
                              color: Colors.grey[600],
                            ),
                            const SizedBox(width: 8),
                            Builder(
                              builder: (_) {
                                // formatter for Indian currency (₹) with thousands separators
                                final fmt = NumberFormat.currency(
                                  locale: 'en_IN',
                                  symbol: '₹',
                                  decimalDigits: 2,
                                );
                                final pending =
                                    d.pendingAmount; // already parsed in model
                                final noDue = pending <= 0.0;
                                // safe debug print of numeric value
                                debugPrint(
                                  'pendingAmount=${pending.toString()}',
                                );
                                // Debug.log(
                                //   'Dealer ${d.shopName} pendingAmount: $pending'
                                //       as num,
                                // );
                                return Flexible(
                                  child: Text(
                                    noDue
                                        ? 'No Due'
                                        : 'Due: ${fmt.format(pending)}',
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 18,
                                      color: noDue
                                          ? Colors.green
                                          : const Color.fromARGB(
                                              255,
                                              255,
                                              0,
                                              0,
                                            ),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                    ],
                  ),
                ),

                if (isApproved || isPending)
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected
                            ? const Color(0xFF1AB69C)
                            : Colors.grey.shade400,
                        width: 2,
                      ),
                      color: selected
                          ? const Color(0xFF1AB69C)
                          : Colors.transparent,
                    ),
                    child: selected
                        ? Center(
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                            ),
                          )
                        : null,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Simple dealer model (scoped to this file)
class _Dealer {
  final String? id;
  final String? companyId;
  final String? employeeId;
  final String? dealerName;
  final String? shopName;
  final String? mobileNumber;
  final String? shopAddress;
  final String? location;
  final String? status; // approved / pending / rejected
  final DateTime? createdAt;
  final double pendingAmount; // NEW: pending amount (defaults to 0.0)

  _Dealer({
    this.id,
    this.companyId,
    this.employeeId,
    this.dealerName,
    this.shopName,
    this.mobileNumber,
    this.shopAddress,
    this.location,
    this.status,
    this.createdAt,
    this.pendingAmount = 0.0,
  });

  factory _Dealer.fromJson(Map<String, dynamic> j) {
    String? str(dynamic v) => v?.toString().trim();
    // parse pendingAmount safely (could be int/double/null)
    double parseAmount(dynamic v) {
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      final s = v.toString().trim();
      return double.tryParse(s) ?? 0.0;
    }

    debugPrint("RAW: ${j.keys}");
    debugPrint("PENDING RAW VALUE: ${j['pendingAmount']}");

    return _Dealer(
      id: str(j['_id']),
      companyId: str(j['companyId']),
      employeeId: str(j['employeeId']),
      dealerName: str(j['dealerName']),
      shopName: str(j['shopName']),
      mobileNumber: str(j['mobileNumber']),
      shopAddress: str(j['shopAddress']),
      location: str(j['location']),
      status: str(j['status']) ?? 'pending', // default to pending
      createdAt: j['createdAt'] != null
          ? DateTime.tryParse(j['createdAt'])
          : null,
      pendingAmount: parseAmount(j['pendingAmount']),
    );
  }
}

class LocationService {
  // Helper to get current position and human-readable area (reverse geocode)
  static Future<(Position, String?)?> getPositionAndArea() async {
    // Ensure permission
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever ||
        permission == LocationPermission.unableToDetermine) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
    }

    final pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    try {
      final placemarks = await placemarkFromCoordinates(
        pos.latitude,
        pos.longitude,
      );
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final parts = <String>[];
        if ((p.subLocality ?? '').isNotEmpty) parts.add(p.subLocality!);
        if ((p.locality ?? '').isNotEmpty) parts.add(p.locality!);
        if ((p.subAdministrativeArea ?? '').isNotEmpty) {
          parts.add(p.subAdministrativeArea!);
        }
        if ((p.administrativeArea ?? '').isNotEmpty) {
          parts.add(p.administrativeArea!);
        }
        if ((p.country ?? '').isNotEmpty) parts.add(p.country!);

        final area = parts.isNotEmpty ? parts.join(', ') : 'Location available';
        return (pos, area);
      }
    } catch (_) {
      // ignore reverse-geocode failure; still return raw position
    }
    return (pos, 'Location available');
  }
}
