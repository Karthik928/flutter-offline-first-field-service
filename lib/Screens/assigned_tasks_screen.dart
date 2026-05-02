import 'package:flutter/material.dart';
import 'package:FieldService_app/Screens/main_page.dart';
import 'package:FieldService_app/services/employee_task_service.dart';
import 'package:FieldService_app/services/trip_manager.dart';
import 'package:FieldService_app/widgets/shared_bottom_nav.dart';
import 'package:FieldService_app/widgets/task_details_sheet.dart'; // ← NEW
import 'package:FieldService_app/widgets/update_task_sheet.dart';

class AssignedTasksScreen extends StatefulWidget {
  const AssignedTasksScreen({super.key});

  @override
  State<AssignedTasksScreen> createState() => _AssignedTasksScreenState();
}

class _AssignedTasksScreenState extends State<AssignedTasksScreen> {
  static const _gradientStart = Color(0xFF52D494);
  static const _gradientEnd = Color(0xFF1AB69C);
  static const _accentGreen = Color(0xFF1AB69C);
  static const _background = Color(0xFFF2F6F3);

  final AllTasksService _service = AllTasksService();

  bool _isLoading = true;
  List<TaskItem> _allTasks = [];
  String _selectedTab = 'Pending';

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  Future<void> _loadTasks() async {
    setState(() => _isLoading = true);

    final result = await _service.fetchAllTasks();
    if (!mounted) return;

    if (result.error == 'UNAUTHORIZED') {
      Navigator.of(context).maybePop();
      return;
    }

    if (!result.success) {
      _showSnackBar(result.error ?? 'Failed to load tasks');
      setState(() => _isLoading = false);
      return;
    }

    setState(() {
      _allTasks = result.tasks;
      _isLoading = false;
    });
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: _accentGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  List<TaskItem> get _pendingTasks =>
      _allTasks.where((t) => t.status.toLowerCase() == 'pending').toList();

  List<TaskItem> get _completedTasks =>
      _allTasks.where((t) => t.status.toLowerCase() == 'completed').toList();

  List<TaskItem> get _filteredTasks {
    switch (_selectedTab) {
      case 'Pending':
        return _pendingTasks;
      case 'Completed':
        return _completedTasks;
      default:
        return _pendingTasks;
    }
  }

  /// Opens the update sheet for a PENDING task, then refreshes if updated.
  Future<void> _onPendingTaskTap(TaskItem task) async {
    if (!task.isPending) return;
    final updated = await UpdateTaskSheet.show(context, task: task);
    if (updated == true) _loadTasks();
  }

  /// Opens the details sheet for a COMPLETED task.
  void _onCompletedDetailsPressed(TaskItem task) {
    TaskDetailsSheet.show(context, task: task);
  }

  Future<void> _openDirections(TaskItem task) async {
    if (TripManager.active != null) {
      _showSnackBar('There is an ongoing trip');
      return;
    }

    final searchQuery = task.location.trim().isNotEmpty
        ? task.location.trim()
        : task.hasCoordinates
            ? '${task.latitude},${task.longitude}'
            : '';

    if (searchQuery.isEmpty) {
      _showSnackBar('No location available for this task');
      return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => MainPage(
          initialMenu: MenuState.map,
          initialTripSearchQuery: searchQuery,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          _buildTabBar(),
          _buildSummaryRow(),
          Expanded(child: _buildList()),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(60),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [_gradientStart, _gradientEnd],
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
            'Assigned Tasks',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        children: [
          _TabChip(
            label: 'Pending',
            count: _pendingTasks.length,
            selected: _selectedTab == 'Pending',
            onTap: () => setState(() => _selectedTab = 'Pending'),
          ),
          const SizedBox(width: 10),
          _TabChip(
            label: 'Completed',
            count: _completedTasks.length,
            selected: _selectedTab == 'Completed',
            onTap: () => setState(() => _selectedTab = 'Completed'),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          _SummaryCard(
            title: 'Total',
            value: '${_allTasks.length}',
            color: _accentGreen,
          ),
          const SizedBox(width: 10),
          _SummaryCard(
            title: 'Pending',
            value: '${_pendingTasks.length}',
            color: const Color(0xFFF59E0B),
          ),
          const SizedBox(width: 10),
          _SummaryCard(
            title: 'Done',
            value: '${_completedTasks.length}',
            color: const Color(0xFF1AB69C),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final list = _filteredTasks;

    if (list.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadTasks,
        color: _accentGreen,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 120),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _selectedTab == 'Pending'
                        ? Icons.pending_actions_outlined
                        : Icons.check_circle_outline,
                    size: 54,
                    color: Colors.grey[300],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No ${_selectedTab.toLowerCase()} tasks',
                    style: TextStyle(color: Colors.grey[400], fontSize: 14),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadTasks,
      color: _accentGreen,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: list.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) => _TaskCard(
          task: list[index],
          onTap: () => _onPendingTaskTap(list[index]),
          onDirectionsTap:
              list[index]
                  .isPending // ← NEW
              ? () => _openDirections(list[index])
              : null,
          onDetailsTap: list[index].isCompleted
              ? () => _onCompletedDetailsPressed(list[index])
              : null,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Private widgets
// ─────────────────────────────────────────────────────────────────────────────

class _TabChip extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  static const _accentGreen = Color(0xFF1AB69C);

  const _TabChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? _accentGreen : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? _accentGreen : const Color(0xFFE5E7EB),
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: _accentGreen.withValues(alpha: 0.18),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : [],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.black54,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.24)
                      : _accentGreen.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: selected ? Colors.white : _accentGreen,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final Color color;

  const _SummaryCard({
    required this.title,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color.withValues(alpha: 0.85),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  final TaskItem task;
  final VoidCallback onTap;
  final VoidCallback? onDetailsTap; // ← non-null only for completed tasks
  final VoidCallback? onDirectionsTap; // ← non-null only for pending tasks

  static const _accentGreen = Color(0xFF1AB69C);

  const _TaskCard({
    required this.task,
    required this.onTap,
    this.onDetailsTap,
    this.onDirectionsTap,
  });

  Color _statusColor() {
    switch (task.status.toLowerCase()) {
      case 'pending':
        return const Color(0xFFF59E0B);
      case 'completed':
        return _accentGreen;
      default:
        return Colors.grey;
    }
  }

  Color _priorityColor() {
    switch (task.priority.toLowerCase()) {
      case 'high':
        return const Color(0xFFEF4444);
      case 'medium':
        return const Color(0xFFF59E0B);
      case 'low':
        return _accentGreen;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final completed = task.isCompleted;
    final statusColor = _statusColor();

    return GestureDetector(
      onTap: task.isPending ? onTap : null,
      child: Container(
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
            // ── Top row: type + status badges ──────────────
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: _accentGreen.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    task.type,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _accentGreen,
                    ),
                  ),
                ),
                const Spacer(),
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
                    task.status,
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

            // ── Title ──────────────────────────────────────
            Text(
              task.title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: completed ? Colors.black54 : Colors.black87,
              ),
            ),
            const SizedBox(height: 4),

            // ── Location ───────────────────────────────────
            Text(
              task.location,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            const SizedBox(height: 10),

            // ── Priority + Due date chips ──────────────────
            Row(
              children: [
                _InfoChip(
                  label: 'Priority',
                  value: task.priority,
                  color: _priorityColor(),
                ),
                const SizedBox(width: 8),
                _InfoChip(
                  label: 'Due',
                  value: task.dueDateLabel,
                  color: statusColor,
                ),
              ],
            ),
            const SizedBox(height: 10),

            // ── Assigned to ────────────────────────────────
            Text(
              'Assigned to ${task.assignedToName}',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            const SizedBox(height: 10),

            const Divider(height: 1, thickness: 0.5, color: Color(0xFFF0F0F0)),
            const SizedBox(height: 10),

            // ── Description ────────────────────────────────
            Text(
              task.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[700],
                height: 1.35,
              ),
            ),

            // ── Completed footer: status + Details button ──
            if (completed) ...[
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // ✅ Completed badge (left)
                  const Row(
                    children: [
                      Icon(Icons.check_circle, size: 14, color: _accentGreen),
                      SizedBox(width: 5),
                      Text(
                        'Completed',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _accentGreen,
                        ),
                      ),
                    ],
                  ),

                  // 📋 Details button (right)
                  GestureDetector(
                    onTap: onDetailsTap,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1AB69C).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: const Color(0xFF1AB69C).withValues(alpha: 0.3),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            color: _accentGreen,
                            size: 14,
                          ),
                          SizedBox(width: 5),
                          Text(
                            'View Details',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: _accentGreen,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],

            // ── Pending CTA ────────────────────────────────
            if (task.isPending) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  // 🗺️ Directions button (left)
                  Expanded(
                    child: GestureDetector(
                      onTap: onDirectionsTap,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFF1AB69C,
                          ).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: const Color(
                              0xFF1AB69C,
                            ).withValues(alpha: 0.3),
                          ),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.directions_outlined,
                              color: _accentGreen,
                              size: 14,
                            ),
                            SizedBox(width: 5),
                            Text(
                              'Directions',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: _accentGreen,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 8),

                  // ✅ Mark Complete button (right)
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF52D494), _accentGreen],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: _accentGreen.withValues(alpha: 0.25),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.task_alt_rounded,
                            color: Colors.white,
                            size: 14,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Mark Complete',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _InfoChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
