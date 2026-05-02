import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:FieldService_app/config.dart';
import 'package:FieldService_app/main.dart';

class ExpensesListPage extends StatefulWidget {
  const ExpensesListPage({super.key});

  @override
  State<ExpensesListPage> createState() => _ExpensesListPageState();
}

class _ExpensesListPageState extends State<ExpensesListPage> {
  List<dynamic> _expenses = [];
  List<dynamic> _filteredExpenses = [];
  bool _isLoading = true;
  String _searchQuery = '';

  // ---------- Filters ----------
  static const String fAll = 'All';
  static const String fToday = 'Today';
  static const String fYesterday = 'Yesterday';
  static const String fLast7 = 'Last 7 days';
  static const String fThisMonth = 'This Month';
  static const String fLastMonth = 'Last Month';

  late String _selectedFilter = fAll;

  // Totals from API
  final Map<String, num?> _totals = {
    'totalExpense': null,
    'today': null,
    'yesterday': null,
    'last7Days': null,
    'thisMonth': null,
    'lastMonth': null,
  };
  bool _totalsLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchExpenses();
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is int) {
      try {
        return DateTime.fromMillisecondsSinceEpoch(value);
      } catch (_) {
        return null;
      }
    }
    if (value is String) {
      // Try ISO parse first, fallback to common formats if needed
      try {
        return DateTime.tryParse(value);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// Sort list in-place by createdAt descending (newest first)
  void _sortByDateDesc(List<dynamic> list) {
    list.sort((a, b) {
      final da =
          _parseDate(a['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final db =
          _parseDate(b['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0);
      return db.compareTo(da); // descending
    });
  }

  Future<void> _fetchExpenses() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final employeeId = prefs.getString('userId') ?? '';

      if (employeeId.isEmpty) {
        throw Exception("Missing employee ID");
      }

      setState(() {
        _isLoading = true;
        _totalsLoading = true;
      });

      // 🔥 USE CACHED GET
      final result = await apiClient.getJsonCached(
        path: AppConfig.expenseUploadByEmployeeId.replaceAll(
          '{id}',
          employeeId,
        ),
        cacheKey: 'expenses_$employeeId',
        ttl: const Duration(minutes: 30),
      );

      final data = result.data;

      // Handle success response (new format with totals + expenses)
      if (data is Map && data['success'] == true) {
        // totals may be present
        if (data['totals'] is Map) {
          final t = Map<String, dynamic>.from(data['totals']);
          _totals['totalExpense'] = _numFromDynamic(t['totalExpense']);
          _totals['today'] = _numFromDynamic(t['today']);
          _totals['yesterday'] = _numFromDynamic(t['yesterday']);
          _totals['last7Days'] = _numFromDynamic(t['last7Days']);
          _totals['thisMonth'] = _numFromDynamic(t['thisMonth']);
          _totals['lastMonth'] = _numFromDynamic(t['lastMonth']);
        }

        final list = List.from(data['expenses'] ?? data['expensesList'] ?? []);

        // treat missing list as empty
        if (list.isEmpty) {
          setState(() {
            _expenses = [];
            _filteredExpenses = [];
            _isLoading = false;
            _totalsLoading = false;
          });
          return;
        }

        _sortByDateDesc(list);

        setState(() {
          _expenses = list;
          // apply currently selected filter immediately
          _applyFilter(); // sets _filteredExpenses
          _isLoading = false;
          _totalsLoading = false;
        });
      } else if (result.data == 404 || data?['message'] == 'Not found') {
        setState(() {
          _expenses = [];
          _filteredExpenses = [];
          _isLoading = false;
          _totalsLoading = false;
        });
      } else {
        throw Exception("Invalid response");
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _totalsLoading = false;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }

  num? _numFromDynamic(dynamic v) {
    if (v == null) return null;
    if (v is num) return v;
    return num.tryParse(v.toString());
  }

  /// Compute a start/end DateTime range for the currently selected filter.
  /// Returns pair (start, end) where both inclusive. If filter == All returns (null, null).
  Pair<DateTime?, DateTime?> _rangeForFilter(String filter) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (filter == fAll) return Pair(null, null);
    if (filter == fToday) return Pair(today, today);
    if (filter == fYesterday) {
      final y = today.subtract(const Duration(days: 1));
      return Pair(y, y);
    }
    if (filter == fLast7) {
      final start = today.subtract(
        const Duration(days: 6),
      ); // last 7 days including today
      return Pair(start, today);
    }
    if (filter == fThisMonth) {
      final start = DateTime(now.year, now.month, 1);
      final next = DateTime(now.year, now.month + 1, 1);
      final end = next.subtract(const Duration(milliseconds: 1));
      return Pair(start, end);
    }
    if (filter == fLastMonth) {
      final firstOfThis = DateTime(now.year, now.month, 1);
      final lastMonthEnd = firstOfThis.subtract(
        const Duration(milliseconds: 1),
      );
      final start = DateTime(lastMonthEnd.year, lastMonthEnd.month, 1);
      final end = DateTime(
        lastMonthEnd.year,
        lastMonthEnd.month,
        lastMonthEnd.day,
        23,
        59,
        59,
        999,
      );
      return Pair(start, end);
    }
    return Pair(null, null);
  }

  void _applyFilter() {
    // apply both selected filter range and text search
    final range = _rangeForFilter(_selectedFilter);

    final start = range.first;
    final end = range.second;

    final q = _searchQuery.trim().toLowerCase();

    List<dynamic> filtered = _expenses.where((exp) {
      final remark = (exp['remark'] ?? '').toString().toLowerCase();
      final rawDate = _parseDate(exp['createdAt']);
      // if parsed date is null, keep the item only if filter is All
      if (start != null || end != null) {
        if (rawDate == null) return false;
        // compare using local date values (strip time)
        final d = DateTime(rawDate.year, rawDate.month, rawDate.day);
        // inclusive comparison
        if (start != null &&
            d.isBefore(DateTime(start.year, start.month, start.day))) {
          return false;
        }
        if (end != null && d.isAfter(DateTime(end.year, end.month, end.day))) {
          return false;
        }
      }

      final matchesText = q.isEmpty || remark.contains(q);
      return matchesText;
    }).toList();

    _sortByDateDesc(filtered);

    setState(() => _filteredExpenses = filtered);
  }

  void _onFilterTap(String filter) {
    if (_selectedFilter == filter) return;
    setState(() {
      _selectedFilter = filter;
    });
    _applyFilter();
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '';
    final date = _parseDate(dateStr);

    if (date != null) {
      // ➕ Add 5 hours 30 minutes for display (IST)
      final adjusted = date.add(const Duration(hours: 5, minutes: 30));
      return DateFormat('dd MMM yyyy, hh:mm a').format(adjusted);
    }

    return '';
  }

  String _totalTextForSelectedFilter() {
    // Map our filter names to totals keys returned by the API
    final map = {
      fAll: 'totalExpense',
      fToday: 'today',
      fYesterday: 'yesterday',
      fLast7: 'last7Days',
      fThisMonth: 'thisMonth',
      fLastMonth: 'lastMonth',
    };
    final key = map[_selectedFilter];
    if (key == null) return '--';
    final val = _totals[key];
    if (val == null) return '--';
    // show integer without decimals if whole, otherwise two decimals
    try {
      if (val % 1 == 0) {
        return val.toStringAsFixed(0);
      }
    } catch (_) {}
    return val.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF9),
      appBar: PreferredSize(
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
            centerTitle: true,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_sharp, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
            ),
            title: const Text(
              'My Expenses',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
                fontSize: 20,
                shadows: [
                  Shadow(
                    offset: Offset(1, 1), // Direction of shadow
                    blurRadius: 4, // Softness of shadow
                    color: Colors.black38, // Shadow color
                  ),
                ],
              ),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 14),
                child: _totalsLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                          strokeWidth: 2,
                        ),
                      )
                    : Row(
                        children: [
                          const Icon(
                            Icons.account_balance_wallet_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _totalTextForSelectedFilter(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          // Filters chips row
          _buildFiltersRow(), // <—— ADD HERE
          // Padding(
          //   padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          //   child: SizedBox(
          //     height: 48,
          //     child: ListView.separated(
          //       scrollDirection: Axis.horizontal,
          //       padding: const EdgeInsets.symmetric(horizontal: 6),
          //       separatorBuilder: (_, __) => const SizedBox(width: 8),
          //       itemCount: 6,
          //       itemBuilder: (ctx, i) {
          //         final filters = [
          //           fAll,
          //           fToday,
          //           fYesterday,
          //           fLast7,
          //           fThisMonth,
          //           fLastMonth,
          //         ];
          //         final filter = filters[i];
          //         final selected = _selectedFilter == filter;
          //         return ChoiceChip(
          //           label: Text(filter),
          //           selected: selected,
          //           onSelected: (_) => _onFilterTap(filter),
          //           selectedColor: const Color(0xFF2E7D32),
          //           backgroundColor: Colors.white,
          //           labelStyle: TextStyle(
          //             color: selected ? Colors.white : const Color(0xFF2E7D32),
          //             fontWeight: FontWeight.w600,
          //           ),
          //           padding: const EdgeInsets.symmetric(
          //             horizontal: 14,
          //             vertical: 8,
          //           ),
          //         );
          //       },
          //     ),
          //   ),
          // ),

          // top controls: search + date range picker row (kept original search)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Expanded Search
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: 'Search remarks...',
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),

                      // 🔽 NOT focused border
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(
                          color: Color(0xFF1AB69C),
                          width: 1.5,
                        ),
                      ),

                      // 🔽 FOCUSED border (when user taps the field)
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(
                          color: Color(0xFF1AB69C),
                          width: 2.0,
                        ),
                      ),

                      // 🔽 Default border
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(
                          color: Color(0xFF1AB69C),
                          width: 1.5,
                        ),
                      ),
                    ),
                    onChanged: (val) {
                      setState(() => _searchQuery = val);
                      _applyFilter();
                    },
                  ),
                ),

                const SizedBox(width: 10),
              ],
            ),
          ),

          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF2E7D32)),
                  )
                : _filteredExpenses.isEmpty
                ? const Center(
                    child: Text(
                      "No expenses found.",
                      style: TextStyle(color: Colors.grey, fontSize: 16),
                    ),
                  )
                : RefreshIndicator(
                    color: const Color(0xFF2E7D32),
                    onRefresh: _fetchExpenses,
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      itemCount: _filteredExpenses.length,
                      itemBuilder: (context, index) {
                        final exp = _filteredExpenses[index];
                        final imageUrl =
                            exp['image'] != null && exp['image'].isNotEmpty
                                ? AppConfig.imageUrl(exp['image'].toString())
                                : null;

                        final amount = exp['amount']?.toString() ?? '--';

                        return GestureDetector(
                          onTap: () {
                            if (imageUrl != null && imageUrl.isNotEmpty) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => _ExpenseImagePreview(
                                    imageUrl: imageUrl,
                                    remark: exp['remark'] ?? 'No Remark',
                                    date: _formatDate(exp['createdAt']),
                                  ),
                                ),
                              );
                            }
                          },
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),

                              // ✅ Add border here
                              border: Border.all(
                                color: const Color(0xFF1AB69C),
                                width: 1.5,
                              ),

                              boxShadow: [
                                BoxShadow(
                                  color: Colors.grey.withValues(
                                    alpha: 0.15,
                                  ), // fix
                                  blurRadius: 6,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),

                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(16),
                                    bottomLeft: Radius.circular(16),
                                  ),
                                  child: SizedBox(
                                    width: 100,
                                    height: 100,
                                    child: imageUrl != null
                                        ? CachedNetworkImage(
                                            imageUrl: imageUrl,
                                            fit: BoxFit.cover,
                                            placeholder: (_, _) => Container(
                                              color: Colors.grey.shade300,
                                              child: const Center(
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              ),
                                            ),
                                            errorWidget: (_, _, _) => Container(
                                              color: Colors.grey.shade200,
                                              child: const Icon(
                                                Icons.broken_image,
                                                color: Colors.grey,
                                              ),
                                            ),
                                          )
                                        : Container(
                                            width: 100,
                                            height: 100,
                                            color: Colors.grey.shade100,
                                            child: const Icon(
                                              Icons.receipt_long_rounded,
                                              color: Colors.grey,
                                            ),
                                          ),
                                  ),
                                ),

                                // 📝 Details
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 10,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                exp['remark'] ?? 'No Remarks',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 15,
                                                  color: Colors.black87,
                                                ),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 6,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF1AB69C),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: Text(
                                                "₹$amount",
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          _formatDate(exp['createdAt']),
                                          style: const TextStyle(
                                            color: Colors.grey,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFiltersRow() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [fAll, fToday, fYesterday, fLast7, fThisMonth, fLastMonth]
              .map((filter) {
                final isSelected = _selectedFilter == filter;
                return Container(
                  margin: const EdgeInsets.only(right: 12),
                  child: GestureDetector(
                    onTap: () => _onFilterTap(filter),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFF2EB9AC)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(25),
                        border: Border.all(
                          color: isSelected
                              ? const Color(
                                  0xFF2E7D32,
                                ) // appGreen same as Trips
                              : Colors.grey[300]!,
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
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.normal,
                          color: isSelected ? Colors.white : Colors.grey[700],
                        ),
                      ),
                    ),
                  ),
                );
              })
              .toList(),
        ),
      ),
    );
  }
}

/// Simple Pair helper (small utility for returning two values)
class Pair<A, B> {
  final A first;
  final B second;
  Pair(this.first, this.second);
}

class _ExpenseImagePreview extends StatelessWidget {
  final String imageUrl;
  final String remark;
  final String date;

  const _ExpenseImagePreview({
    required this.imageUrl,
    required this.remark,
    required this.date,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Expense Preview',
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: Center(
        child: Column(
          children: [
            Expanded(
              child: Hero(
                tag: imageUrl,
                child: CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.contain,
                  errorWidget: (_, _, _) => const Icon(
                    Icons.broken_image,
                    color: Colors.white54,
                    size: 100,
                  ),
                ),
              ),
            ),
            Container(
              width: double.infinity,
              color: Colors.black.withValues(alpha: 0.7),
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    remark,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    date,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
