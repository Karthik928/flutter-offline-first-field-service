// lib/screens/failed_records_screen.dart
//
// Production-grade "Failed Records" screen.
//
// Features:
//  • Grouped by FailedRecordType with animated section headers
//  • Filter chips (All / by type)
//  • Search bar (fuzzy match on path + error detail + body keys)
//  • Sort: Newest first / Oldest first / By type
//  • Expandable detail cards (full body, headers, timeline)
//  • Pretty JSON viewer with syntax-like colouring
//  • Animated empty state
//  • Pull-to-refresh
//  • Status-code badge with colour semantics
//  • Count badge on AppBar
//  • No network calls — 100% read-only

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../offline/failed_record_model.dart';
import '../offline/failed_record_store.dart';

// ─── Colour palette (internal) ───────────────────────────────────────────────

const _kBg = Color(0xFFFFFFFF);
const _kSurface = Color(0xFFFFFFFF);
const _kSurface2 = Color(0xFFF7F9FA);
const _kBorder = Color(0xFFE5E7EB);
const _kTextPrimary = Color(0xFF111827);
const _kTextSecondary = Color(0xFF6B7280);
const _kAccent = Color(0xFF0BA5EC);
const _kRed = Color(0xFFE45555);
const _kAmber = Color(0xFFF59E0B);
const _kGreen = Color(0xFF1EB89C);
const _kChipBg = Color(0xFFFFFFFF);

// ─── Type metadata ────────────────────────────────────────────────────────────

const _typeConfig = <FailedRecordType, _TypeMeta>{
  FailedRecordType.tripStart: _TypeMeta(
    icon: Icons.play_circle_outline_rounded,
    color: Color(0xFF3DD68C),
    label: 'Trip Start',
  ),
  FailedRecordType.tripEnd: _TypeMeta(
    icon: Icons.stop_circle_outlined,
    color: Color(0xFFFF5C72),
    label: 'Trip End',
  ),
  FailedRecordType.tripUpdate: _TypeMeta(
    icon: Icons.update_rounded,
    color: Color(0xFF6B7FFF),
    label: 'Trip Update',
  ),
  FailedRecordType.fileUpload: _TypeMeta(
    icon: Icons.upload_file_rounded,
    color: Color(0xFFFFB547),
    label: 'File Upload',
  ),
  FailedRecordType.shopVisit: _TypeMeta(
    icon: Icons.store_mall_directory_outlined,
    color: Color(0xFF54D2E0),
    label: 'Shop Visit',
  ),
  FailedRecordType.orderSubmit: _TypeMeta(
    icon: Icons.receipt_long_outlined,
    color: Color(0xFFD46BFF),
    label: 'Order Submit',
  ),
  FailedRecordType.generic: _TypeMeta(
    icon: Icons.api_rounded,
    color: Color(0xFF8A8FB8),
    label: 'API Request',
  ),
};

class _TypeMeta {
  final IconData icon;
  final Color color;
  final String label;
  const _TypeMeta({
    required this.icon,
    required this.color,
    required this.label,
  });
}

// ─── Sort options ─────────────────────────────────────────────────────────────

enum _SortMode { newestFirst, oldestFirst, byType }

// ════════════════════════════════════════════════════════════════════════════
// Main screen
// ════════════════════════════════════════════════════════════════════════════

class FailedRecordsScreen extends StatefulWidget {
  final FailedRecordStore store;

  const FailedRecordsScreen({super.key, required this.store});

  @override
  State<FailedRecordsScreen> createState() => _FailedRecordsScreenState();
}

class _FailedRecordsScreenState extends State<FailedRecordsScreen>
    with SingleTickerProviderStateMixin {
  List<FailedRecord> _all = [];
  bool _loading = true;
  String _searchQuery = '';
  FailedRecordType? _filterType; // null = show all
  _SortMode _sort = _SortMode.newestFirst;

  final _searchController = TextEditingController();
  late final AnimationController _shimmerCtrl;

  @override
  void initState() {
    super.initState();
    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _load();
  }

  @override
  void dispose() {
    _shimmerCtrl.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final records = await widget.store.all();
    if (!mounted) return;
    setState(() {
      _all = records;
      _loading = false;
    });
  }

  List<FailedRecord> get _filtered {
    var list = List<FailedRecord>.from(_all);

    // Type filter
    if (_filterType != null) {
      list = list.where((r) => r.recordType == _filterType).toList();
    }

    // Search
    final q = _searchQuery.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((r) {
        return r.path.toLowerCase().contains(q) ||
            (r.errorDetail?.toLowerCase().contains(q) ?? false) ||
            r.failureLabel.toLowerCase().contains(q) ||
            r.typeLabel.toLowerCase().contains(q) ||
            (r.jsonBody?.toString().toLowerCase().contains(q) ?? false);
      }).toList();
    }

    // Sort
    switch (_sort) {
      case _SortMode.newestFirst:
        list.sort((a, b) => b.failedAt.compareTo(a.failedAt));
        break;
      case _SortMode.oldestFirst:
        list.sort((a, b) => a.failedAt.compareTo(b.failedAt));
        break;
      case _SortMode.byType:
        list.sort((a, b) => a.recordType.index.compareTo(b.recordType.index));
        break;
    }

    return list;
  }

  Map<FailedRecordType, List<FailedRecord>> get _grouped {
    final map = <FailedRecordType, List<FailedRecord>>{};
    for (final r in _filtered) {
      map.putIfAbsent(r.recordType, () => []).add(r);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: _buildTheme(),
      child: Scaffold(
        backgroundColor: _kBg,
        body: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            _buildAppBar(innerBoxIsScrolled),
          ],
          body: Column(
            children: [
              SizedBox(height: 8),
              _buildFilterRow(),
              Expanded(
                child: _loading
                    ? _buildShimmer()
                    : RefreshIndicator(
                        onRefresh: _load,
                        color: _kAccent,
                        backgroundColor: _kBg,
                        child: _filtered.isEmpty
                            ? _buildEmptyState()
                            : _buildList(),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── AppBar ───────────────────────────────────────────────────────────────

  Widget _buildAppBar(bool innerBoxIsScrolled) {
    return SliverAppBar(
      backgroundColor: _kGreen,
      surfaceTintColor: Colors.transparent,
      expandedHeight: 120,
      floating: false,
      pinned: true,
      elevation: 0,

      // ✅ FIX: move title here (NOT inside FlexibleSpaceBar)
      title: Row(
        children: [
          const Text(
            'Failed Records',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(width: 8),
          if (_all.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.4),
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${_all.length}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),

      leading: IconButton(
        icon: const Icon(Icons.arrow_back_sharp, color: Colors.white),
        onPressed: () => Navigator.pop(context),
      ),

      // ✅ Keep background only (no title here)
      flexibleSpace: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [_kGreen, _kGreen],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
      ),

      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(52),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: _buildSearchBar(),
        ),
      ),

      actions: [
        _SortButton(
          current: _sort,

          onChanged: (s) => setState(() => _sort = s),
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  // ─── Search bar ───────────────────────────────────────────────────────────

  Widget _buildSearchBar() {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: _kSurface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (v) => setState(() => _searchQuery = v),
        style: const TextStyle(color: _kTextPrimary, fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Search by path, error, data…',
          hintStyle: TextStyle(
            color: _kTextSecondary.withValues(alpha: 0.6),
            fontSize: 14,
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            color: _kTextSecondary,
            size: 18,
          ),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: Icon(
                    Icons.close_rounded,
                    color: _kTextSecondary,
                    size: 16,
                  ),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 11),
        ),
      ),
    );
  }

  // ─── Filter chips ─────────────────────────────────────────────────────────

  Widget _buildFilterRow() {
    final typeCounts = <FailedRecordType, int>{};
    for (final r in _all) {
      typeCounts[r.recordType] = (typeCounts[r.recordType] ?? 0) + 1;
    }

    final types = typeCounts.keys.toList()
      ..sort((a, b) => (typeCounts[b] ?? 0).compareTo(typeCounts[a] ?? 0));

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _FilterChip(
            label: 'All',
            count: _all.length,
            selected: _filterType == null,
            color: _kAccent,
            onTap: () => setState(() => _filterType = null),
          ),
          const SizedBox(width: 8),
          ...types.map((t) {
            final meta = _typeConfig[t]!;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _FilterChip(
                label: meta.label,
                count: typeCounts[t] ?? 0,
                selected: _filterType == t,
                color: meta.color,
                icon: meta.icon,
                onTap: () =>
                    setState(() => _filterType = (_filterType == t) ? null : t),
              ),
            );
          }),
        ],
      ),
    );
  }

  // ─── List ─────────────────────────────────────────────────────────────────

  Widget _buildList() {
    final grouped = _grouped;

    // If sorting by type, use grouped sections; otherwise flat
    if (_sort == _SortMode.byType) {
      final items = <Widget>[];
      for (final entry in grouped.entries) {
        items.add(_SectionHeader(type: entry.key, count: entry.value.length));
        for (var i = 0; i < entry.value.length; i++) {
          items.add(_RecordCard(record: entry.value[i], index: i));
        }
      }
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: items,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      itemCount: _filtered.length,
      itemBuilder: (context, index) =>
          _RecordCard(record: _filtered[index], index: index),
    );
  }

  // ─── Empty state ──────────────────────────────────────────────────────────

  Widget _buildEmptyState() {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _kGreen.withValues(alpha: 0.12),
                    border: Border.all(
                      color: _kGreen.withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                  ),
                  child: const Icon(
                    Icons.check_circle_outline_rounded,
                    color: _kGreen,
                    size: 36,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'No Failed Records',
                  style: TextStyle(
                    color: _kTextPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _searchQuery.isNotEmpty || _filterType != null
                      ? 'Try adjusting your filters'
                      : 'All synced records are healthy',
                  style: const TextStyle(color: _kTextSecondary, fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Shimmer loading ──────────────────────────────────────────────────────

  Widget _buildShimmer() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: List.generate(
        5,
        (i) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: AnimatedBuilder(
            animation: _shimmerCtrl,
            builder: (_, _) {
              final shimmer = LinearGradient(
                colors: const [
                  Color(0xFF1A1D27),
                  Color(0xFF262A3D),
                  Color(0xFF1A1D27),
                ],
                stops: const [0, 0.5, 1],
                transform: _ShimmerTransform(_shimmerCtrl.value),
              );
              return Container(
                height: 100,
                decoration: BoxDecoration(
                  gradient: shimmer,
                  borderRadius: BorderRadius.circular(16),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  ThemeData _buildTheme() {
    return ThemeData.dark().copyWith(
      scaffoldBackgroundColor: _kBg,
      colorScheme: const ColorScheme.dark(
        primary: _kAccent,
        surface: _kSurface,
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Record Card
// ════════════════════════════════════════════════════════════════════════════

class _RecordCard extends StatefulWidget {
  final FailedRecord record;
  final int index;

  const _RecordCard({required this.record, required this.index});

  @override
  State<_RecordCard> createState() => _RecordCardState();
}

class _RecordCardState extends State<_RecordCard>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late final AnimationController _ctrl;
  late final Animation<double> _expandAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _expandAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOutCubic);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    _expanded ? _ctrl.forward() : _ctrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.record;
    final meta = _typeConfig[r.recordType]!;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 300 + widget.index * 50),
      curve: Curves.easeOut,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(0, 20 * (1 - v)),
          child: child,
        ),
      ),
      child: GestureDetector(
        onTap: _toggle,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: _kSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _expanded
                  ? meta.color.withValues(alpha: 0.35)
                  : _kBorder,
              width: 1,
            ),
            boxShadow: _expanded
                ? [
                    BoxShadow(
                      color: meta.color.withValues(alpha: 0.06),
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : [],
          ),
          child: Column(
            children: [
              _buildHeader(r, meta),
              SizeTransition(
                sizeFactor: _expandAnim,
                child: _buildDetails(r, meta),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(FailedRecord r, _TypeMeta meta) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Type icon badge
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: meta.color.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(meta.icon, color: meta.color, size: 20),
          ),
          const SizedBox(width: 12),
          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        r.typeLabel,
                        style: const TextStyle(
                          color: _kTextPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    _StatusBadge(code: r.lastStatusCode),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${r.method}  ${r.path}',
                  style: const TextStyle(
                    color: _kTextSecondary,
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      color: _kRed.withValues(alpha: 0.7),
                      size: 12,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        r.failureLabel,
                        style: TextStyle(
                          color: _kRed.withValues(alpha: 0.85),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      _relativeTime(r.failedAt),
                      style: const TextStyle(
                        color: _kTextSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          AnimatedRotation(
            turns: _expanded ? 0.5 : 0,
            duration: const Duration(milliseconds: 260),
            child: const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: _kTextSecondary,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetails(FailedRecord r, _TypeMeta meta) {
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: _kBorder, width: 1)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline row
          _TimelineRow(record: r),
          const SizedBox(height: 16),

          // Metadata grid
          _MetaGrid(record: r),
          const SizedBox(height: 16),

          // Error detail
          if (r.errorDetail != null && r.errorDetail!.isNotEmpty) ...[
            _SectionLabel(
              label: 'Error Detail',
              icon: Icons.bug_report_outlined,
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _kRed.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _kRed.withValues(alpha: 0.2)),
              ),
              child: SelectableText(
                r.errorDetail!,
                style: TextStyle(
                  color: _kRed.withValues(alpha: 0.9),
                  fontSize: 12,
                  fontFamily: 'monospace',
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Request body
          if (r.sanitisedBody.isNotEmpty) ...[
            _SectionLabel(
              label: 'Request Body',
              icon: Icons.data_object_rounded,
              trailing: _CopyButton(text: jsonEncode(r.sanitisedBody)),
            ),
            const SizedBox(height: 8),
            _JsonViewer(data: r.sanitisedBody),
            const SizedBox(height: 16),
          ],

          // Attached files
          if (r.attachedFileNames.isNotEmpty) ...[
            _SectionLabel(
              label: 'Attached Files',
              icon: Icons.attach_file_rounded,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: r.attachedFileNames
                  .map((name) => _FileChip(name: name))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Sub-widgets
// ════════════════════════════════════════════════════════════════════════════

class _StatusBadge extends StatelessWidget {
  final int code;
  const _StatusBadge({required this.code});

  @override
  Widget build(BuildContext context) {
    Color color;
    if (code == 0) {
      color = _kTextSecondary;
    } else if (code >= 500) {
      color = _kRed;
    } else if (code >= 400) {
      color = _kAmber;
    } else if (code >= 200 && code < 300) {
      color = _kGreen;
    } else {
      color = _kTextSecondary;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        code == 0 ? 'NO RESP' : '$code',
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  final FailedRecord record;
  const _TimelineRow({required this.record});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _TimestampBlock(
          label: 'Enqueued',
          time: record.enqueuedAt,
          icon: Icons.schedule_rounded,
          color: _kAccent,
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: CustomPaint(
              painter: _DashedLinePainter(color: _kBorder),
              size: const Size(double.infinity, 1),
            ),
          ),
        ),
        _TimestampBlock(
          label: 'Failed',
          time: record.failedAt,
          icon: Icons.cancel_outlined,
          color: _kRed,
          alignRight: true,
        ),
      ],
    );
  }
}

class _TimestampBlock extends StatelessWidget {
  final String label;
  final DateTime time;
  final IconData icon;
  final Color color;
  final bool alignRight;

  const _TimestampBlock({
    required this.label,
    required this.time,
    required this.icon,
    required this.color,
    this.alignRight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: alignRight
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Row(
          children: alignRight
              ? [
                  Text(
                    label,
                    style: const TextStyle(
                      color: _kTextSecondary,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(icon, size: 12, color: color),
                ]
              : [
                  Icon(icon, size: 12, color: color),
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: const TextStyle(
                      color: _kTextSecondary,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
        ),
        const SizedBox(height: 2),
        Text(
          _formatTs(time),
          style: const TextStyle(
            color: _kTextPrimary,
            fontSize: 11,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }
}

class _MetaGrid extends StatelessWidget {
  final FailedRecord record;
  const _MetaGrid({required this.record});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _MetaChip(label: 'Attempts', value: '${record.attemptCount}'),
        _MetaChip(
          label: 'Method',
          value: record.method,
          mono: true,
          color: _kAccent,
        ),
        if (record.attachedFileNames.isNotEmpty)
          _MetaChip(
            label: 'Files',
            value: '${record.attachedFileNames.length}',
            color: _kAmber,
          ),
        _MetaChip(
          label: 'ID',
          value: record.id.length > 12
              ? '…${record.id.substring(record.id.length - 8)}'
              : record.id,
          mono: true,
        ),
      ],
    );
  }
}

class _MetaChip extends StatelessWidget {
  final String label;
  final String value;
  final bool mono;
  final Color? color;

  const _MetaChip({
    required this.label,
    required this.value,
    this.mono = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _kSurface2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _kBorder),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$label  ',
              style: const TextStyle(color: _kTextSecondary, fontSize: 11),
            ),
            TextSpan(
              text: value,
              style: TextStyle(
                color: color ?? _kTextPrimary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                fontFamily: mono ? 'monospace' : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  final IconData icon;
  final Widget? trailing;

  const _SectionLabel({required this.label, required this.icon, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: _kTextSecondary),
        const SizedBox(width: 6),
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: _kTextSecondary,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
          ),
        ),
        const Spacer(),
        trailing ?? const SizedBox.shrink(),
      ],
    );
  }
}

class _JsonViewer extends StatelessWidget {
  final Map<String, dynamic> data;
  const _JsonViewer({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 220),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF13162A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBorder),
      ),
      child: SingleChildScrollView(
        child: SelectableText.rich(
          _buildJsonSpans(data, 0),
          style: const TextStyle(fontSize: 12, height: 1.6),
        ),
      ),
    );
  }

  TextSpan _buildJsonSpans(dynamic value, int depth) {
    const indent = '  ';
    final pad = indent * depth;
    final padInner = indent * (depth + 1);

    if (value is Map<String, dynamic>) {
      final children = <InlineSpan>[
        const TextSpan(
          text: '{\n',
          style: TextStyle(color: _kTextSecondary),
        ),
      ];
      final entries = value.entries.toList();
      for (var i = 0; i < entries.length; i++) {
        final e = entries[i];
        children.add(
          TextSpan(
            children: [
              TextSpan(
                text: '$padInner"${e.key}"',
                style: const TextStyle(color: Color(0xFF88C0D0)),
              ),
              const TextSpan(
                text: ': ',
                style: TextStyle(color: _kTextSecondary),
              ),
              _buildJsonSpans(e.value, depth + 1),
              if (i < entries.length - 1)
                const TextSpan(
                  text: ',',
                  style: TextStyle(color: _kTextSecondary),
                ),
              const TextSpan(text: '\n'),
            ],
          ),
        );
      }
      children.add(
        TextSpan(
          text: '$pad}',
          style: const TextStyle(color: _kTextSecondary),
        ),
      );
      return TextSpan(children: children);
    }

    if (value is List) {
      if (value.isEmpty) {
        return const TextSpan(
          text: '[]',
          style: TextStyle(color: _kTextSecondary),
        );
      }
      final children = <InlineSpan>[
        const TextSpan(
          text: '[\n',
          style: TextStyle(color: _kTextSecondary),
        ),
      ];
      for (var i = 0; i < value.length; i++) {
        children.add(
          TextSpan(
            children: [
              TextSpan(text: padInner),
              _buildJsonSpans(value[i], depth + 1),
              if (i < value.length - 1)
                const TextSpan(
                  text: ',',
                  style: TextStyle(color: _kTextSecondary),
                ),
              const TextSpan(text: '\n'),
            ],
          ),
        );
      }
      children.add(
        TextSpan(
          text: '$pad]',
          style: const TextStyle(color: _kTextSecondary),
        ),
      );
      return TextSpan(children: children);
    }

    if (value is String) {
      return TextSpan(
        text: '"$value"',
        style: const TextStyle(color: Color(0xFFA3BE8C)),
      );
    }

    if (value is num) {
      return TextSpan(
        text: '$value',
        style: const TextStyle(color: Color(0xFFB48EAD)),
      );
    }

    if (value is bool) {
      return TextSpan(
        text: '$value',
        style: TextStyle(
          color: value ? _kGreen : _kRed,
          fontWeight: FontWeight.w600,
        ),
      );
    }

    return TextSpan(
      text: 'null',
      style: const TextStyle(color: _kTextSecondary),
    );
  }
}

class _CopyButton extends StatefulWidget {
  final String text;
  const _CopyButton({required this.text});

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _copy,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: _copied
            ? const Row(
                key: ValueKey('done'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_rounded, size: 12, color: _kGreen),
                  SizedBox(width: 4),
                  Text(
                    'Copied',
                    style: TextStyle(color: _kGreen, fontSize: 11),
                  ),
                ],
              )
            : Row(
                key: const ValueKey('copy'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.copy_rounded, size: 12, color: _kTextSecondary),
                  const SizedBox(width: 4),
                  Text(
                    'Copy',
                    style: const TextStyle(
                      color: _kTextSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _FileChip extends StatelessWidget {
  final String name;
  const _FileChip({required this.name});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _kAmber.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _kAmber.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.attach_file_rounded, size: 12, color: _kAmber),
          const SizedBox(width: 5),
          Text(
            name,
            style: const TextStyle(
              color: _kAmber,
              fontSize: 11,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final Color color;
  final IconData? icon;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.color,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.18) : _kChipBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color.withValues(alpha: 0.5) : _kBorder,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: selected ? color : _kTextSecondary),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                color: selected ? color : _kTextSecondary,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: selected
                    ? color.withValues(alpha: 0.25)
                    : _kTextSecondary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  color: selected ? color : _kTextSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final FailedRecordType type;
  final int count;
  const _SectionHeader({required this.type, required this.count});

  @override
  Widget build(BuildContext context) {
    final meta = _typeConfig[type]!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Row(
        children: [
          Icon(meta.icon, size: 14, color: meta.color),
          const SizedBox(width: 8),
          Text(
            meta.label.toUpperCase(),
            style: TextStyle(
              color: meta.color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: meta.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                color: meta.color,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Divider(color: _kBorder, height: 1)),
        ],
      ),
    );
  }
}

class _SortButton extends StatelessWidget {
  final _SortMode current;
  final ValueChanged<_SortMode> onChanged;

  const _SortButton({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_SortMode>(
      onSelected: onChanged,
      color: _kSurface2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: _kBorder),
      ),
      icon: Icon(
        Icons.sort_rounded,
        //color: current != _SortMode.newestFirst ? _kAccent : _kTextSecondary,
        color: Colors.white,
        size: 22,
      ),
      itemBuilder: (_) => [
        _sortItem(
          _SortMode.newestFirst,
          'Newest First',
          Icons.arrow_downward_rounded,
          current,
        ),
        _sortItem(
          _SortMode.oldestFirst,
          'Oldest First',
          Icons.arrow_upward_rounded,
          current,
        ),
        _sortItem(
          _SortMode.byType,
          'Group by Type',
          Icons.category_rounded,
          current,
        ),
      ],
    );
  }

  PopupMenuItem<_SortMode> _sortItem(
    _SortMode mode,
    String label,
    IconData icon,
    _SortMode current,
  ) {
    final selected = current == mode;
    return PopupMenuItem(
      value: mode,
      child: Row(
        children: [
          Icon(icon, size: 16, color: selected ? _kAccent : _kTextSecondary),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              color: selected ? _kAccent : _kTextPrimary,
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
          if (selected) ...[
            const Spacer(),
            const Icon(Icons.check_rounded, size: 14, color: _kAccent),
          ],
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Helpers
// ════════════════════════════════════════════════════════════════════════════

String _relativeTime(DateTime dt) {
  final diff = DateTime.now().toUtc().difference(dt.toUtc());
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return '${dt.day}/${dt.month}/${dt.year}';
}

String _formatTs(DateTime dt) {
  final l = dt.toLocal();
  final h = l.hour.toString().padLeft(2, '0');
  final m = l.minute.toString().padLeft(2, '0');
  final d = l.day.toString().padLeft(2, '0');
  final mo = l.month.toString().padLeft(2, '0');
  return '$d/$mo  $h:$m';
}

// ─── Dashed line painter ──────────────────────────────────────────────────

class _DashedLinePainter extends CustomPainter {
  final Color color;
  const _DashedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const dashW = 4.0;
    const gap = 3.0;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x + dashW, 0), paint);
      x += dashW + gap;
    }
  }

  @override
  bool shouldRepaint(_DashedLinePainter old) => old.color != color;
}

// ─── Shimmer gradient transform ───────────────────────────────────────────

class _ShimmerTransform extends GradientTransform {
  final double progress;
  const _ShimmerTransform(this.progress);

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * (progress * 2 - 0.5), 0, 0);
  }
}
