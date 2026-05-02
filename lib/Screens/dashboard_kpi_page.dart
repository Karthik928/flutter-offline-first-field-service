// dashboard_kpi_page.dart
// Rewritten: shows KPIs + charts (Counts bar, Speedometer, Category Pie)
// Requires: fl_chart, http, shared_preferences, your AppConfig + apiClient cache

import 'dart:convert';
import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:FieldService_app/config.dart';
import 'package:FieldService_app/main.dart';
import 'package:FieldService_app/offline/cache_store.dart';
import 'package:FieldService_app/services/secure_storage_service.dart';

class DashboardKpiPage extends StatefulWidget {
  const DashboardKpiPage({super.key});

  @override
  State<DashboardKpiPage> createState() => _DashboardKpiPageState();
}

class _DashboardKpiPageState extends State<DashboardKpiPage>
    with TickerProviderStateMixin {
  final Color _primary = const Color(0xFF1AB69C);

  bool _loading = true;
  DashboardSummary? _summary;

  // Chart state (pie + speedometer)
  bool _isIncentivesLoading = true;
  Map<String, double>? _incentivesData;
  String? _focusedLabel;
  double? _focusedValue;

  final bool _showSpeedometerInfo = true;
  final Duration _gaugeAnimDuration = const Duration(milliseconds: 900);

  double _salesValue = 0.0;
  double _revenueValue = 0.0;
  double _targetValue = 1.0; // avoid divide-by-zero

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<Map<String, String>> _headers({bool json = false}) async {
    //final prefs = await SharedPreferences.getInstance();
    final token = await SecureStorageService.getToken();
    return {
      'Accept': 'application/json',
      if (json) 'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _isIncentivesLoading = true;
    });

    try {
      final data = await fetchDashboardSummary(_headers);
      if (!mounted) return;

      // Sync local chart values from summary (safe parsing)
      final sales = double.tryParse(data.salesAmount ?? '0') ?? 0.0;
      final received = double.tryParse(data.receivedAmount ?? '0') ?? 0.0;
      double yearlyTarget = double.tryParse(data.yearlyTarget ?? '') ?? 0.0;

      // ✅ FINAL fallback rule
      if (yearlyTarget <= 0) {
        yearlyTarget = 100000; // DEFAULT TARGET
      }

      final categories = data.categoryWiseSales ?? {};

      setState(() {
        _summary = data;
        _salesValue = sales;
        _revenueValue = received;
        _targetValue = yearlyTarget;
        _incentivesData = categories;
        _isIncentivesLoading = false;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _isIncentivesLoading = false;
      });
    }
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,

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
            automaticallyImplyLeading: false,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
            ),
            title: const Text(
              'Reports & Summaries',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
                fontSize: 20,
              ),
            ),
            centerTitle: true,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_sharp, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ),
      ),

      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_summary == null || _summary!.isEmpty)
          ? const Center(
              child: Text(
                "No Data Found",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black54,
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              color: _primary,
              child: ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  _sectionTitle('Counts'),
                  _buildCountsRadialChart(
                    dealers: _summary!.dealersCount,
                    farmers: _summary!.farmersCount,
                    dealerTickets: _summary!.dealerTicketsCount,
                    farmerTickets: _summary!.farmerTicketsCount,
                  ),

                  const SizedBox(height: 18),

                  _sectionTitle('Performance'),
                  _buildPerformanceRow(),

                  const SizedBox(height: 18),

                  _sectionTitle('Category Sales'),
                  _buildCategorySection(),
                ],
              ),
            ),
    );
  }

  Widget _buildPerformanceRow() {
    final isCompact = MediaQuery.of(context).size.width < 420;

    return _buildVehicleSpeedometer(
      salesValue: _salesValue,
      revenueValue: _revenueValue,
      maxValue: _targetValue,
      compact: isCompact,
    );
  }

  Widget _buildCategorySection() {
    if (_isIncentivesLoading) return _buildPieSkeleton();
    if (_incentivesData == null ||
        _incentivesData!.values.every((v) => v == 0)) {
      return _buildEmptyPieCard();
    }

    // Use the same pie implementation below (_buildIncentivesPieCard).
    return _buildIncentivesPieCard(compact: false);
  }

  // ---------- UI HELPERS (cards / grid) ----------

  Widget _sectionTitle(String t) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
      child: Text(
        t,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    );
  }

  // ----------------- Charts & helper widgets -----------------

  // NEW: Replace the whole CountsBar(...) with this implementation
  // NEW: Replace CountsBar entirely with this

  Widget _buildCountsRadialChart({
    required int dealers,
    required int farmers,
    required int dealerTickets,
    required int farmerTickets,
  }) {
    final items = [
      ('No. of Dealers', dealers, const Color(0xFF1AB69C)),
      ('No. of Farmers', farmers, const Color(0xFF4CAF50)),
      ('Dealer Queries Raised', dealerTickets, const Color(0xFFFFC107)),
      ('Farmer Queries Raised', farmerTickets, const Color(0xFFF44336)),
    ];

    final maxValue = items
        .map((e) => e.$2)
        .fold<int>(1, (a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF1AB69C).withValues(alpha: 0.10),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          SizedBox(
            height: 200,
            child: PieChart(
              PieChartData(
                startDegreeOffset: -90,
                centerSpaceRadius: 46,
                sectionsSpace: 2,
                sections: List.generate(items.length, (i) {
                  final value = items[i].$2.toDouble();
                  final ratio = maxValue == 0 ? 0.0 : value / maxValue;

                  return PieChartSectionData(
                    value: ratio <= 0 ? 0.01 : ratio,
                    color: items[i].$3,
                    radius: 64 - (i * 8), // 👈 concentric rings
                    title: '',
                  );
                }),
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Legend
          Column(
            children: items.map((e) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: e.$3,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          e.$1,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      e.$2.toString(),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget countsBar({
    required int dealers,
    required int farmers,
    required int dealerTickets,
    required int farmerTickets,
  }) {
    final items = [
      ('Dealers', dealers, const Color(0xFF50C6B4)),
      ('Farmers', farmers, const Color(0xFF1AB69C)),
      ('Dealer Tickets', dealerTickets, const Color(0xFFFFC107)),
      ('Farmer Tickets', farmerTickets, const Color(0xFFF44336)),
    ];

    final maxVal = items.map((e) => e.$2).fold<int>(1, (a, b) => a > b ? a : b);

    String fmt(int v) {
      if (v >= 1e6) return '${(v / 1e6).toStringAsFixed(1)}M';
      if (v >= 1e3) return '${(v / 1e3).toStringAsFixed(1)}K';
      return v.toString();
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _primary.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: items.map((e) {
          final label = e.$1;
          final value = e.$2;
          final color = e.$3;

          final ratio = maxVal == 0 ? 0.0 : value / maxVal;

          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Label + Value row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      fmt(value),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                // Progress bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: ratio.clamp(0.0, 1.0),
                    minHeight: 8,
                    backgroundColor: color.withValues(alpha: 0.15),
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // ---------------- The Pie Chart you provided (unchanged) ----------------
  Widget _buildIncentivesPieCard({bool compact = false}) {
    if (_isIncentivesLoading) return _buildPieSkeleton();

    if (_incentivesData == null ||
        _incentivesData!.values.every((v) => v == 0)) {
      return _buildEmptyPieCard();
    }

    // Visual color palette (kept small & consistent)
    final colors = [
      const Color(0xFF1E88E5), // blue
      const Color(0xFFFFC107), // yellow
      const Color(0xFF43A047), // green
      const Color(0xFF64B5F6), // light blue
      const Color(0xFFE91E63), // pink
    ];

    // Sort descending so largest slice anchors at top
    final entries = _incentivesData!.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final total = entries.fold<double>(0.0, (p, e) => p + e.value);

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Chart
            Center(
              child: SizedBox(
                width: compact ? 115 : 140,
                height: compact ? 115 : 140,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Decorative ring + Pie
                    DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: PieChart(
                        PieChartData(
                          centerSpaceRadius: 0,
                          sectionsSpace: 2,
                          startDegreeOffset: -90,
                          pieTouchData: PieTouchData(
                            touchCallback: (event, response) {
                              if (!event.isInterestedForInteractions ||
                                  response == null ||
                                  response.touchedSection == null) {
                                setState(() {
                                  _focusedLabel = null;
                                  _focusedValue = null;
                                });
                                return;
                              }

                              final int index =
                                  response.touchedSection!.touchedSectionIndex;
                              if (index < 0 || index >= entries.length) {
                                setState(() {
                                  _focusedLabel = null;
                                  _focusedValue = null;
                                });
                                return;
                              }

                              final entry = entries[index];
                              setState(() {
                                _focusedLabel = entry.key;
                                _focusedValue = entry.value;
                              });
                            },
                          ),
                          sections: List.generate(entries.length, (i) {
                            final value = entries[i].value;
                            final percent = total > 0
                                ? (value / total * 100)
                                : 0.0;

                            return PieChartSectionData(
                              value: value,
                              color: colors[i % colors.length],
                              radius: compact ? 60 : 70,
                              title: '${percent.toStringAsFixed(0)}%',
                              titleStyle: TextStyle(
                                fontSize: compact ? 11 : 13,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                              titlePositionPercentageOffset: 0.60,
                            );
                          }),
                        ),
                      ),
                    ),

                    // CENTER overlay when a slice is focused
                    if (_focusedLabel != null && _focusedValue != null)
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.96),
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.06),
                                blurRadius: 6,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _focusedLabel!,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _focusedValue!.toStringAsFixed(0),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black,
                                ),
                              ),
                              Text(
                                "(${((_focusedValue! / total) * 100).toStringAsFixed(0)}%)",
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.black54,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildPieSkeleton() {
    return Container(
      height: 180,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(20),
      ),
    );
  }

  Widget _buildEmptyPieCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF1AB69C), width: 1.0),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1AB69C).withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: const Center(
        child: Text(
          "No category sales available",
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.black54,
          ),
        ),
      ),
    );
  }

  // ---------------- The Speedometer you provided (kept intact) ----------------
  // NOTE: small adaptions only so it compiles inside this state class:
  Map<String, dynamic>? _overTargetStatusFor(double value, double maxValue) {
    if (maxValue <= 0) return null;
    final ratio = value / maxValue;
    if (ratio <= 1.0) return null;
    final overPercent = (ratio - 1.0) * 100.0;
    return {'label': 'Over', 'ratio': ratio, 'overPercent': overPercent};
  }

  Widget _buildVehicleSpeedometer({
    required double salesValue,
    required double revenueValue,
    required double maxValue,
    bool compact = false,
  }) {
    // Actual (can exceed 100%)
    final double actualSalesPercent = maxValue == 0
        ? 0.0
        : (salesValue / maxValue);

    final double actualRevenuePercent = maxValue == 0
        ? 0.0
        : (revenueValue / maxValue);

    // compute over-target state (sales or revenue)
    final salesStatus = _overTargetStatusFor(salesValue, maxValue);
    final revenueStatus = _overTargetStatusFor(revenueValue, maxValue);

    // choose which metric to show badge for (prefer the larger ratio)
    Map<String, dynamic>? chosenStatus;
    if (salesStatus != null && revenueStatus != null) {
      chosenStatus = (salesStatus['ratio'] >= revenueStatus['ratio'])
          ? salesStatus
          : revenueStatus;
    } else {
      chosenStatus = salesStatus ?? revenueStatus;
    }

    final bool isOver = chosenStatus != null;

    // clamp visual needle values — needles visually capped at 100%
    final double clampedSales = salesValue.clamp(0.0, maxValue);
    final double clampedRevenue = revenueValue.clamp(0.0, maxValue);

    final double salesProgress = maxValue == 0
        ? 0.0
        : (clampedSales / maxValue).clamp(0.0, 1.0);
    final double revenueProgress = maxValue == 0
        ? 0.0
        : (clampedRevenue / maxValue).clamp(0.0, 1.0);

    final double padding = compact ? 8.0 : 12.0;

    // AnimatedContainer for glow - hardware accelerated shadow animation
    return AnimatedContainer(
      duration: const Duration(milliseconds: 420),
      //padding: EdgeInsets.all(padding),
      padding: EdgeInsets.only(
        left: padding + 5,
        right: padding + 5,
        top: padding,
        bottom: padding + 6,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF1AB69C), width: 1.0),
        boxShadow: isOver
            ? [
                // subtle glow, not expensive
                BoxShadow(
                  color: const Color(0xFF1AB69C).withValues(alpha: 0.16),
                  blurRadius: 22,
                  spreadRadius: 2,
                  offset: const Offset(0, 8),
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _legendDot(
                      label: "Sales",
                      color: const Color.fromARGB(221, 197, 4, 4),
                    ),
                    _legendDot(
                      label: "Revenue",
                      color: const Color(0xFF1AB69C),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 50),
                // child: Text(
                //   _showSpeedometerInfo
                //       ? "Tap to hide details"
                //       : "Tap gauge for details",
                //   style: TextStyle(
                //     fontSize: 11,
                //     fontWeight: FontWeight.w600,
                //     color: Colors.black45,
                //   ),
                // ),
              ),
              //const SizedBox(height: 40),
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                // onTap: () {
                //   setState(() {
                //     _showSpeedometerInfo = !_showSpeedometerInfo;
                //   });
                // },
                child: SizedBox(
                  height: compact ? 140 : 160,
                  child: Padding(
                    padding: EdgeInsets.only(top: 24, left: 6.0, right: 6.0),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final size = Size(
                          constraints.maxWidth,
                          constraints.maxHeight,
                        );
                        return RepaintBoundary(
                          // reduces paint cost when parent rebuilds
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // Arc is static unless maxValue changes; we don't animate it
                              CustomPaint(
                                size: size,
                                painter: _SpeedometerArcPainter(
                                  maxValue: maxValue,
                                ),
                              ),
                              // Use TweenAnimationBuilder for each needle — smooth + low-cost.
                              TweenAnimationBuilder<double>(
                                tween: Tween(begin: 0.0, end: salesProgress),
                                duration: _gaugeAnimDuration,
                                curve: Curves.easeOutCubic,
                                builder: (context, animSales, _) {
                                  return CustomPaint(
                                    size: size,
                                    painter: _SpeedometerNeedlePainter(
                                      animSales,
                                      color: const Color.fromARGB(
                                        221,
                                        197,
                                        4,
                                        4,
                                      ),
                                      thicknessFactor: 0.28,
                                    ),
                                  );
                                },
                              ),
                              TweenAnimationBuilder<double>(
                                tween: Tween(begin: 0.0, end: revenueProgress),
                                duration: _gaugeAnimDuration,
                                curve: Curves.easeOutCubic,
                                builder: (context, animRevenue, _) {
                                  return CustomPaint(
                                    size: size,
                                    painter: _SpeedometerNeedlePainter(
                                      animRevenue,
                                      color: const Color(0xFF1AB69C),
                                      thicknessFactor: 0.50,
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeInOut,
                child: _showSpeedometerInfo
                    ? Container(
                        margin: const EdgeInsets.only(top: 12),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.black12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _speedInfoBlock(
                              label: "Sales",
                              value: salesValue, // ✅ ACTUAL VALUE
                              percent: actualSalesPercent, // ✅ CAN EXCEED 100%
                              color: Colors.black87,
                            ),
                            _speedInfoBlock(
                              label: "Revenue",
                              value: revenueValue, // ✅ ACTUAL VALUE
                              percent:
                                  actualRevenuePercent, // ✅ CAN EXCEED 100%
                              color: const Color(0xFF1AB69C),
                            ),

                            _speedInfoBlock(
                              label: "Target",
                              value: maxValue,
                              percent: null,
                              color: Colors.black54,
                            ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),

          // Badge positioned top-right (absolute)
          if (isOver)
            Positioned(
              right: -8,
              top: -10,
              child: _buildTargetBadge(
                label: chosenStatus['label'] as String,
                overPercent: chosenStatus['overPercent'] as double,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTargetBadge({
    required String label,
    required double overPercent,
  }) {
    final display = overPercent <= 0
        ? ''
        : ' +${overPercent.toStringAsFixed(0)}%';
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(12),
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF1AB69C),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.emoji_events, size: 16, color: Colors.white),
            const SizedBox(width: 6),
            Text(
              '$label$display',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _speedInfoBlock({
    required String label,
    required double value,
    required double? percent,
    required Color color,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min, // 👈 important
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Colors.black54,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value % 1 == 0 ? value.toInt().toString() : value.toStringAsFixed(1),
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        if (percent != null)
          Text(
            percent <= 1
                ? "${(percent * 100).toStringAsFixed(0)}%"
                : "+${((percent - 1) * 100).toStringAsFixed(0)}%",
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: percent > 1 ? const Color(0xFF1AB69C) : Colors.black45,
            ),
          ),
      ],
    );
  }

  Widget _legendDot({required String label, required Color color}) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }
}

// ---------------- Custom Painters for speedometer (kept behavior) ----------------
class _SpeedometerArcPainter extends CustomPainter {
  final double maxValue;

  _SpeedometerArcPainter({required this.maxValue});
  @override
  void paint(Canvas canvas, Size size) {
    // ---- Geometry ----
    final strokeWidth = (size.width * 0.12).clamp(8.0, 20.0);
    final radius = (size.width / 2) - strokeWidth * 0.6;

    // Push arc higher so semicircle fills top
    final center = Offset(size.width / 2, size.height * 0.95);

    const startAngle = pi; // left
    const sweepAngle = pi; // 180°

    final arcRect = Rect.fromCircle(center: center, radius: radius);

    // ---- Color zones (Low ➜ High) ----
    final thresholds = [0.35, 0.6, 0.8, 1.0];
    final colors = const [
      Color(0xFFF44336),
      Color(0xFFFF9800),
      Color(0xFFFFEB3B),
      Color(0xFF4CAF50),
    ];

    // ---- Main segmented arc ----
    const int segments = 42;
    for (int i = 0; i < segments; i++) {
      final fracStart = i / segments;
      final fracSweep = 1 / segments;

      Color segColor = colors.last;
      for (int t = 0; t < thresholds.length; t++) {
        if (fracStart <= thresholds[t]) {
          segColor = colors[t];
          break;
        }
      }

      final paint = Paint()
        ..color = segColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(
        arcRect,
        startAngle + sweepAngle * fracStart,
        sweepAngle * fracSweep,
        false,
        paint,
      );
    }

    // ---- Tick marks ----
    final minorTickPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.12)
      ..strokeWidth = 1.0;

    final majorTickPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.45)
      ..strokeWidth = 2.6;

    const int majorDivisions = 10;
    for (int i = 0; i <= majorDivisions; i++) {
      final frac = i / majorDivisions;
      final angle = startAngle + sweepAngle * frac;

      final outer = Offset(
        center.dx + (radius + strokeWidth * 0.20) * cos(angle),
        center.dy + (radius + strokeWidth * 0.20) * sin(angle),
      );

      final inner = Offset(
        center.dx + (radius - strokeWidth * 0.45) * cos(angle),
        center.dy + (radius - strokeWidth * 0.45) * sin(angle),
      );

      canvas.drawLine(inner, outer, majorTickPaint);

      if (i < majorDivisions) {
        for (int m = 1; m <= 3; m++) {
          final subFrac = (i + m / 4) / majorDivisions;
          final subAngle = startAngle + sweepAngle * subFrac;

          final so = Offset(
            center.dx + (radius + strokeWidth * 0.16) * cos(subAngle),
            center.dy + (radius + strokeWidth * 0.16) * sin(subAngle),
          );
          final si = Offset(
            center.dx + (radius - strokeWidth * 0.30) * cos(subAngle),
            center.dy + (radius - strokeWidth * 0.30) * sin(subAngle),
          );

          canvas.drawLine(si, so, minorTickPaint);
        }
      }
    }

    // ---- Numeric labels (0 … target) ----
    final labelStyle = TextStyle(
      color: Colors.black54,
      fontSize: (size.width * 0.025).clamp(8.0, 12.0),
      fontWeight: FontWeight.w600,
    );

    final stepValue = maxValue / majorDivisions;

    String fmt(double v) {
      if (v >= 1e7) return '${(v / 1e7).toStringAsFixed(1)}Cr';
      if (v >= 1e5) return '${(v / 1e5).toStringAsFixed(1)}L';
      if (v >= 1e3) return '${(v / 1e3).toStringAsFixed(1)}K';
      return v.toInt().toString();
    }

    final normalOffset = strokeWidth * 0.9;
    final edgeExtra = strokeWidth * 0.15;
    final edgeDrop = strokeWidth * 0.45;

    for (int i = 0; i <= majorDivisions; i++) {
      final frac = i / majorDivisions;
      final angle = startAngle + sweepAngle * frac;

      final bool isStart = i == 0;
      final bool isEnd = i == majorDivisions;

      final tp = TextPainter(
        text: TextSpan(text: fmt(stepValue * i), style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();

      final arcPoint = Offset(
        center.dx + radius * cos(angle),
        center.dy + radius * sin(angle),
      );

      final normal = Offset(cos(angle), sin(angle));
      final tangent = Offset(-sin(angle), cos(angle));

      final double extraOffset = isStart
          ? edgeExtra
          : isEnd
          ? edgeExtra + 7
          : 5;

      Offset labelCenter = arcPoint + normal * (normalOffset + extraOffset);

      if (isStart || isEnd) {
        labelCenter += tangent * (tp.width * (isStart ? 2 : -0.45));
        labelCenter = labelCenter.translate(0, edgeDrop);
      }

      final dx = isStart
          ? labelCenter.dx
          : isEnd
          ? labelCenter.dx - tp.width
          : labelCenter.dx - tp.width / 2;

      final dy = labelCenter.dy - tp.height / 2;

      tp.paint(canvas, Offset(dx, dy));
    }

    // ---- Subtle outer finish ring ----
    final outerRingPaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.06)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius + strokeWidth * 0.55),
      startAngle,
      sweepAngle,
      false,
      outerRingPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _SpeedometerArcPainter old) {
    return old.maxValue != maxValue;
  }
}

class _SpeedometerNeedlePainter extends CustomPainter {
  final double progress;
  final Color color;
  final double thicknessFactor;

  _SpeedometerNeedlePainter(
    this.progress, {
    required this.color,
    required this.thicknessFactor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final baseStroke = (size.width * 0.12).clamp(8.0, 20.0);
    final radius = (size.width / 2) - baseStroke * 0.6;

    // ✅ SAME center as arc painter
    final center = Offset(size.width / 2, size.height * 0.95);

    // ✅ EXACT mapping: 0 → left, 1 → right
    final p = progress.clamp(0.0, 1.0);
    final angle = pi + (pi * p);

    final stroke = (baseStroke * thicknessFactor).clamp(1.8, 10.0);

    final paint = Paint()
      ..color = color
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    final end = Offset(
      center.dx + radius * 0.90 * cos(angle),
      center.dy + radius * 0.90 * sin(angle),
    );

    canvas.drawLine(center, end, paint);

    // pivot
    // ---- CENTER HUB / JOINT POINT ----

    // Outer hub ring
    final outerRadius = (baseStroke * 0.22).clamp(6.0, 12.0);
    canvas.drawCircle(
      center,
      outerRadius,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.12)
        ..style = PaintingStyle.fill,
    );

    // Inner hub (main dot)
    final innerRadius = outerRadius * 0.55;
    canvas.drawCircle(
      center,
      innerRadius,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill,
    );

    // Optional tiny center pin (adds realism)
    canvas.drawCircle(center, innerRadius * 0.35, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _SpeedometerNeedlePainter old) {
    return old.progress != progress ||
        old.color != color ||
        old.thicknessFactor != thicknessFactor;
  }
}

// -------------------- End speedometer painters --------------------

// -------------------- Data fetching + model --------------------

class DashboardSummary {
  final int dealersCount;
  final int farmersCount;
  final int dealerTicketsCount;
  final int farmerTicketsCount;
  final int totalOrders;
  final int deliveredOrders;
  final String? totalRevenue;
  final String? salesAmount;
  final String? receivedAmount;
  final String? pendingPayment;
  final Map<String, double>? categoryWiseSales;
  final String? yearlyTarget;
  final String? achievedPercentage;

  DashboardSummary({
    required this.dealersCount,
    required this.farmersCount,
    required this.dealerTicketsCount,
    required this.farmerTicketsCount,
    required this.totalOrders,
    required this.deliveredOrders,
    required this.totalRevenue,
    required this.salesAmount,
    required this.receivedAmount,
    required this.pendingPayment,
    required this.categoryWiseSales,
    required this.yearlyTarget,
    required this.achievedPercentage,
  });

  factory DashboardSummary.fromJson(Map<String, dynamic> j) {
    // safe parsing for categoryWiseSales — expects list or map
    Map<String, double> categories = {};
    try {
      final raw = j['categoryWiseSales'];
      if (raw is List) {
        for (final e in raw) {
          final key = (e['category'] ?? e['name'] ?? 'Unknown').toString();
          final v =
              double.tryParse((e['value'] ?? e['amount'] ?? '0').toString()) ??
              0.0;
          categories[key] = (categories[key] ?? 0.0) + v;
        }
      } else if (raw is Map) {
        raw.forEach((k, v) {
          categories[k.toString()] = double.tryParse(v.toString()) ?? 0.0;
        });
      }
    } catch (_) {}

    return DashboardSummary(
      dealersCount: j['counts']?['dealers'] ?? j['dealersCount'] ?? 0,
      farmersCount: j['counts']?['farmers'] ?? j['farmersCount'] ?? 0,
      dealerTicketsCount:
          j['counts']?['dealerTickets'] ?? j['dealerTicketsCount'] ?? 0,
      farmerTicketsCount:
          j['counts']?['farmerTickets'] ?? j['farmerTicketsCount'] ?? 0,
      totalOrders: j['totalOrders'] ?? 0,
      deliveredOrders: j['deliveredOrders'] ?? 0,
      totalRevenue:
          j['revenue']?['receivedAmount']?.toString() ??
          j['sales']?['salesAmount']?.toString() ??
          '0',
      salesAmount: j['sales']?['salesAmount']?.toString() ?? '0',
      receivedAmount: j['revenue']?['receivedAmount']?.toString() ?? '0',
      pendingPayment: j['revenue']?['pendingPayment']?.toString() ?? '0',
      categoryWiseSales: categories.isEmpty ? null : categories,
      yearlyTarget:
          j['target']?['yearlyTarget']?.toString() ?? j['target']?.toString(),
      achievedPercentage: j['target']?['achievedPercentage']?.toString(),
    );
  }

  factory DashboardSummary.empty() {
    return DashboardSummary(
      dealersCount: 0,
      farmersCount: 0,
      dealerTicketsCount: 0,
      farmerTicketsCount: 0,
      totalOrders: 0,
      deliveredOrders: 0,
      totalRevenue: '0',
      salesAmount: '0',
      receivedAmount: '0',
      pendingPayment: '0',
      categoryWiseSales: null,
      yearlyTarget: '0',
      achievedPercentage: '0',
    );
  }

  bool get isEmpty {
    return dealersCount == 0 &&
        farmersCount == 0 &&
        dealerTicketsCount == 0 &&
        farmerTicketsCount == 0 &&
        totalOrders == 0 &&
        deliveredOrders == 0 &&
        (salesAmount == null || salesAmount == '0') &&
        (receivedAmount == null || receivedAmount == '0') &&
        (categoryWiseSales == null ||
            categoryWiseSales!.values.every((v) => v == 0));
  }
}

Future<DashboardSummary> fetchDashboardSummary(
  Future<Map<String, String>> Function() headerBuilder,
) async {
  final cacheKey = 'dashboard:summaries';
  final uri = AppConfig.u(AppConfig.reportsByToken);

  // Try network
  try {
    final headers = await headerBuilder();
    final res = await http.get(uri, headers: headers);

    if (res.statusCode == 200) {
      await apiClient.cache?.put(
        cacheKey,
        CacheEntry(
          body: res.body,
          statusCode: res.statusCode,
          storedAtMillis: DateTime.now().millisecondsSinceEpoch,
        ),
      );

      final body = jsonDecode(res.body);
      return DashboardSummary.fromJson(body['data'] ?? body);
    }
  } catch (_) {
    // ignore → fallback
  }

  // Fallback to cache
  final cached = apiClient.cache?.get(cacheKey);
  if (cached != null && cached.body.isNotEmpty) {
    final body = jsonDecode(cached.body);
    return DashboardSummary.fromJson(body['data'] ?? body);
  }

  return DashboardSummary.empty();
}
