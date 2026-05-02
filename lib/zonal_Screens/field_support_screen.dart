import 'package:flutter/material.dart';
import 'package:FieldService_app/config.dart';
import 'package:FieldService_app/zonal_services/zonal_ticket_service.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// CONSTANTS
// ═══════════════════════════════════════════════════════════════════════════════

class _C {
  static const green = Color(0xFF1AB69C);
  static const greenLight = Color(0xFFE8F8F5);
  static const gradStart = Color(0xFF52D494);
  static const gradEnd = Color(0xFF1AB69C);
  static const bg = Color(0xFFF2F6F3);
  static const amber = Color(0xFFF59E0B);
  static const red = Color(0xFFEF4444);
}

// ═══════════════════════════════════════════════════════════════════════════════
// SCREEN
// ═══════════════════════════════════════════════════════════════════════════════

class FieldSupportScreen extends StatefulWidget {
  const FieldSupportScreen({super.key});

  @override
  State<FieldSupportScreen> createState() => _FieldSupportScreenState();
}

class _FieldSupportScreenState extends State<FieldSupportScreen> {
  final ZonalTicketService _service = ZonalTicketService();

  String _selectedFilter = 'All';
  bool _isLoading = true;
  List<TicketData> _tickets = [];

  final List<String> _filters = ['All', 'Pending', 'Open', 'Resolved'];

  @override
  void initState() {
    super.initState();
    _loadTickets();
  }

  Future<void> _loadTickets() async {
    setState(() => _isLoading = true);
    final result = await _service.fetchTickets();
    if (!mounted) return;

    if (result.error == 'UNAUTHORIZED') {
      Navigator.of(context).maybePop();
      return;
    }
    if (!result.success) {
      _snack(result.error ?? 'Failed to load tickets');
      setState(() => _isLoading = false);
      return;
    }
    setState(() {
      _tickets = result.tickets;
      _isLoading = false;
    });
  }

  List<TicketData> get _filtered {
    List<TicketData> list = List.from(_tickets);

    // ✅ FILTER (only if not ALL)
    if (_selectedFilter != 'All') {
      list = list.where((t) {
        final s = t.status.toLowerCase();

        if (_selectedFilter == 'Resolved') {
          return s == 'resolved' || s == 'solved';
        }

        return s == _selectedFilter.toLowerCase();
      }).toList();
    }

    // ✅ SORTING LOGIC (CORE REQUIREMENT)
    list.sort((a, b) {
      final statusA = a.status.toLowerCase();
      final statusB = b.status.toLowerCase();

      // 🔥 Priority: Pending first
      if (statusA == 'pending' && statusB != 'pending') return -1;
      if (statusA != 'pending' && statusB == 'pending') return 1;

      // 🔥 Inside same status → latest first
      return b.date.compareTo(a.date);
    });

    return list;
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return _C.amber;
      case 'open':
        return _C.red;
      case 'resolved':
      case 'solved':
        return _C.green;
      default:
        return Colors.grey;
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: _C.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bg,
      appBar: _appBar(),
      body: Column(
        children: [
          _filterChips(),
          Expanded(child: _ticketList()),
        ],
      ),
    );
  }

  PreferredSizeWidget _appBar() => PreferredSize(
    preferredSize: const Size.fromHeight(60),
    child: Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_C.gradStart, _C.gradEnd],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
        ),
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(
            Icons.arrow_back_sharp,
            color: Colors.white,
            size: 20,
          ),
        ),
        title: const Text(
          'Field Support',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    ),
  );

  Widget _filterChips() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _filters.map((f) {
          final sel = _selectedFilter == f;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => setState(() => _selectedFilter = f),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: sel ? _C.green : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: sel ? _C.green : const Color(0xFFE5E7EB),
                  ),
                  boxShadow: sel
                      ? [
                          BoxShadow(
                            color: _C.green.withValues(alpha: 0.25),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ]
                      : [],
                ),
                child: Text(
                  f,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: sel ? Colors.white : Colors.black54,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    ),
  );

  Widget _ticketList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: _C.green));
    }

    final list = _filtered;

    return RefreshIndicator(
      onRefresh: _loadTickets,
      color: _C.green,
      child: list.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 120),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.support_agent_outlined,
                        size: 52,
                        color: Colors.grey[300],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No tickets found',
                        style: TextStyle(color: Colors.grey[400], fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ],
            )
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final t = list[i];
                return _TicketCard(
                  ticket: t,
                  statusColor: _statusColor(t.status),
                  onDetails: () => _showDetailsSheet(t),
                  onResolve: () => _showResolveSheet(t),
                );
              },
            ),
    );
  }

  // ── Details Bottom Sheet ───────────────────────────────────────────────────

  void _showDetailsSheet(TicketData ticket) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DetailsSheet(
        ticket: ticket,
        baseUrl: AppConfig.apiBase,
        statusColor: _statusColor(ticket.status),
      ),
    );
  }

  // ── Resolve Bottom Sheet ───────────────────────────────────────────────────

  void _showResolveSheet(TicketData ticket) {
    final controller = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,

      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Drag handle
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),

                  Text(
                    'Resolve Ticket',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _C.green,
                    ),
                  ),

                  const SizedBox(height: 16),

                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          ticket.ticketId,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _C.green.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          ticket.status,
                          style: const TextStyle(color: _C.green, fontSize: 12),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  TextField(
                    controller: controller,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: 'Enter solution...',
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _C.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () async {
                        if (controller.text.trim().isEmpty) {
                          _snack('Solution cannot be empty');
                          return;
                        }
                        final ok = await _service.updateTicket(
                          id: ticket.id,
                          type: ticket.type,
                          status: 'Solved',
                          solution: controller.text.trim(),
                        );
                        if (!mounted || !ctx.mounted) return;
                        Navigator.pop(ctx);
                        _snack(
                          ok ? 'Ticket resolved!' : 'Failed to update ticket',
                        );
                        if (ok) _loadTickets();
                      },
                      child: const Text(
                        'Mark as Solved',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// DETAILS BOTTOM SHEET  (standalone widget for clean separation)
// ═══════════════════════════════════════════════════════════════════════════════

class _DetailsSheet extends StatelessWidget {
  final TicketData ticket;
  final String baseUrl;
  final Color statusColor;

  const _DetailsSheet({
    required this.ticket,
    required this.baseUrl,
    required this.statusColor,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // ── Fixed header ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Column(
                children: [
                  // Drag handle
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Ticket Details',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: _C.green,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          ticket.status,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: statusColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                ],
              ),
            ),

            // ── Scrollable body ─────────────────────────────────────────────
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                children: [
                  // Core info card
                  _InfoCard(ticket: ticket),

                  // Farmer-only: Images
                  if (ticket.isFarmer && ticket.images.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _SectionHeader(
                      icon: Icons.photo_library_outlined,
                      label: 'Site Images',
                      count: ticket.images.length,
                    ),
                    const SizedBox(height: 10),
                    _ImageGrid(images: ticket.images, baseUrl: baseUrl),
                  ],

                  // Farmer-only: Ponds
                  if (ticket.isFarmer && ticket.ponds.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _SectionHeader(
                      icon: Icons.water_outlined,
                      label: 'Pond Details',
                      count: ticket.ponds.length,
                    ),
                    const SizedBox(height: 10),
                    ...ticket.ponds.asMap().entries.map(
                      (e) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _PondCard(pond: e.value, index: e.key),
                      ),
                    ),
                  ],

                  const SizedBox(height: 16),

                  // Close button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _C.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        'Close',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),
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

// ═══════════════════════════════════════════════════════════════════════════════
// INFO CARD  — core ticket fields
// ═══════════════════════════════════════════════════════════════════════════════

class _InfoCard extends StatelessWidget {
  final TicketData ticket;
  const _InfoCard({required this.ticket});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _C.greenLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _C.green.withValues(alpha: 0.15)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _row('Ticket ID', ticket.ticketId),
          _row('Type', ticket.type),
          _row('Customer', ticket.customer),
          _row('Mobile', ticket.mobileNumber),
          _row('Location', ticket.location),
          _row('Remarks', ticket.remarks),
          if (ticket.response != null && ticket.response!.isNotEmpty)
            _row('Solution', ticket.response!),
          _row(
            'Date',
            '${ticket.date.day}/${ticket.date.month}/${ticket.date.year}  '
                '${ticket.date.hour.toString().padLeft(2, '0')}:'
                '${ticket.date.minute.toString().padLeft(2, '0')}',
            isLast: true,
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {bool isLast = false}) => Column(
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
      if (!isLast)
        Divider(
          height: 16,
          thickness: 0.5,
          color: _C.green.withValues(alpha: 0.2),
        ),
    ],
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION HEADER
// ═══════════════════════════════════════════════════════════════════════════════

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  const _SectionHeader({
    required this.icon,
    required this.label,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: _C.greenLight,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: _C.green, size: 16),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: _C.green.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '$count',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: _C.green,
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// IMAGE GRID  — horizontal scroll + tap to preview full screen
// ═══════════════════════════════════════════════════════════════════════════════

class _ImageGrid extends StatelessWidget {
  final List<String> images;
  final String baseUrl;
  const _ImageGrid({required this.images, required this.baseUrl});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 100,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: images.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (ctx, i) {
          final url = '$baseUrl${images[i]}';
          return GestureDetector(
            onTap: () => _openPreview(ctx, i),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Image.network(
                  url,
                  fit: BoxFit.cover,
                  loadingBuilder: (_, child, prog) => prog == null
                      ? child
                      : Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              value: prog.expectedTotalBytes != null
                                  ? prog.cumulativeBytesLoaded /
                                        prog.expectedTotalBytes!
                                  : null,
                              color: _C.green,
                            ),
                          ),
                        ),
                  errorBuilder: (_, _, _) => Container(
                    color: Colors.grey.shade200,
                    child: const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.grey,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _openPreview(BuildContext context, int initialIndex) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _ImagePreviewScreen(
          urls: images.map((p) => '$baseUrl$p').toList(),
          initialIndex: initialIndex,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// IMAGE PREVIEW SCREEN — full screen, swipeable
// ═══════════════════════════════════════════════════════════════════════════════

class _ImagePreviewScreen extends StatefulWidget {
  final List<String> urls;
  final int initialIndex;
  const _ImagePreviewScreen({required this.urls, required this.initialIndex});

  @override
  State<_ImagePreviewScreen> createState() => _ImagePreviewScreenState();
}

class _ImagePreviewScreenState extends State<_ImagePreviewScreen> {
  late final PageController _ctrl;
  late int _current;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _ctrl = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          '${_current + 1} / ${widget.urls.length}',
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
        centerTitle: true,
      ),
      body: PageView.builder(
        controller: _ctrl,
        itemCount: widget.urls.length,
        onPageChanged: (i) => setState(() => _current = i),
        itemBuilder: (_, i) => InteractiveViewer(
          minScale: 0.8,
          maxScale: 4.0,
          child: Center(
            child: Image.network(
              widget.urls[i],
              fit: BoxFit.contain,
              loadingBuilder: (_, child, prog) => prog == null
                  ? child
                  : const Center(
                      child: CircularProgressIndicator(color: _C.green),
                    ),
              errorBuilder: (_, _, _) => const Center(
                child: Icon(
                  Icons.broken_image_outlined,
                  color: Colors.white54,
                  size: 52,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// POND CARD  — expandable, shows all 3 reading types
// ═══════════════════════════════════════════════════════════════════════════════

class _PondCard extends StatefulWidget {
  final PondData pond;
  final int index;
  const _PondCard({required this.pond, required this.index});

  @override
  State<_PondCard> createState() => _PondCardState();
}

class _PondCardState extends State<_PondCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.pond;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _C.green.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          // ── Pond header (always visible) ──────────────────────────────────
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _C.greenLight,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.water_outlined,
                      color: _C.green,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.pondName.isEmpty
                              ? 'Pond ${widget.index + 1}'
                              : p.pondName,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${p.culturedSpecies}  •  ${p.culturedArea} acres',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: _C.green,
                  ),
                ],
              ),
            ),
          ),

          // ── Expanded readings ─────────────────────────────────────────────
          if (_expanded) ...[
            Divider(height: 1, color: _C.green.withValues(alpha: 0.15)),

            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Physical readings
                  if (p.physicalReadings.isNotEmpty) ...[
                    _ReadingHeader(
                      icon: Icons.analytics_outlined,
                      label: 'Physical Readings',
                    ),
                    const SizedBox(height: 8),
                    ...p.physicalReadings.map((r) => _PhysicalCard(r)),
                  ],

                  // Chemical readings
                  if (p.chemicalReadings.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    _ReadingHeader(
                      icon: Icons.science_outlined,
                      label: 'Chemical Readings',
                    ),
                    const SizedBox(height: 8),
                    ...p.chemicalReadings.map((r) => _ChemicalCard(r)),
                  ],

                  // Disease readings
                  if (p.diseaseReadings.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    _ReadingHeader(
                      icon: Icons.bug_report_outlined,
                      label: 'Disease Readings',
                    ),
                    const SizedBox(height: 8),
                    ...p.diseaseReadings.map((r) => _DiseaseCard(r)),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Reading sub-widgets ──────────────────────────────────────────────────────

class _ReadingHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  const _ReadingHeader({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 14, color: _C.green),
      const SizedBox(width: 6),
      Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Colors.black54,
        ),
      ),
    ],
  );
}

class _ReadingGrid extends StatelessWidget {
  final List<MapEntry<String, String>> items;
  const _ReadingGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF6FDFB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _C.green.withValues(alpha: 0.12)),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        children: items
            .map(
              (e) => SizedBox(
                width: (MediaQuery.of(context).size.width - 112) / 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.key,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[500],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      e.value,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _PhysicalCard extends StatelessWidget {
  final PhysicalReading r;
  const _PhysicalCard(this.r);
  @override
  Widget build(BuildContext context) => _ReadingGrid(
    items: [
      MapEntry('Stocking PL', '${r.stockingPL}'),
      MapEntry('DOC', '${r.doc}'),
      MapEntry('Feed/Day', '${r.feedIntakePerDay}'),
      MapEntry('Count', '${r.count}'),
      MapEntry('Avg Weight', '${r.avgWeight}g'),
    ],
  );
}

class _ChemicalCard extends StatelessWidget {
  final ChemicalReading r;
  const _ChemicalCard(this.r);
  @override
  Widget build(BuildContext context) => _ReadingGrid(
    items: [
      MapEntry('Salinity', '${r.salinity}'),
      MapEntry('pH', '${r.ph}'),
      MapEntry('Alkalinity', '${r.alkalinity}'),
      MapEntry('Ammonia', '${r.ammonia}'),
      MapEntry('Nitrite', '${r.nitrite}'),
      MapEntry('DO', '${r.dissolvedOxygen}'),
    ],
  );
}

class _DiseaseCard extends StatelessWidget {
  final DiseaseReading r;
  const _DiseaseCard(this.r);
  @override
  Widget build(BuildContext context) =>
      _ReadingGrid(items: [MapEntry('Vibrios', '${r.vibrios}')]);
}

// ═══════════════════════════════════════════════════════════════════════════════
// TICKET CARD
// ═══════════════════════════════════════════════════════════════════════════════

class _TicketCard extends StatelessWidget {
  final TicketData ticket;
  final Color statusColor;
  final VoidCallback onDetails;
  final VoidCallback onResolve;

  const _TicketCard({
    required this.ticket,
    required this.statusColor,
    required this.onDetails,
    required this.onResolve,
  });

  @override
  Widget build(BuildContext context) {
    final resolved =
        ticket.status.toLowerCase() == 'resolved' ||
        ticket.status.toLowerCase() == 'solved';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: ticket ID + status badge
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: _C.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  ticket.ticketId,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _C.green,
                  ),
                ),
              ),
              const Spacer(),
              // Farmer badge
              if (ticket.isFarmer)
                Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Farmer',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.blueAccent,
                    ),
                  ),
                ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  ticket.status,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),
          Text(
            ticket.customer,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${ticket.type} • ${ticket.mobileNumber}',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 6),
          Text(
            ticket.location,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
              height: 1.4,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Text(
            ticket.remarks,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[700],
              height: 1.4,
            ),
          ),

          // Solution preview
          if (ticket.response != null && ticket.response!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Solution: ${ticket.response}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[700],
                fontStyle: FontStyle.italic,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],

          // Farmer indicators
          if (ticket.isFarmer) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                if (ticket.images.isNotEmpty)
                  _Pill(
                    Icons.photo_outlined,
                    '${ticket.images.length} photo${ticket.images.length > 1 ? 's' : ''}',
                  ),
                if (ticket.images.isNotEmpty && ticket.ponds.isNotEmpty)
                  const SizedBox(width: 6),
                if (ticket.ponds.isNotEmpty)
                  _Pill(
                    Icons.water_outlined,
                    '${ticket.ponds.length} pond${ticket.ponds.length > 1 ? 's' : ''}',
                  ),
              ],
            ),
          ],

          const SizedBox(height: 10),
          const Divider(height: 1, thickness: 0.5, color: Color(0xFFF0F0F0)),
          const SizedBox(height: 10),

          Row(
            children: [
              const Icon(
                Icons.access_time_rounded,
                size: 13,
                color: Colors.black38,
              ),
              const SizedBox(width: 4),
              Text(
                ticket.timeAgo,
                style: const TextStyle(fontSize: 12, color: Colors.black45),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  ticket.status,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: _C.green, width: 1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    foregroundColor: _C.green,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  icon: const Icon(Icons.visibility_outlined, size: 16),
                  label: const Text(
                    'View Details',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  onPressed: onDetails,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: resolved ? Colors.grey[200] : _C.green,
                    foregroundColor: resolved ? Colors.grey : Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  icon: Icon(
                    resolved
                        ? Icons.check_circle_rounded
                        : Icons.check_circle_outline_rounded,
                    size: 16,
                  ),
                  label: Text(
                    resolved ? 'Resolved' : 'Resolve',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onPressed: resolved ? null : onResolve,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// Small inline pill badge used on the ticket card
class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Pill(this.icon, this.label);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: _C.green.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: _C.green.withValues(alpha: 0.2)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: _C.green),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: _C.green,
          ),
        ),
      ],
    ),
  );
}
