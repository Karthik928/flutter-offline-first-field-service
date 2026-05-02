// lib/screena/farmer_visit_screen.dart
// Farmer Visit (list-only like Dealer Visit)
// - Shows FARMERS LIST with search + single-select
// - Floating "Add Farmer" button opens a bottom sheet to add a farmer (with Get Location, strict validations, dynamic ponds)
// - "Start Visit" bottom bar enabled only after selecting a farmer; returns the selected farmer id (Navigator.pop)

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:FieldService_app/Screens/add_farmer_screen.dart';
import 'package:FieldService_app/Screens/farmer_purposes_screen.dart';
import 'package:FieldService_app/config.dart';
import 'package:FieldService_app/main.dart';

class FarmerVisitScreen extends StatefulWidget {
  final bool display;
  final bool showPendingOnStart;
  final bool refreshOnStart;
  const FarmerVisitScreen({
    super.key,
    this.display = false,
    this.showPendingOnStart = false,
    this.refreshOnStart = false,
  });

  /// When user taps "Start Visit", we pop with the selected farmer id (String?).
  /// Caller: final selectedId = await Navigator.push(...);
  @override
  State<FarmerVisitScreen> createState() => _FarmerVisitScreenState();
}

class _FarmerVisitScreenState extends State<FarmerVisitScreen> {
  final Color appGreen = const Color(0xFF1AB69C);
  final Color backgroundColor = const Color.fromRGBO(255, 212, 219, 220);

  bool _loading = true;
  String? _error;
  String _search = '';
  List<_FarmerLite> _farmers = [];
  String? _selectedId;
  bool condition = false;

  // New: status filter state ('all' | 'approved' | 'pending' | 'rejected')
  String _filterStatus = 'approved';

  @override
  void initState() {
    super.initState();
    condition = widget.display;
    if (widget.showPendingOnStart) {
      _filterStatus = 'pending';
    }
    _saveTripComplete();
    // If requested, force refresh when screen is created
    _fetchFarmers(forceRefresh: widget.refreshOnStart);
  }

  Future<void> _saveTripComplete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('tripcomplete', condition);
  }

  void _safeSet(void Function() fn) {
    if (!mounted) return;
    setState(fn);
  }

  Future<void> _fetchFarmers({bool forceRefresh = false}) async {
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

      final path = AppConfig.fill('/api/farmers/employee/{id}', {
        'id': employeeId,
      });
      final cacheKey = 'farmers:$employeeId';

      debugPrint('🌍 [Farmers] GET $path (cacheKey=$cacheKey)');

      final ttl = forceRefresh ? Duration.zero : const Duration(minutes: 2);

      final result = await apiClient.getJsonCached(
        path: path,
        cacheKey: cacheKey,
        ttl: ttl,
      );

      debugPrint(
        '↩️ [Farmers] code=${result.statusCode} fromCache=${result.fromCache}',
      );

      final j = result.data;
      final raw = (j is Map && j['farmers'] is List)
          ? (j['farmers'] as List)
          : (j is List ? j : const <dynamic>[]);

      final list = raw.map((e) => _FarmerLite.fromJson(e)).toList();
      _safeSet(() => _farmers = list);
    } catch (e) {
      _safeSet(() => _error = 'Failed to load farmers: $e');
    } finally {
      _safeSet(() => _loading = false);
    }
  }

  List<_FarmerLite> get _filtered {
    final q = _search.trim().toLowerCase();

    Iterable<_FarmerLite> list = _farmers;

    // Apply status filter
    if (_filterStatus != 'all') {
      list = list.where((f) => (f.status ?? 'approved') == _filterStatus);
    }

    // Apply search
    if (q.isEmpty) return list.toList();
    return list.where((f) {
      return (f.name?.toLowerCase().contains(q) ?? false) ||
          (f.address?.toLowerCase().contains(q) ?? false) ||
          (f.mobile?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  Future<void> _openAddFarmer() async {
    final refreshed = await AddFarmerBottomSheet.show(context);
    if (refreshed == true) {
      // Show pending filter and force a network refresh
      _safeSet(() {
        _filterStatus = 'pending';
      });
      await _fetchFarmers(forceRefresh: true);
    }
  }

  void _onStartVisit() {
    // Get the selected farmer object
    final farmer = _farmers.firstWhere((f) => f.id == _selectedId);

    // Only rejected farmers are blocked
    if ((farmer.status ?? '').toLowerCase() == 'rejected') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Rejected farmers cannot be selected.'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    _showPurposeSelectionScreen(farmer);
  }

  void _showPurposeSelectionScreen(_FarmerLite farmer) {
    double lat = 0;
    double lng = 0;

    if (farmer.location != null && farmer.location!.contains(' ')) {
      final parts = farmer.location!.split(' ');
      lat = double.tryParse(parts[0]) ?? 0;
      lng = double.tryParse(parts[1]) ?? 0;
    }

    final farmerId = farmer.id ?? '';
    final farmerName = farmer.name ?? 'Farmer';
    final mobile = farmer.mobile ?? '';
    final address = farmer.address ?? '';
    final pendingAmount = farmer.pendingAmount.toDouble();
    final totalCultureArea = farmer.totalCultureArea;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FarmerPurposesScreen(
          farmerId: farmerId,
          farmerName: farmerName,
          address: address,
          mobile: mobile,
          latitude: lat,
          longitude: lng,
          pendingAmount: pendingAmount,
          allowOtherVisit: condition,
          tripCompleted: condition,
          totalCultureArea: totalCultureArea,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _filtered;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(30),
          ),
          child: Container(
            decoration: const BoxDecoration(
              // give the container the same rounded bottom corners
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
              gradient: LinearGradient(
                colors: [Color(0xFF52D494), Color(0xFF1AB69C)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              title: const Text(
                "Farmers List",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              centerTitle: true,
              // AppBar shape can stay but is optional now
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(30),
                ),
              ),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_sharp, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),
        ),
      ),

      floatingActionButton: condition
          ? FloatingActionButton.extended(
              onPressed: _openAddFarmer,
              backgroundColor: appGreen,
              icon: const Icon(
                Icons.person_add_alt_1,
                color: Color.fromARGB(255, 255, 255, 255),
              ),
              label: const Text(
                'Add Farmer',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          : null,

      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: _selectedId == null ? null : _onStartVisit,

            style: ElevatedButton.styleFrom(
              backgroundColor: Color(0xFF1AB69C),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Next',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
          ),
        ),
      ),

      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: _SearchBox(
              hint: 'Search farmers (name / mobile / location)…',
              onChanged: (v) => setState(() => _search = v),
            ),
          ),

          // New: filter chips row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _StatusChip(
                    label: 'All',
                    value: 'all',
                    selected: _filterStatus == 'all',
                    onTap: () => setState(() => _filterStatus = 'all'),
                  ),
                  const SizedBox(width: 8),
                  _StatusChip(
                    label: 'Approved',
                    value: 'approved',
                    selected: _filterStatus == 'approved',
                    onTap: () => setState(() => _filterStatus = 'approved'),
                  ),
                  const SizedBox(width: 8),
                  _StatusChip(
                    label: 'Pending',
                    value: 'pending',
                    selected: _filterStatus == 'pending',
                    onTap: () => setState(() => _filterStatus = 'pending'),
                  ),
                  const SizedBox(width: 8),
                  _StatusChip(
                    label: 'Rejected',
                    value: 'rejected',
                    selected: _filterStatus == 'rejected',
                    onTap: () => setState(() => _filterStatus = 'rejected'),
                  ),
                ],
              ),
            ),
          ),

          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : (_error != null
                      ? _ErrorRetry(message: _error!, onRetry: _fetchFarmers)
                      : RefreshIndicator(
                          onRefresh: _fetchFarmers,
                          child: items.isEmpty
                              ? const _EmptyState(
                                  icon: Icons.agriculture,
                                  title: 'No farmers found',
                                )
                              : ListView.separated(
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    8,
                                    16,
                                    24,
                                  ),
                                  itemCount: items.length,
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(height: 10),
                                  itemBuilder: (_, i) {
                                    final f = items[i];
                                    final selected = f.id == _selectedId;
                                    return _SelectCard(
                                      leadingIcon: Icons.agriculture_rounded,
                                      title: f.name ?? 'Farmer',
                                      subtitle: (f.mobile ?? '').isNotEmpty
                                          ? f.mobile!
                                          : '',
                                      subtitle2: f.address ?? '',
                                      status: f.status, // 👈 NEW
                                      trailingSelected: selected,
                                      pendingAmount: f
                                          .pendingAmount, // 👈 NEW (shows location in place of trailing icon)
                                      onTap: () {
                                        if (f.status?.toLowerCase() ==
                                            'rejected') {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Rejected farmers cannot be selected.',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              behavior:
                                                  SnackBarBehavior.floating,
                                              duration: Duration(seconds: 2),
                                            ),
                                          );
                                          return;
                                        }
                                        setState(
                                          () => _selectedId = selected
                                              ? null
                                              : f.id,
                                        );
                                      },
                                    );
                                  },
                                ),
                        )),
          ),
        ],
      ),
    );
  }
}

/* ========================= Small helper widgets & models ========================= */

class _StatusChip extends StatelessWidget {
  final String label;
  final String value;
  final bool selected;
  final VoidCallback onTap;
  const _StatusChip({
    required this.label,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: Color(0xFF1AB69C),
      backgroundColor: Colors.white,
      labelStyle: TextStyle(
        color: selected ? Colors.white : Colors.grey[800],
        fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
      ),
      elevation: 0,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    );
  }
}

class _FarmerLite {
  final String? id;
  final String? name;
  final String? mobile;
  final String? address;
  final String? status;
  final String? location;
  final num pendingAmount;
  final num totalCultureArea;

  _FarmerLite({
    this.id,
    this.name,
    this.mobile,
    this.address,
    this.status,
    this.location,
    this.pendingAmount = 0,
    this.totalCultureArea = 0,
  });

  factory _FarmerLite.fromJson(dynamic j) {
    String? s(String k) {
      try {
        final v = (j as Map)[k];
        return v?.toString().trim();
      } catch (_) {
        return null;
      }
    }

    num parseNum(String k) {
      try {
        final v = (j as Map)[k];
        if (v == null) return 0;
        if (v is num) return v;
        return num.parse(v.toString());
      } catch (_) {
        return 0;
      }
    }

    return _FarmerLite(
      id: s('_id') ?? s('id'),
      name: s('name') ?? s('farmerName'),
      mobile: s('mobileNumber') ?? s('mobile'),
      address: s('address'),
      status: s('status') ?? 'pending',
      location: s('location'),
      pendingAmount: parseNum('pendingAmount'),
      totalCultureArea: parseNum('totalCultureArea'),
    );
  }
}

class _SearchBox extends StatelessWidget {
  const _SearchBox({required this.hint, required this.onChanged});
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search),
        filled: true,
        fillColor: Colors.grey.withValues(alpha: 0.08),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
      ),
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.info_outline, color: Colors.orange, size: 32),
            const SizedBox(height: 10),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 10),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.title});
  final IconData icon;
  final String title;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: Color(0xFF1AB69C)),
            const SizedBox(height: 10),
            Text(title, style: TextStyle(color: Colors.grey[700])),
          ],
        ),
      ),
    );
  }
}

class _SelectCard extends StatelessWidget {
  final IconData leadingIcon;
  final String title;
  final String subtitle;
  final String? subtitle2;
  final num pendingAmount; // 👈 NEW
  final String? status; // approved / pending / rejected
  final bool trailingSelected;
  final VoidCallback onTap;

  const _SelectCard({
    required this.leadingIcon,
    required this.title,
    required this.subtitle,
    this.subtitle2,
    this.pendingAmount = 0, // 👈 NEW
    this.status,
    required this.trailingSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final appGreen = const Color(0xFF1AB69C);

    // Determine status flags
    final isApproved = (status ?? '').toLowerCase() == 'approved';
    final isPending = (status ?? '').toLowerCase() == 'pending';
    final isRejected = (status ?? '').toLowerCase() == 'rejected';

    Color statusColor() {
      if (isPending) return Colors.orange;
      if (isRejected) return Colors.red;
      return Colors.transparent;
    }

    String? statusLabel() {
      if (isPending) return 'Pending';
      if (isRejected) return 'Rejected';
      return null;
    }

    // Decide the card border color:
    // - selected -> app green (more visible)
    // - pending -> orange
    // - rejected -> red
    // - otherwise -> light neutral border
    final Color cardBorderColor = trailingSelected
        ? appGreen
        : (isPending
              ? Colors.orange.withValues(alpha: 0.9)
              : (isRejected
                    ? Colors.red.withValues(alpha: 0.9)
                    : Color(0xFF1AB69C).withValues(alpha: 0.5)));

    final double cardBorderWidth = trailingSelected ? 2.0 : 1.0;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            // Rounded corners
            borderRadius: BorderRadius.circular(16),

            // Visible border (this is the key change)
            border: Border.all(color: cardBorderColor, width: cardBorderWidth),

            // Soft shadow
            boxShadow: [
              BoxShadow(
                color: Colors.white,
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Leading icon box
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: appGreen.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(leadingIcon, color: appGreen),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                        ),
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
                    const SizedBox(height: 6),
                    if (subtitle.trim().isNotEmpty)
                      Row(
                        children: [
                          Icon(Icons.phone, size: 16, color: Colors.grey[600]),
                          const SizedBox(width: 6),
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.grey[800],
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 6),
                    if ((subtitle2 ?? '').trim().isNotEmpty)
                      Row(
                        children: [
                          Icon(
                            Icons.location_on_rounded,
                            size: 16,
                            color: Colors.grey[600],
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            // child: Padding(
                            //   padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              subtitle2!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.grey[700],
                                fontSize: 13,
                              ),
                            ),
                            //),
                          ),
                        ],
                      ),
                    const SizedBox(height: 6),

                    if (isApproved || isPending)
                      Row(
                        mainAxisSize: MainAxisSize.min,
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
                                  pendingAmount; // already parsed in model
                              final noDue = pending <= 0.0;
                              // safe debug print of numeric value
                              debugPrint('pendingAmount=${pending.toString()}');
                              // Debug.log(
                              //   'Dealer ${d.shopName} pendingAmount: $pending'
                              //       as num,
                              // );
                              return Text(
                                noDue
                                    ? 'No Due'
                                    : 'Due: ${fmt.format(pending)}',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 18,
                                  color: noDue
                                      ? Colors.green
                                      : const Color.fromARGB(255, 255, 0, 0),
                                  fontWeight: FontWeight.w600,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                  ],
                ),
              ),

              // Selection circle (only for approved)
              if (isApproved || isPending)
                Container(
                  width: 22,
                  height: 22,
                  margin: const EdgeInsets.only(left: 8, top: 4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: trailingSelected ? appGreen : Colors.grey.shade400,
                      width: 2,
                    ),
                    color: trailingSelected ? appGreen : Colors.transparent,
                  ),
                  child: trailingSelected
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
    );
  }
}

/* ========================= Add Farmer Bottom Sheet ========================= */

// class AddFarmerBottomSheet extends StatefulWidget {
//   const AddFarmerBottomSheet({super.key});

//   static Future<bool?> show(BuildContext context) {
//     return showModalBottomSheet<bool>(
//       context: context,
//       isScrollControlled: true, // keep true for keyboard-safe + scroll
//       backgroundColor: Colors.transparent,
//       builder: (context) {
//         return DraggableScrollableSheet(
//           expand: false,
//           initialChildSize: 0.65, // 👈 80% height initially
//           minChildSize: 0.6, // 👈 can shrink to 60%
//           maxChildSize: 0.9, // 👈 can drag to full
//           builder: (_, controller) {
//             return Container(
//               decoration: const BoxDecoration(
//                 color: Colors.white,
//                 borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
//               ),
//               child: SingleChildScrollView(
//                 controller: controller,
//                 child: const AddFarmerBottomSheet(),
//               ),
//             );
//           },
//         );
//       },
//     );
//   }

//   @override
//   State<AddFarmerBottomSheet> createState() => _AddFarmerBottomSheetState();
// }

// class _AddFarmerBottomSheetState extends State<AddFarmerBottomSheet> {
//   final _formKey = GlobalKey<FormState>();
//   final Color appGreen = const Color(0xFF2E7D32);

//   // Main fields
//   final _nameCtrl = TextEditingController();
//   final _mobileCtrl = TextEditingController();
//   final _addressCtrl = TextEditingController(); // read-only (Get Location)
//   final _areaCtrl = TextEditingController();

//   // Ponds (farms)
//   final List<_PondForm> _ponds = [_PondForm()];

//   bool _submitting = false;
//   bool _locating = false;
//   String? _topError;

//   // inside _FarmerVisitScreenState
//   double? _lat;
//   double? _lng;

//   @override
//   void dispose() {
//     _nameCtrl.dispose();
//     _mobileCtrl.dispose();
//     _addressCtrl.dispose();
//     _areaCtrl.dispose();
//     for (final p in _ponds) {
//       p.dispose();
//     }
//     super.dispose();
//   }

//   void _setTopError(String? msg) {
//     if (!mounted) return;
//     setState(() => _topError = msg);
//   }

//   // Input formatters
//   static final List<TextInputFormatter> _lettersOnly = [
//     FilteringTextInputFormatter.allow(RegExp(r"[A-Za-z ]")),
//     LengthLimitingTextInputFormatter(40),
//   ];
//   static final List<TextInputFormatter> _tenDigits = [
//     FilteringTextInputFormatter.digitsOnly,
//     LengthLimitingTextInputFormatter(10),
//   ];
//   static final TextInputFormatter _oneDotNumber =
//       TextInputFormatter.withFunction(
//         (oldValue, newValue) => RegExp(r'^\d*\.?\d*$').hasMatch(newValue.text)
//             ? newValue
//             : oldValue,
//       );

//   // Validators
//   String? _vName(String? v) {
//     final s = (v ?? '').trim();
//     if (s.isEmpty) return 'Name is required';
//     if (!RegExp(r'^[A-Za-z ]+$').hasMatch(s)) return 'Letters & spaces only';
//     return null;
//   }

//   String? _vMobile(String? v) {
//     final s = (v ?? '').trim();
//     if (s.length != 10) return 'Enter exactly 10 digits';
//     if (!RegExp(r'^\d{10}$').hasMatch(s)) return 'Invalid number';
//     return null;
//   }

//   String? _vRequired(String? v, String label) {
//     if ((v ?? '').trim().isEmpty) return '$label is required';
//     return null;
//   }

//   String? _vDoublePos(String? v, String label) {
//     final s = (v ?? '').trim();
//     if (s.isEmpty) return '$label is required';
//     final d = double.tryParse(s);
//     if (d == null || d <= 0) return 'Enter a valid positive number';
//     return null;
//   }

//   // Location
//   Future<void> _getLocation() async {
//     _setTopError(null);
//     setState(() => _locating = true);
//     try {
//       LocationPermission perm = await Geolocator.checkPermission();
//       if (perm == LocationPermission.denied ||
//           perm == LocationPermission.deniedForever) {
//         perm = await Geolocator.requestPermission();
//         if (perm == LocationPermission.denied ||
//             perm == LocationPermission.deniedForever) {
//           _setTopError('Location permission denied');
//           return;
//         }
//       }
//       final pos = await Geolocator.getCurrentPosition(
//         desiredAccuracy: LocationAccuracy.high,
//       );

//       String address = 'Location available';
//       try {
//         final pm = await placemarkFromCoordinates(pos.latitude, pos.longitude);
//         if (pm.isNotEmpty) {
//           final p = pm.first;
//           final parts = [
//             p.name,
//             p.street,
//             p.subLocality,
//             p.locality,
//             p.subAdministrativeArea,
//             p.administrativeArea,
//             p.postalCode,
//             p.country,
//           ].where((e) => e != null && e.trim().isNotEmpty).toList();

//           if (parts.isNotEmpty) address = parts.join(', ');
//         }
//       } catch (_) {}

//       if (!mounted) return;
//       setState(() {
//         _lat = pos.latitude;
//         _lng = pos.longitude;
//         _addressCtrl.text = address; // human-readable; stays read-only
//       });
//     } catch (e) {
//       _setTopError('Failed to get location: $e');
//     } finally {
//       if (mounted) setState(() => _locating = false);
//     }
//   }

//   void _addPond() => setState(() => _ponds.add(_PondForm()));
//   void _removePond(int i) {
//     if (_ponds.length == 1) return;
//     setState(() => _ponds.removeAt(i).dispose());
//   }

//   Future<void> _submit() async {
//     FocusScope.of(context).unfocus();
//     _setTopError(null);

//     // sanitize mobile
//     _mobileCtrl.text = _mobileCtrl.text.replaceAll(RegExp(r'[^0-9]'), '');
//     if (_mobileCtrl.text.length > 10) {
//       _mobileCtrl.text = _mobileCtrl.text.substring(0, 10);
//     }

//     // form + ponds validation
//     if (!(_formKey.currentState?.validate() ?? false)) {
//       _setTopError('Please correct the highlighted fields.');
//       return;
//     }
//     for (int i = 0; i < _ponds.length; i++) {
//       final err = _ponds[i].validate();
//       if (err != null) {
//         _setTopError('Pond ${i + 1}: $err');
//         return;
//       }
//     }

//     setState(() => _submitting = true);
//     try {
//       final prefs = await SharedPreferences.getInstance();
//       final companyId = prefs.getString('companyId') ?? '';
//       final employeeId = prefs.getString('userId') ?? '';
//       if (companyId.isEmpty || employeeId.isEmpty) {
//         _setTopError('Missing companyId/employeeId. Please re-login.');
//         return;
//       }

//       final ponds = _ponds.map((p) => p.toJson()).toList();

//       final body = {
//         "name": _nameCtrl.text.trim(),
//         "mobileNumber": _mobileCtrl.text.trim(),
//         "employeeId": employeeId,
//         "companyId": companyId,
//         "address": _addressCtrl.text.trim(),
//         "location":
//             "${(_lat ?? 0).toStringAsFixed(6)} ${(_lng ?? 0).toStringAsFixed(6)}",
//         "totalCultureArea": double.parse(_areaCtrl.text.trim()),
//         "farms": ponds,
//       };

//       debugPrint(
//         "🚀 [Farmers] POST ${AppConfig.farmers}\n"
//         "companyId=$companyId employeeId=$employeeId\n"
//         "address=${body['address']}\n"
//         "location=${body['location']}",
//       );

//       // Send now if online, else enqueue (optimistic)
//       final resp = await apiClient.sendOrQueue(
//         method: HttpVerb.post,
//         path: AppConfig.farmers, // e.g. '/api/farmers'
//         jsonBody: body,
//         // optimisticOk true by default — caller can proceed if queued
//       );

//       if (!mounted) return;

//       if (resp == null) {
//         // Queued (offline or retriable server error). Treat as success for UX.
//         ScaffoldMessenger.of(context).showSnackBar(
//           const SnackBar(
//             content: Text('Saved offline — will sync automatically'),
//             duration: Duration(seconds: 2),
//             behavior: SnackBarBehavior.floating,
//           ),
//         );
//         Navigator.of(context).pop(true);
//         return;
//       }

//       if (resp.statusCode == 200 || resp.statusCode == 201) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           const SnackBar(
//             content: Text('Farmer added successfully!'),
//             duration: Duration(seconds: 2),
//             behavior: SnackBarBehavior.floating,
//           ),
//         );
//         Navigator.of(context).pop(true);
//       } else {
//         String msg = 'HTTP ${resp.statusCode}';
//         try {
//           final d = jsonDecode(resp.body);
//           if (d is Map && d['message'] is String) msg = d['message'];
//         } catch (_) {}
//         _setTopError('Failed to add farmer: $msg');
//       }
//     } catch (e) {
//       _setTopError('Network error: $e');
//     } finally {
//       if (mounted) setState(() => _submitting = false);
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     final bottomInset = MediaQuery.of(context).viewInsets.bottom;
//     return SafeArea(
//       top: false,
//       child: Padding(
//         padding: EdgeInsets.only(
//           left: 16,
//           right: 16,
//           bottom: bottomInset + 12,
//           top: 12,
//         ),
//         child: SingleChildScrollView(
//           keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
//           child: Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               // drag handle
//               Center(
//                 child: Container(
//                   width: 40,
//                   height: 5,
//                   margin: const EdgeInsets.only(bottom: 12),
//                   decoration: BoxDecoration(
//                     color: Colors.grey.withValues(alpha: 0.25),
//                     borderRadius: BorderRadius.circular(3),
//                   ),
//                 ),
//               ),

//               // error bar
//               AnimatedSwitcher(
//                 duration: const Duration(milliseconds: 200),
//                 child: _topError == null
//                     ? const SizedBox.shrink()
//                     : Container(
//                         width: double.infinity,
//                         margin: const EdgeInsets.only(bottom: 10),
//                         padding: const EdgeInsets.symmetric(
//                           horizontal: 12,
//                           vertical: 10,
//                         ),
//                         decoration: BoxDecoration(
//                           color: const Color(0xFFFFE8E8),
//                           borderRadius: BorderRadius.circular(10),
//                           border: Border.all(color: const Color(0xFFFFC2C2)),
//                         ),
//                         child: Row(
//                           crossAxisAlignment: CrossAxisAlignment.start,
//                           children: [
//                             const Icon(
//                               Icons.error_outline,
//                               color: Colors.red,
//                               size: 18,
//                             ),
//                             const SizedBox(width: 8),
//                             Expanded(
//                               child: Text(
//                                 _topError!,
//                                 style: const TextStyle(
//                                   color: Colors.red,
//                                   fontSize: 13.5,
//                                 ),
//                               ),
//                             ),
//                             InkWell(
//                               onTap: () => _setTopError(null),
//                               child: const Icon(
//                                 Icons.close,
//                                 size: 18,
//                                 color: Colors.red,
//                               ),
//                             ),
//                           ],
//                         ),
//                       ),
//               ),

//               const Text(
//                 'Add Farmer',
//                 style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
//               ),
//               const SizedBox(height: 10),

//               Form(
//                 key: _formKey,
//                 child: Column(
//                   children: [
//                     _field(
//                       label: 'Farmer Name',
//                       controller: _nameCtrl,
//                       inputFormatters: _lettersOnly,
//                       textInputAction: TextInputAction.next,
//                       validator: _vName,
//                     ),
//                     _field(
//                       label: 'Mobile Number',
//                       controller: _mobileCtrl,
//                       keyboardType: TextInputType.number,
//                       inputFormatters: _tenDigits,
//                       textInputAction: TextInputAction.next,
//                       validator: _vMobile,
//                       maxLength: 10,
//                       maxLengthEnforcement: MaxLengthEnforcement.enforced,
//                       onChanged: (v) {
//                         final digits = v.replaceAll(RegExp(r'[^0-9]'), '');
//                         final trimmed = digits.length > 10
//                             ? digits.substring(0, 10)
//                             : digits;
//                         if (trimmed != _mobileCtrl.text) {
//                           final sel = trimmed.length;
//                           _mobileCtrl.value = TextEditingValue(
//                             text: trimmed,
//                             selection: TextSelection.collapsed(offset: sel),
//                           );
//                         }
//                       },
//                     ),
//                     Row(
//                       crossAxisAlignment: CrossAxisAlignment.start,
//                       children: [
//                         Expanded(
//                           child: _field(
//                             label: 'Address / Location (auto)',
//                             controller: _addressCtrl,
//                             readOnly: true,
//                             enableInteractiveSelection: false,
//                             validator: (v) => _vRequired(v, 'Location'),
//                           ),
//                         ),
//                         const SizedBox(width: 8),
//                         SizedBox(
//                           height: 48,
//                           child: ElevatedButton.icon(
//                             onPressed: _locating ? null : _getLocation,
//                             style: ElevatedButton.styleFrom(
//                               backgroundColor: appGreen,
//                               foregroundColor: Colors.white,
//                             ),
//                             icon: _locating
//                                 ? const SizedBox(
//                                     height: 16,
//                                     width: 16,
//                                     child: CircularProgressIndicator(
//                                       strokeWidth: 2,
//                                       valueColor: AlwaysStoppedAnimation(
//                                         Colors.white,
//                                       ),
//                                     ),
//                                   )
//                                 : const Icon(Icons.my_location),
//                             label: Text(_locating ? 'Locating…' : 'Get'),
//                           ),
//                         ),
//                       ],
//                     ),
//                     _field(
//                       label: 'Total Culture Area (acres)',
//                       controller: _areaCtrl,
//                       keyboardType: const TextInputType.numberWithOptions(
//                         decimal: true,
//                       ),
//                       inputFormatters: [_oneDotNumber],
//                       textInputAction: TextInputAction.next,
//                       validator: (v) => _vDoublePos(v, 'Total culture area'),
//                     ),

//                     const SizedBox(height: 12),

//                     // Ponds header
//                     Row(
//                       children: [
//                         const Text(
//                           'Ponds',
//                           style: TextStyle(
//                             fontSize: 16,
//                             fontWeight: FontWeight.w800,
//                           ),
//                         ),
//                         const Spacer(),
//                         OutlinedButton.icon(
//                           onPressed: _addPond,
//                           icon: const Icon(Icons.add),
//                           label: const Text('Add Pond'),
//                         ),
//                       ],
//                     ),
//                     const SizedBox(height: 8),

//                     // pond cards
//                     Column(
//                       children: List.generate(_ponds.length, (i) {
//                         final p = _ponds[i];
//                         return _pondCard(
//                           index: i,
//                           pf: p,
//                           onRemove: _ponds.length == 1
//                               ? null
//                               : () => _removePond(i),
//                         );
//                       }),
//                     ),

//                     const SizedBox(height: 14),

//                     SizedBox(
//                       width: double.infinity,
//                       child: ElevatedButton(
//                         onPressed: _submitting ? null : _submit,
//                         style: ElevatedButton.styleFrom(
//                           backgroundColor: appGreen,
//                           foregroundColor: Colors.white,
//                           minimumSize: const Size(double.infinity, 48),
//                           shape: RoundedRectangleBorder(
//                             borderRadius: BorderRadius.circular(12),
//                           ),
//                         ),
//                         child: _submitting
//                             ? const SizedBox(
//                                 height: 20,
//                                 width: 20,
//                                 child: CircularProgressIndicator(
//                                   strokeWidth: 2,
//                                 ),
//                               )
//                             : const Text(
//                                 'Save Farmer',
//                                 style: TextStyle(fontWeight: FontWeight.w700),
//                               ),
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }

//   // Shared field
//   Widget _field({
//     required String label,
//     required TextEditingController controller,
//     String? hint,
//     String? Function(String?)? validator,
//     TextInputType? keyboardType,
//     List<TextInputFormatter>? inputFormatters,
//     TextInputAction? textInputAction,
//     bool readOnly = false,
//     bool enableInteractiveSelection = true,
//     int? maxLength,
//     MaxLengthEnforcement? maxLengthEnforcement,
//     ValueChanged<String>? onChanged,
//   }) {
//     return Padding(
//       padding: const EdgeInsets.only(bottom: 12),
//       child: TextFormField(
//         controller: controller,
//         validator: validator,
//         keyboardType: keyboardType,
//         inputFormatters: inputFormatters,
//         textInputAction: textInputAction,
//         readOnly: readOnly,
//         enableInteractiveSelection: enableInteractiveSelection,
//         maxLength: maxLength,
//         maxLengthEnforcement: maxLengthEnforcement,
//         onChanged: onChanged,
//         buildCounter:
//             (_, {required currentLength, required isFocused, maxLength}) =>
//                 null,
//         decoration: InputDecoration(
//           labelText: label,
//           hintText: hint,
//           filled: true,
//           fillColor: Colors.grey.withValues(alpha: 0.06),
//           contentPadding: const EdgeInsets.symmetric(
//             horizontal: 14,
//             vertical: 12,
//           ),
//           enabledBorder: OutlineInputBorder(
//             borderRadius: BorderRadius.circular(12),
//             borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
//           ),
//           focusedBorder: const OutlineInputBorder(
//             borderRadius: BorderRadius.all(Radius.circular(12)),
//             borderSide: BorderSide(color: Color(0xFF2E7D32), width: 1.4),
//           ),
//           errorBorder: const OutlineInputBorder(
//             borderRadius: BorderRadius.all(Radius.circular(12)),
//             borderSide: BorderSide(color: Colors.red),
//           ),
//           focusedErrorBorder: const OutlineInputBorder(
//             borderRadius: BorderRadius.all(Radius.circular(12)),
//             borderSide: BorderSide(color: Colors.red),
//           ),
//         ),
//       ),
//     );
//   }

//   Widget _pondCard({
//     required int index,
//     required _PondForm pf,
//     VoidCallback? onRemove,
//   }) {
//     final ts = MediaQuery.of(context).textScaleFactor;
//     final double gap = (16 + (ts - 1.0) * 8).clamp(12.0, 24.0);

//     return Container(
//       margin: const EdgeInsets.only(bottom: 12),
//       padding: const EdgeInsets.all(14),
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(12),
//         boxShadow: [
//           BoxShadow(
//             color: Colors.black.withValues(alpha: 0.06),
//             blurRadius: 8,
//             offset: const Offset(0, 2),
//           ),
//         ],
//       ),
//       child: Column(
//         children: [
//           Row(
//             children: [
//               Text(
//                 'Pond ${index + 1}',
//                 style: const TextStyle(
//                   fontWeight: FontWeight.w800,
//                   fontSize: 14,
//                 ),
//               ),
//               const Spacer(),
//               if (onRemove != null)
//                 IconButton(
//                   onPressed: onRemove,
//                   icon: const Icon(Icons.delete_outline, color: Colors.red),
//                 ),
//             ],
//           ),
//           SizedBox(height: gap),
//           _miniField(
//             label: 'Culture Species',
//             controller: pf.species,
//             inputFormatters: AddFarmerBottomSheetStateMix._lettersOnly,
//             validator: (v) {
//               final s = (v ?? '').trim();
//               if (s.isEmpty) return 'Species required';
//               if (!RegExp(r'^[A-Za-z ]+$').hasMatch(s)) {
//                 return 'Letters & spaces only';
//               }
//               return null;
//             },
//           ),
//           SizedBox(height: gap),
//           _miniField(
//             label: 'Stocking Density',
//             controller: pf.density,
//             keyboardType: TextInputType.number,
//             inputFormatters: [FilteringTextInputFormatter.digitsOnly],
//             validator: (v) => _reqInt(v, 'Stocking density'),
//           ),
//           SizedBox(height: gap),
//           _miniField(
//             label: 'Days of Culture',
//             controller: pf.days,
//             keyboardType: TextInputType.number,
//             inputFormatters: [FilteringTextInputFormatter.digitsOnly],
//             validator: (v) => _reqInt(v, 'Days of culture'),
//           ),
//           SizedBox(height: gap),
//           _miniField(
//             label: 'Salinity',
//             controller: pf.salinity,
//             keyboardType: TextInputType.number,
//             inputFormatters: [FilteringTextInputFormatter.digitsOnly],
//             validator: (v) => _reqInt(v, 'Salinity'),
//           ),
//           SizedBox(height: gap),
//           _miniField(
//             label: 'Feed Intake / Day',
//             controller: pf.feed,
//             keyboardType: const TextInputType.numberWithOptions(decimal: true),
//             inputFormatters: [AddFarmerBottomSheetStateMix._oneDot],
//             validator: (v) => _reqDouble(v, 'Feed intake'),
//           ),
//           SizedBox(height: gap),
//           _miniField(
//             label: 'Size / Count (e.g., 20g)',
//             controller: pf.size,
//             validator: (v) =>
//                 (v ?? '').trim().isEmpty ? 'Size/Count is required' : null,
//           ),
//         ],
//       ),
//     );
//   }

//   String? _reqInt(String? v, String label) {
//     final s = (v ?? '').trim();
//     if (s.isEmpty) return '$label is required';
//     if (int.tryParse(s) == null) return 'Enter a valid integer';
//     return null;
//   }

//   String? _reqDouble(String? v, String label) {
//     final s = (v ?? '').trim();
//     if (s.isEmpty) return '$label is required';
//     if (double.tryParse(s) == null) return 'Enter a valid number';
//     return null;
//   }

//   Widget _miniField({
//     required String label,
//     required TextEditingController controller,
//     String? Function(String?)? validator,
//     TextInputType? keyboardType,
//     List<TextInputFormatter>? inputFormatters,
//   }) {
//     return Padding(
//       padding: const EdgeInsets.only(bottom: 8),
//       child: TextFormField(
//         controller: controller,
//         validator: validator,
//         keyboardType: keyboardType,
//         inputFormatters: inputFormatters,
//         decoration: InputDecoration(
//           labelText: label,
//           filled: true,
//           fillColor: Colors.grey.withValues(alpha: 0.06),
//           contentPadding: const EdgeInsets.symmetric(
//             horizontal: 12,
//             vertical: 10,
//           ),
//           enabledBorder: OutlineInputBorder(
//             borderRadius: BorderRadius.circular(10),
//             borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
//           ),
//           focusedBorder: const OutlineInputBorder(
//             borderRadius: BorderRadius.all(Radius.circular(10)),
//             borderSide: BorderSide(color: Color(0xFF2E7D32), width: 1.2),
//           ),
//           errorBorder: const OutlineInputBorder(
//             borderRadius: BorderRadius.all(Radius.circular(10)),
//             borderSide: BorderSide(color: Colors.red),
//           ),
//           focusedErrorBorder: const OutlineInputBorder(
//             borderRadius: BorderRadius.all(Radius.circular(10)),
//             borderSide: BorderSide(color: Colors.red),
//           ),
//         ),
//       ),
//     );
//   }
// }

// tiny mixin to reuse formatters inside pond card
// mixin AddFarmerBottomSheetStateMix {
//   static final List<TextInputFormatter> _lettersOnly = [
//     FilteringTextInputFormatter.allow(RegExp(r"[A-Za-z ]")),
//     LengthLimitingTextInputFormatter(40),
//   ];
//   static final TextInputFormatter _oneDot = TextInputFormatter.withFunction(
//     (oldValue, newValue) =>
//         RegExp(r'^\d*\.?\d*$').hasMatch(newValue.text) ? newValue : oldValue,
//   );
// }

/* ========================= Models & small widgets ========================= */

/* ========================= Pond helper ========================= */

// class _PondForm {
//   final species = TextEditingController();
//   final density = TextEditingController();
//   final days = TextEditingController();
//   final salinity = TextEditingController();
//   final feed = TextEditingController();
//   final size = TextEditingController();

//   String? validate() {
//     if ((species.text).trim().isEmpty) return 'Species required';
//     if (!RegExp(r'^[A-Za-z ]+$').hasMatch(species.text.trim())) {
//       return 'Species: letters & spaces only';
//     }
//     if (int.tryParse(density.text.trim()) == null) {
//       return 'Stocking density must be an integer';
//     }
//     if (int.tryParse(days.text.trim()) == null) {
//       return 'Days of culture must be an integer';
//     }
//     if (int.tryParse(salinity.text.trim()) == null) {
//       return 'Salinity must be an integer';
//     }
//     if (double.tryParse(feed.text.trim()) == null) {
//       return 'Feed intake must be a number';
//     }
//     if ((size.text).trim().isEmpty) return 'Size/Count is required';
//     return null;
//   }

//   Map<String, dynamic> toJson() => {
//     "cultureSpecies": species.text.trim(),
//     "stockingDensity": int.parse(density.text.trim()),
//     "daysOfCulture": int.parse(days.text.trim()),
//     "salinity": int.parse(salinity.text.trim()),
//     "feedIntakePerDay": double.parse(feed.text.trim()),
//     "sizeOrCount": size.text.trim(),
//   };

//   void dispose() {
//     species.dispose();
//     density.dispose();
//     days.dispose();
//     salinity.dispose();
//     feed.dispose();
//     size.dispose();
//   }
// }
