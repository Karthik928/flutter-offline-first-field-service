import 'package:flutter/material.dart';
import 'package:FieldService_app/zonal_Screens/task_create_screen.dart';
import 'package:FieldService_app/zonal_services/zonal_tasks_service.dart';
import 'package:FieldService_app/zonal_services/zonal_employee_service.dart';
import 'package:FieldService_app/zonal_services/zonal_edit_delete_task_service.dart';
import 'package:FieldService_app/zonal_services/zonal_customer_service.dart';

// ─── Constants ────────────────────────────────────────────────────────────────

const _gradientStart = Color(0xFF52D494);
const _gradientEnd = Color(0xFF1AB69C);
const _accentGreen = Color(0xFF1AB69C);
const _background = Color(0xFFF2F6F3);
const _baseImageUrl =
    'https://YOUR_API_BASE_URL'; // ← Replace with AppConfig.apiBase

// ─── Screen ───────────────────────────────────────────────────────────────────

class TaskManagerScreen extends StatefulWidget {
  const TaskManagerScreen({super.key});

  @override
  State<TaskManagerScreen> createState() => _TaskManagerScreenState();
}

class _TaskManagerScreenState extends State<TaskManagerScreen> {
  String _selectedTab = 'All';
  final List<String> _tabs = ['All', 'Pending', 'Done', 'Late'];

  late final ZonalTasksService _tasksService;
  late final ZonalEditDeleteTaskService _editDeleteService;

  List<ZonalCustomer> _customers = [];
  bool _isLoadingCustomers = false;

  List<dynamic> tasks = [];
  bool _isLoading = true;

  List<Employee> _employees = [];
  bool _isLoadingEmployees = false;

  @override
  void initState() {
    super.initState();
    _tasksService = ZonalTasksService();
    _editDeleteService = ZonalEditDeleteTaskService();
    _loadTasks();
    _loadEmployees();
    _loadCustomers();
  }

  // ─── Data Loading ─────────────────────────────────────────────────────────

  Future<void> _loadTasks() async {
    setState(() => _isLoading = true);
    final result = await _tasksService.fetchTasks();
    if (!mounted) return;
    if (result.error == 'UNAUTHORIZED') {
      Navigator.pop(context);
      return;
    }
    if (!result.success) {
      _showSnackBar(result.error ?? 'Error loading tasks', isError: true);
      setState(() => _isLoading = false);
      return;
    }
    setState(() {
      tasks = result.data ?? [];
      _isLoading = false;
    });
  }

  Future<void> _loadEmployees() async {
    setState(() => _isLoadingEmployees = true);
    final service = ZonalEmployeeService();
    final data = await service.fetchEmployees();
    if (!mounted) return;
    setState(() {
      _employees = data;
      _isLoadingEmployees = false;
    });
  }

  Future<void> _loadCustomers() async {
    setState(() => _isLoadingCustomers = true);
    final service = ZonalCustomerService();
    final res = await service.fetchCustomers();
    if (!mounted) return;
    if (!res.success) {
      _showSnackBar(res.error ?? 'Failed to load customers', isError: true);
      setState(() => _isLoadingCustomers = false);
      return;
    }
    setState(() {
      _customers = res.customers;
      _isLoadingCustomers = false;
    });
  }

  // ─── Filtering ────────────────────────────────────────────────────────────

  List<dynamic> get _filtered {
    List<dynamic> list = List.from(tasks);
    final now = DateTime.now();

    // ✅ FILTER (only if NOT ALL)
    if (_selectedTab != 'All') {
      switch (_selectedTab) {
        case 'Pending':
          list = list
              .where(
                (t) =>
                    (t['status'] ?? '').toString().toLowerCase() == 'pending',
              )
              .toList();
          break;

        case 'Done':
          list = list
              .where(
                (t) =>
                    (t['status'] ?? '').toString().toLowerCase() == 'completed',
              )
              .toList();
          break;

        case 'Late':
          list = list.where((t) {
            final due = DateTime.tryParse(t['dueDate'] ?? '');
            return due != null &&
                due.isBefore(now) &&
                (t['status'] ?? '').toString().toLowerCase() != 'completed';
          }).toList();
          break;
      }
    }

    // ✅ SORTING (CORE REQUIREMENT)
    list.sort((a, b) {
      final statusA = (a['status'] ?? '').toString().toLowerCase();
      final statusB = (b['status'] ?? '').toString().toLowerCase();

      final dateA = DateTime.tryParse(a['dueDate'] ?? '') ?? DateTime(1970);
      final dateB = DateTime.tryParse(b['dueDate'] ?? '') ?? DateTime(1970);

      // 🔥 Pending first
      if (statusA == 'pending' && statusB != 'pending') return -1;
      if (statusA != 'pending' && statusB == 'pending') return 1;

      // 🔥 Latest first
      return dateB.compareTo(dateA);
    });

    return list;
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return const Color(0xFFF59E0B);
      case 'completed':
        return _accentGreen;
      case 'late':
        return const Color(0xFFEF4444);
      default:
        return Colors.grey;
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? const Color(0xFFEF4444) : _accentGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ─── Completed Task Detail Sheet ──────────────────────────────────────────

  void _showCompletedTaskDetail(Map<String, dynamic> raw) {
    final title = raw['title'] ?? 'Task';
    final updateDescription = raw['updateDescription'] as String?;
    final updateImagePath = raw['updateImage'] as String?;
    final taskType = (raw['type'] ?? '').toString();
    final priority = raw['priority'] ?? '';
    final location = raw['location'] ?? '';
    final description = raw['description'] ?? '';
    final customerName = raw['customerName'] as String?;

    final dueDate = DateTime.tryParse(raw['dueDate'] ?? '');
    String formattedDue = 'N/A';
    if (dueDate != null) {
      formattedDue =
          '${dueDate.day.toString().padLeft(2, '0')} ${_monthName(dueDate.month)} ${dueDate.year}';
    }

    final updatedAt = DateTime.tryParse(raw['updatedAt'] ?? '');
    String completedOn = 'N/A';
    if (updatedAt != null) {
      completedOn =
          '${updatedAt.day.toString().padLeft(2, '0')} ${_monthName(updatedAt.month)} ${updatedAt.year}  ${updatedAt.hour.toString().padLeft(2, '0')}:${updatedAt.minute.toString().padLeft(2, '0')}';
    }

    final assigned = raw['assignedTo'];
    final assignedName = assigned != null
        ? '${assigned['firstName'] ?? ''} ${assigned['lastName'] ?? ''}'.trim()
        : 'Unassigned';

    final assignedBy = raw['assignedBy'];
    final assignedByName = assignedBy != null
        ? '${assignedBy['firstName'] ?? ''} ${assignedBy['lastName'] ?? ''}'
              .trim()
        : 'N/A';

    Color priorityColor;
    switch (priority) {
      case 'High':
        priorityColor = const Color(0xFFEF4444);
        break;
      case 'Medium':
        priorityColor = const Color(0xFFF59E0B);
        break;
      default:
        priorityColor = _accentGreen;
    }

    final hasImage =
        updateImagePath != null && updateImagePath.trim().isNotEmpty;
    final imageUrl = hasImage ? '$_baseImageUrl$updateImagePath' : null;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.72,
        minChildSize: 0.45,
        maxChildSize: 0.95,
        builder: (_, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Handle ──
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),

              // ── Header ──
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Green check circle
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: _accentGreen.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_circle_rounded,
                        color: _accentGreen,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              _Chip(
                                label: taskType.toUpperCase(),
                                bg: _accentGreen.withValues(alpha: 0.1),
                                fg: _accentGreen,
                              ),
                              const SizedBox(width: 6),
                              _Chip(
                                label: priority,
                                bg: priorityColor.withValues(alpha: 0.12),
                                fg: priorityColor,
                                dot: priorityColor,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.close,
                          size: 18,
                          color: Colors.black54,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              Divider(color: Colors.grey[200], height: 1),

              // ── Scrollable content ──
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                  children: [
                    // ── Task Info Grid ──
                    _SectionLabel(label: 'Task Details'),
                    const SizedBox(height: 10),
                    _InfoGrid(
                      items: [
                        _InfoItem(
                          icon: Icons.person_outline,
                          label: 'Assigned To',
                          value: assignedName,
                        ),
                        _InfoItem(
                          icon: Icons.supervisor_account_outlined,
                          label: 'Assigned By',
                          value: assignedByName,
                        ),
                        _InfoItem(
                          icon: Icons.calendar_today_outlined,
                          label: 'Due Date',
                          value: formattedDue,
                        ),
                        _InfoItem(
                          icon: Icons.access_time_rounded,
                          label: 'Completed On',
                          value: completedOn,
                        ),
                      ],
                    ),

                    if (location.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _InfoRow(
                        icon: Icons.location_on_outlined,
                        label: 'Location',
                        value: location,
                      ),
                    ],

                    if (customerName != null &&
                        customerName.trim().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      _InfoRow(
                        icon: Icons.storefront_outlined,
                        label: 'Customer',
                        value: customerName,
                      ),
                    ],

                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _SectionLabel(label: 'Description'),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF9FAFB),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFFE5E7EB),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          description,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.black54,
                            height: 1.55,
                          ),
                        ),
                      ),
                    ],

                    // ── Completion Report ──
                    const SizedBox(height: 20),
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            _accentGreen.withValues(alpha: 0.06),
                            _gradientStart.withValues(alpha: 0.04),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _accentGreen.withValues(alpha: 0.2),
                          width: 1,
                        ),
                      ),
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(7),
                                decoration: BoxDecoration(
                                  color: _accentGreen.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.task_alt_rounded,
                                  color: _accentGreen,
                                  size: 16,
                                ),
                              ),
                              const SizedBox(width: 10),
                              const Text(
                                'Completion Report',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.black87,
                                ),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: _accentGreen.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Text(
                                  'Completed',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: _accentGreen,
                                  ),
                                ),
                              ),
                            ],
                          ),

                          // ── Update Description ──
                          if (updateDescription != null &&
                              updateDescription.trim().isNotEmpty) ...[
                            const SizedBox(height: 14),
                            const Text(
                              'Update Note',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF6B7280),
                                letterSpacing: 0.3,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: _accentGreen.withValues(alpha: 0.18),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.notes_rounded,
                                    size: 15,
                                    color: _accentGreen,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      updateDescription,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: Colors.black87,
                                        height: 1.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ] else ...[
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Icon(
                                  Icons.notes_rounded,
                                  size: 15,
                                  color: Colors.grey[400],
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'No update note provided',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[400],
                                  ),
                                ),
                              ],
                            ),
                          ],

                          // ── Update Image ──
                          if (hasImage && imageUrl != null) ...[
                            const SizedBox(height: 16),
                            const Text(
                              'Proof of Completion',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF6B7280),
                                letterSpacing: 0.3,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _CompletionImage(imageUrl: imageUrl),
                          ],
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

  String _monthName(int month) {
    const months = [
      '',
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
    return months[month];
  }

  // ─── Delete ───────────────────────────────────────────────────────────────

  Future<void> _confirmDelete(String taskId, String taskTitle) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        backgroundColor: Colors.white,
        title: const Row(
          children: [
            Icon(
              Icons.delete_outline_rounded,
              color: Color(0xFFEF4444),
              size: 22,
            ),
            SizedBox(width: 8),
            Text(
              'Delete Task',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to delete "$taskTitle"? This action cannot be undone.',
          style: const TextStyle(
            fontSize: 13,
            color: Colors.black54,
            height: 1.5,
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFFE5E7EB)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              foregroundColor: Colors.black54,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Delete',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final result = await _editDeleteService.deleteTask(taskId);
    if (!mounted) return;

    if (result.success) {
      _showSnackBar('Task deleted successfully');
      _loadTasks();
    } else {
      _showSnackBar(result.error ?? 'Failed to delete task', isError: true);
    }
  }

  // ─── Edit Bottom Sheet ────────────────────────────────────────────────────

  void _showEditSheet(Map<String, dynamic> rawTask) {
    final taskId = rawTask['_id'] ?? '';
    final titleCtrl = TextEditingController(text: rawTask['title'] ?? '');
    final locationCtrl = TextEditingController(text: rawTask['location'] ?? '');
    final descCtrl = TextEditingController(text: rawTask['description'] ?? '');

    String taskType = rawTask['type'] ?? 'Dealer Visit';
    String priority = rawTask['priority'] ?? 'Medium';
    DateTime? dueDate = DateTime.tryParse(rawTask['dueDate'] ?? '');

    final assignedRaw = rawTask['assignedTo'];
    String assigneeId = assignedRaw?['_id'] ?? '';
    String assigneeName = assignedRaw != null
        ? '${assignedRaw['firstName'] ?? ''} ${assignedRaw['lastName'] ?? ''}'
              .trim()
        : 'Choose Employee';

    bool isSubmitting = false;

    final taskTypes = [
      'Dealer Visit',
      'Farmer Visit',
      'Payment Purpose',
      'Order Visit',
      'Other',
    ];
    final priorities = ['High', 'Medium', 'Low'];

    String? customerName = rawTask['customerName'];
    String customerDisplay = rawTask['customerName'] ?? 'Choose Customer';

    Color priorityColor(String p) {
      switch (p) {
        case 'High':
          return const Color(0xFFEF4444);
        case 'Medium':
          return const Color(0xFFF59E0B);
        default:
          return _accentGreen;
      }
    }

    String formatDate(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')} / ${d.month.toString().padLeft(2, '0')} / ${d.year}';

    String daysUntil(DateTime d) {
      final diff = d.difference(DateTime.now()).inDays;
      if (diff == 0) return 'today';
      if (diff == 1) return 'tomorrow';
      if (diff < 0) return '${diff.abs()} days ago';
      return 'in $diff days';
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          void showPicker({
            required String title,
            required List<String> options,
            required String selected,
            required ValueChanged<String> onSelected,
            Color Function(String)? colorBuilder,
          }) {
            showModalBottomSheet(
              context: ctx,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Divider(color: Colors.grey[200]),
                    const SizedBox(height: 4),
                    ...options.map((opt) {
                      final isSel = opt == selected;
                      final color = colorBuilder?.call(opt) ?? _accentGreen;
                      return GestureDetector(
                        onTap: () {
                          onSelected(opt);
                          Navigator.pop(ctx);
                        },
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 13,
                          ),
                          decoration: BoxDecoration(
                            color: isSel
                                ? _accentGreen.withValues(alpha: 0.08)
                                : Colors.grey[50],
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isSel ? _accentGreen : Colors.transparent,
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                opt,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: isSel
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: isSel ? _accentGreen : Colors.black87,
                                ),
                              ),
                              const Spacer(),
                              if (isSel)
                                const Icon(
                                  Icons.check_circle_rounded,
                                  color: _accentGreen,
                                  size: 20,
                                ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            );
          }

          Widget label(String text) => Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF6B7280),
              letterSpacing: 0.3,
            ),
          );

          Widget buildField({
            required String lbl,
            required String hint,
            required TextEditingController ctrl,
            required IconData icon,
            int maxLines = 1,
            bool readOnly = false,
          }) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                label(lbl),
                const SizedBox(height: 8),
                TextField(
                  controller: ctrl,
                  readOnly: readOnly,
                  maxLines: maxLines,
                  style: const TextStyle(fontSize: 14, color: Colors.black87),
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: TextStyle(fontSize: 13, color: Colors.grey[400]),
                    prefixIcon: Icon(icon, size: 18, color: _accentGreen),
                    filled: true,
                    fillColor: const Color(0xFFF9FAFB),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 13,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: Color(0xFFE5E7EB),
                        width: 1,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: _accentGreen,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ],
            );
          }

          Widget buildSelector({
            required String lbl,
            required String value,
            required IconData icon,
            required Color iconColor,
            required VoidCallback onTap,
            Color? badgeColor,
          }) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                label(lbl),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: onTap,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9FAFB),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFFE5E7EB),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: iconColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(icon, size: 16, color: iconColor),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            value,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: value.contains('Choose')
                                  ? Colors.grey[400]
                                  : Colors.black87,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (badgeColor != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: badgeColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                        ],
                        Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: Colors.grey[400],
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }

          Future<void> submitEdit() async {
            if (titleCtrl.text.trim().isEmpty) {
              _showSnackBar('Please enter a task title', isError: true);
              return;
            }
            if (assigneeId.isEmpty) {
              _showSnackBar('Please select an employee', isError: true);
              return;
            }
            if (customerName == null || customerName!.isEmpty) {
              _showSnackBar('Please select a customer', isError: true);
              return;
            }
            if (locationCtrl.text.trim().isEmpty) {
              _showSnackBar('Customer address missing', isError: true);
              return;
            }
            if (dueDate == null) {
              _showSnackBar('Please select a due date', isError: true);
              return;
            }
            if (descCtrl.text.trim().isEmpty) {
              _showSnackBar('Please enter a description', isError: true);
              return;
            }

            setSheetState(() => isSubmitting = true);
            final result = await _editDeleteService.updateTask(
              taskId: taskId,
              title: titleCtrl.text.trim(),
              type: taskType,
              priority: priority,
              assignedTo: assigneeId,
              location: locationCtrl.text.trim(),
              customerName: customerName!,
              dueDate:
                  '${dueDate!.year}-${dueDate!.month.toString().padLeft(2, '0')}-${dueDate!.day.toString().padLeft(2, '0')}',
              description: descCtrl.text.trim(),
            );
            setSheetState(() => isSubmitting = false);

            if (!mounted || !ctx.mounted) return;
            if (result.success) {
              Navigator.pop(ctx);
              _showSnackBar('Task updated successfully');
              _loadTasks();
            } else {
              _showSnackBar(
                result.error ?? 'Failed to update task',
                isError: true,
              );
            }
          }

          return DraggableScrollableSheet(
            initialChildSize: 0.92,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            builder: (_, scrollController) => Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: Column(
                      children: [
                        Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.grey[300],
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            const Text(
                              'Edit Task',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: Colors.black87,
                              ),
                            ),
                            const Spacer(),
                            GestureDetector(
                              onTap: () => Navigator.pop(ctx),
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: Colors.grey[100],
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.close,
                                  size: 18,
                                  color: Colors.black54,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Divider(color: Colors.grey[200], height: 1),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                      children: [
                        buildField(
                          lbl: 'Task Title',
                          hint: 'e.g., Follow up on monthly payment',
                          ctrl: titleCtrl,
                          icon: Icons.title_outlined,
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: buildSelector(
                                lbl: 'Task Type',
                                value: taskType,
                                icon: Icons.task_outlined,
                                iconColor: _accentGreen,
                                onTap: () => showPicker(
                                  title: 'Select Task Type',
                                  options: taskTypes,
                                  selected: taskType,
                                  onSelected: (v) =>
                                      setSheetState(() => taskType = v),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: buildSelector(
                                lbl: 'Priority',
                                value: priority,
                                icon: Icons.flag_outlined,
                                iconColor: priorityColor(priority),
                                badgeColor: priorityColor(priority),
                                onTap: () => showPicker(
                                  title: 'Select Priority',
                                  options: priorities,
                                  selected: priority,
                                  colorBuilder: priorityColor,
                                  onSelected: (v) =>
                                      setSheetState(() => priority = v),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        buildSelector(
                          lbl: 'Assign Employee',
                          value: assigneeName,
                          icon: Icons.person_outline,
                          iconColor: _accentGreen,
                          onTap: () {
                            if (_isLoadingEmployees) return;
                            showPicker(
                              title: 'Select Employee',
                              options: _employees.map((e) => e.name).toList(),
                              selected: assigneeName,
                              onSelected: (name) {
                                final emp = _employees.firstWhere(
                                  (e) => e.name == name,
                                );
                                setSheetState(() {
                                  assigneeName = emp.name;
                                  assigneeId = emp.id;
                                });
                              },
                            );
                          },
                        ),
                        const SizedBox(height: 14),
                        buildSelector(
                          lbl: 'Customer Name',
                          value: customerDisplay,
                          icon: Icons.storefront_outlined,
                          iconColor: _accentGreen,
                          onTap: () {
                            if (_isLoadingCustomers) return;
                            showPicker(
                              title: 'Select Customer',
                              options: _customers
                                  .map((c) => c.displayName)
                                  .toList(),
                              selected: customerDisplay,
                              onSelected: (name) {
                                final selected = _customers.firstWhere(
                                  (c) => c.displayName == name,
                                );
                                setSheetState(() {
                                  customerDisplay = selected.displayName;
                                  customerName = selected.name;
                                  locationCtrl.text = selected.address ?? '';
                                });
                              },
                            );
                          },
                        ),
                        const SizedBox(height: 14),
                        buildField(
                          lbl: 'Location',
                          hint: 'Auto-filled from customer',
                          ctrl: locationCtrl,
                          icon: Icons.location_on_outlined,
                          readOnly: true,
                        ),
                        const SizedBox(height: 14),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            label('Due Date'),
                            const SizedBox(height: 8),
                            GestureDetector(
                              onTap: () async {
                                final now = DateTime.now();
                                final today = DateTime(
                                  now.year,
                                  now.month,
                                  now.day,
                                );

                                // ✅ Ensure initialDate is valid
                                final safeInitialDate =
                                    (dueDate != null &&
                                        dueDate!.isBefore(today))
                                    ? today
                                    : (dueDate ?? today);

                                final picked = await showDatePicker(
                                  context: ctx,
                                  initialDate: safeInitialDate, // ✅ FIX
                                  firstDate: today, // ✅ no past dates
                                  lastDate: DateTime(2100),
                                  builder: (context, child) => Theme(
                                    data: Theme.of(context).copyWith(
                                      colorScheme: const ColorScheme.light(
                                        primary: _accentGreen,
                                        onPrimary: Colors.white,
                                        onSurface: Colors.black87,
                                        surface: Colors.white,
                                        secondary: _accentGreen,
                                      ),
                                    ),
                                    child: child!,
                                  ),
                                );

                                if (picked != null) {
                                  setSheetState(() => dueDate = picked);
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF9FAFB),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: dueDate != null
                                        ? _accentGreen
                                        : const Color(0xFFE5E7EB),
                                    width: dueDate != null ? 1.5 : 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 30,
                                      height: 30,
                                      decoration: BoxDecoration(
                                        color: _accentGreen.withValues(
                                          alpha: 0.12,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(
                                        Icons.calendar_today_outlined,
                                        size: 16,
                                        color: _accentGreen,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        dueDate == null
                                            ? 'Select a due date'
                                            : formatDate(dueDate!),
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: dueDate == null
                                              ? Colors.grey[400]
                                              : Colors.black87,
                                        ),
                                      ),
                                    ),
                                    if (dueDate != null)
                                      GestureDetector(
                                        onTap: () =>
                                            setSheetState(() => dueDate = null),
                                        child: const Icon(
                                          Icons.close,
                                          size: 16,
                                          color: Colors.grey,
                                        ),
                                      )
                                    else
                                      Icon(
                                        Icons.keyboard_arrow_down_rounded,
                                        color: Colors.grey[400],
                                        size: 20,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            if (dueDate != null) ...[
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.check_circle_outline,
                                    size: 13,
                                    color: _accentGreen,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Due ${daysUntil(dueDate!)}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: _accentGreen,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 14),
                        buildField(
                          lbl: 'Description',
                          hint:
                              'Provide specific instructions for this task...',
                          ctrl: descCtrl,
                          icon: Icons.notes_outlined,
                          maxLines: 4,
                        ),
                        const SizedBox(height: 24),
                        Container(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [_gradientStart, _gradientEnd],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: _accentGreen.withValues(alpha: 0.35),
                                blurRadius: 14,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              minimumSize: const Size(double.infinity, 52),
                            ),
                            icon: isSubmitting
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  )
                                : const Icon(
                                    Icons.check_circle_outline,
                                    size: 20,
                                  ),
                            label: Text(
                              isSubmitting ? 'Saving...' : 'Save Changes',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.3,
                              ),
                            ),
                            onPressed: isSubmitting ? null : submitEdit,
                          ),
                        ),
                      ],
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

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: _buildAppBar(),
      floatingActionButton: _buildFab(),
      body: Column(
        children: [
          _buildTabBar(),
          Expanded(child: _buildTaskList()),
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
            'Task Manager',
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
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _tabs.map((tab) {
            final isSelected = _selectedTab == tab;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => setState(() => _selectedTab = tab),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected ? _accentGreen : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected
                          ? _accentGreen
                          : const Color(0xFFE5E7EB),
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: _accentGreen.withValues(alpha: 0.25),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : [],
                  ),
                  child: Text(
                    tab,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white : Colors.black54,
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

  Widget _buildTaskList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final list = _filtered;

    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, size: 48, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text(
              'No tasks in "$_selectedTab"',
              style: TextStyle(fontSize: 14, color: Colors.grey[400]),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
      itemCount: list.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final raw = list[index] as Map<String, dynamic>;
        final task = _TaskData.fromApi(raw);
        final isPending =
            (raw['status'] ?? '').toString().toLowerCase() == 'pending';
        final isCompleted =
            (raw['status'] ?? '').toString().toLowerCase() == 'completed';

        return _TaskCard(
          task: task,
          statusColor: _statusColor(task.status),
          isPending: isPending,
          isCompleted: isCompleted,
          onEdit: isPending ? () => _showEditSheet(raw) : null,
          onDelete: isPending
              ? () => _confirmDelete(raw['_id'] ?? '', task.title)
              : null,
          onViewDetails: isCompleted
              ? () => _showCompletedTaskDetail(raw)
              : null,
        );
      },
    );
  }

  Widget _buildFab() {
    return FloatingActionButton.extended(
      onPressed: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => TaskCreateScreen())),
      backgroundColor: _accentGreen,
      foregroundColor: Colors.white,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      icon: const Icon(Icons.add, size: 20),
      label: const Text(
        'New Task',
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
    );
  }
}

// ─── Data Model ───────────────────────────────────────────────────────────────

class _TaskData {
  final String category;
  final String priority;
  final Color priorityColor;
  final String title;
  final String assignedTo;
  final String timeInfo;
  final String status;

  const _TaskData({
    required this.category,
    required this.priority,
    required this.priorityColor,
    required this.title,
    required this.assignedTo,
    required this.timeInfo,
    required this.status,
  });

  factory _TaskData.fromApi(Map<String, dynamic> json) {
    final assigned = json['assignedTo'];
    final assignedName = assigned != null
        ? '${assigned['firstName'] ?? ''} ${assigned['lastName'] ?? ''}'
        : 'Unassigned';

    final dueDate = DateTime.tryParse(json['dueDate'] ?? '');
    String formattedDate = 'No Date';
    if (dueDate != null) {
      formattedDate = '${dueDate.day}/${dueDate.month}/${dueDate.year}';
    }

    Color priorityColor;
    switch (json['priority']) {
      case 'High':
        priorityColor = const Color(0xFFF59E0B);
        break;
      case 'Medium':
        priorityColor = const Color(0xFF4D8AF0);
        break;
      case 'Low':
        priorityColor = const Color(0xFF1AB69C);
        break;
      default:
        priorityColor = Colors.grey;
    }

    return _TaskData(
      category: (json['type'] ?? '').toUpperCase(),
      priority: json['priority'] ?? '',
      priorityColor: priorityColor,
      title: json['title'] ?? '',
      assignedTo: assignedName.trim(),
      timeInfo: formattedDate,
      status: (json['status'] ?? ''),
    );
  }
}

extension StringExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    return this[0].toUpperCase() + substring(1);
  }
}

// ─── Task Card ────────────────────────────────────────────────────────────────

class _TaskCard extends StatelessWidget {
  final _TaskData task;
  final Color statusColor;
  final bool isPending;
  final bool isCompleted;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onViewDetails;

  const _TaskCard({
    required this.task,
    required this.statusColor,
    required this.isPending,
    required this.isCompleted,
    this.onEdit,
    this.onDelete,
    this.onViewDetails,
  });

  @override
  Widget build(BuildContext context) {
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
          // ── Category + Priority ──
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
                  task.category,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: _accentGreen,
                    letterSpacing: 0.3,
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
                  color: task.priorityColor.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: task.priorityColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      task.priority,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: task.priorityColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          Text(
            task.title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),

          const SizedBox(height: 8),

          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: _accentGreen.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    task.assignedTo.isNotEmpty ? task.assignedTo[0] : '?',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: _accentGreen,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  task.assignedTo,
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),
          const Divider(height: 1, thickness: 0.5, color: Color(0xFFF0F0F0)),
          const SizedBox(height: 10),

          Row(
            children: [
              const Icon(
                Icons.access_time_rounded,
                size: 14,
                color: Colors.black38,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  task.timeInfo,
                  style: const TextStyle(fontSize: 12, color: Colors.black45),
                ),
              ),
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

          // ── Actions for pending ──
          if (isPending) ...[
            const SizedBox(height: 12),
            const Divider(height: 1, thickness: 0.5, color: Color(0xFFF0F0F0)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(
                        color: Color(0xFF1AB69C),
                        width: 1,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      foregroundColor: _accentGreen,
                      padding: const EdgeInsets.symmetric(vertical: 9),
                    ),
                    icon: const Icon(Icons.edit_outlined, size: 15),
                    label: const Text(
                      'Edit',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onPressed: onEdit,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(
                        color: Color(0xFFEF4444),
                        width: 1,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      foregroundColor: const Color(0xFFEF4444),
                      padding: const EdgeInsets.symmetric(vertical: 9),
                    ),
                    icon: const Icon(Icons.delete_outline_rounded, size: 15),
                    label: const Text(
                      'Delete',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onPressed: onDelete,
                  ),
                ),
              ],
            ),
          ],

          // ── View Details for completed ──
          if (isCompleted) ...[
            const SizedBox(height: 12),
            const Divider(height: 1, thickness: 0.5, color: Color(0xFFF0F0F0)),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: _accentGreen.withValues(alpha: 0.4),
                    width: 1,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  foregroundColor: _accentGreen,
                  backgroundColor: _accentGreen.withValues(alpha: 0.05),
                  padding: const EdgeInsets.symmetric(vertical: 9),
                ),
                icon: const Icon(Icons.task_alt_rounded, size: 15),
                label: const Text(
                  'View Completion Report',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                onPressed: onViewDetails,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Reusable Widgets ─────────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;
  final Color? dot;

  const _Chip({
    required this.label,
    required this.bg,
    required this.fg,
    this.dot,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot != null) ...[
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: fg,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        color: Color(0xFF6B7280),
        letterSpacing: 0.5,
      ),
    );
  }
}

class _InfoGrid extends StatelessWidget {
  final List<_InfoItem> items;
  const _InfoGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 2.4,
      children: items
          .map(
            (item) => Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
              ),
              child: Row(
                children: [
                  Icon(item.icon, size: 14, color: _accentGreen),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          item.label,
                          style: const TextStyle(
                            fontSize: 9,
                            color: Color(0xFF9CA3AF),
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.value,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _InfoItem {
  final IconData icon;
  final String label;
  final String value;
  const _InfoItem({
    required this.icon,
    required this.label,
    required this.value,
  });
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: _accentGreen),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF9CA3AF),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Completion Image Widget ──────────────────────────────────────────────────

class _CompletionImage extends StatefulWidget {
  final String imageUrl;
  const _CompletionImage({required this.imageUrl});

  @override
  State<_CompletionImage> createState() => _CompletionImageState();
}

class _CompletionImageState extends State<_CompletionImage> {
  bool _hasError = false;

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Container(
        width: double.infinity,
        height: 140,
        decoration: BoxDecoration(
          color: const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.broken_image_outlined,
              size: 32,
              color: Colors.grey[300],
            ),
            const SizedBox(height: 6),
            Text(
              'Image unavailable',
              style: TextStyle(fontSize: 11, color: Colors.grey[400]),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: () => _showFullImage(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            Image.network(
              widget.imageUrl,
              width: double.infinity,
              height: 180,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) {
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => setState(() => _hasError = true),
                );
                return const SizedBox.shrink();
              },
              loadingBuilder: (_, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return Container(
                  width: double.infinity,
                  height: 180,
                  color: const Color(0xFFF9FAFB),
                  child: Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _accentGreen,
                      value: loadingProgress.expectedTotalBytes != null
                          ? loadingProgress.cumulativeBytesLoaded /
                                loadingProgress.expectedTotalBytes!
                          : null,
                    ),
                  ),
                );
              },
            ),
            Positioned(
              bottom: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.zoom_in_rounded, size: 12, color: Colors.white),
                    SizedBox(width: 4),
                    Text(
                      'Tap to expand',
                      style: TextStyle(fontSize: 10, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showFullImage(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            iconTheme: const IconThemeData(color: Colors.white),
            title: const Text(
              'Proof of Completion',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
          body: Center(
            child: InteractiveViewer(
              child: Image.network(
                widget.imageUrl,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const Center(
                  child: Text(
                    'Image failed to load',
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
