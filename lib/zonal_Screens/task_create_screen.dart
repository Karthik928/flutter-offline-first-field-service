import 'package:flutter/material.dart';
import 'package:FieldService_app/zonal_services/zonal_customer_service.dart';
import 'package:FieldService_app/zonal_services/zonal_employee_service.dart';
import 'package:FieldService_app/zonal_services/zonal_create_task_service.dart';

class TaskCreateScreen extends StatefulWidget {
  const TaskCreateScreen({super.key});

  @override
  State<TaskCreateScreen> createState() => _TaskCreateScreenState();
}

class _TaskCreateScreenState extends State<TaskCreateScreen> {
  static const _gradientStart = Color(0xFF52D494);
  static const _gradientEnd = Color(0xFF1AB69C);
  static const _accentGreen = Color(0xFF1AB69C);
  static const _background = Color(0xFFF2F6F3);
  static const _cardBg = Colors.white;
  static const _labelColor = Color(0xFF6B7280);
  static const _borderColor = Color(0xFFE5E7EB);

  final _titleController = TextEditingController();
  final _locationController = TextEditingController();
  final _descriptionController = TextEditingController();

  String _taskType = 'Dealer Visit';
  String _priority = 'Medium';
  DateTime? _dueDate;

  final _taskTypes = [
    "Dealer Visit",
    "Farmer Visit",
    "Payment Purpose",
    "Order Visit",
    "Other",
  ];
  final _priorities = ['High', 'Medium', 'Low'];
  List<Employee> _employees = [];
  bool _isLoadingEmployees = false;

  String? _assigneeId;
  String _assigneeName = 'Choose Employee';

  List<ZonalCustomer> _customers = [];
  bool _isLoadingCustomers = false;

  String? _customerName; // actual value for API
  String _customerDisplay = 'Choose Customer'; // UI

  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadEmployees();
    _loadCustomers();
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
    final data = await service.fetchCustomers();

    if (!mounted) return;

    if (!data.success) {
      _showSnackBar(data.error ?? 'Failed to load customers', isError: true);
      setState(() => _isLoadingCustomers = false);
      return;
    }

    setState(() {
      _customers = data.customers;
      _isLoadingCustomers = false;
    });
  }

  Color _priorityColor(String p) {
    switch (p) {
      case 'High':
        return const Color(0xFFEF4444);
      case 'Medium':
        return const Color(0xFFF59E0B);
      case 'Low':
        return _accentGreen;
      default:
        return _accentGreen;
    }
  }

  IconData _taskTypeIcon(String t) {
    switch (t) {
      case 'Dealer Visit':
        return Icons.storefront_outlined;
      case 'Payment Collection':
        return Icons.currency_rupee;
      case 'Pond Visit':
        return Icons.water_drop_outlined;
      case 'Onboarding':
        return Icons.person_add_alt_1_outlined;
      default:
        return Icons.task_outlined;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _locationController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  // ─── Bottom Sheet Picker ──────────────────────────────────────────────────

  void _showOptionPicker({
    required String title,
    required List<String> options,
    required String selected,
    required ValueChanged<String> onSelected,
    Color Function(String)? colorBuilder,
    IconData Function(String)? iconBuilder,
  }) {
    showModalBottomSheet(
      context: context,
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
              final isSelected = opt == selected;
              final color = colorBuilder?.call(opt) ?? _accentGreen;
              final icon = iconBuilder?.call(opt);
              return GestureDetector(
                onTap: () {
                  onSelected(opt);
                  Navigator.pop(context);
                },
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 13,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? _accentGreen.withValues(alpha: 0.08)
                        : Colors.grey[50],
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected ? _accentGreen : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      if (icon != null) ...[
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Icon(icon, size: 18, color: color),
                        ),
                        const SizedBox(width: 12),
                      ] else ...[
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Text(
                        opt,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: isSelected ? _accentGreen : Colors.black87,
                        ),
                      ),
                      const Spacer(),
                      if (isSelected)
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

  // ─── Date Picker ──────────────────────────────────────────────────────────

  Future<void> _pickDate() async {
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now(),
      firstDate: todayOnly,
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: _accentGreen,
              onPrimary: Colors.white,
              onSurface: Colors.black87,
              surface: Colors.white,
              secondary: _accentGreen,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(foregroundColor: _accentGreen),
            ),
            dialogTheme: DialogThemeData(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')} / ${d.month.toString().padLeft(2, '0')} / ${d.year}';

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: _buildAppBar(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSectionCard(
              children: [
                _buildTextField(
                  label: 'Task Title',
                  hint: 'e.g., Follow up on monthly payment',
                  controller: _titleController,
                  icon: Icons.title_outlined,
                ),
              ],
            ),
            const SizedBox(height: 14),
            _buildSectionCard(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildSelectorField(
                        label: 'Task Type',
                        value: _taskType,
                        icon: _taskTypeIcon(_taskType),
                        iconColor: _accentGreen,
                        onTap: () => _showOptionPicker(
                          title: 'Select Task Type',
                          options: _taskTypes,
                          selected: _taskType,
                          colorBuilder: (_) => _accentGreen,
                          iconBuilder: _taskTypeIcon,
                          onSelected: (v) => setState(() => _taskType = v),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildSelectorField(
                        label: 'Priority',
                        value: _priority,
                        icon: Icons.flag_outlined,
                        iconColor: _priorityColor(_priority),
                        badgeColor: _priorityColor(_priority),
                        onTap: () => _showOptionPicker(
                          title: 'Select Priority',
                          options: _priorities,
                          selected: _priority,
                          colorBuilder: _priorityColor,
                          onSelected: (v) => setState(() => _priority = v),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            _buildSectionCard(
              children: [
                _buildSelectorField(
                  label: 'Assign Employee',
                  value: _assigneeName,
                  icon: Icons.person_outline,
                  iconColor: _accentGreen,
                  fullWidth: true,
                  onTap: () {
                    if (_isLoadingEmployees) return;

                    _showOptionPicker(
                      title: 'Select Employee',
                      options: _employees.map((e) => e.name).toList(),
                      selected: _assigneeName,
                      iconBuilder: (_) => Icons.person_outline,
                      onSelected: (name) {
                        final selected = _employees.firstWhere(
                          (e) => e.name == name,
                        );

                        setState(() {
                          _assigneeName = selected.name;
                          _assigneeId = selected.id; // 🔥 IMPORTANT
                        });
                      },
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 14),
            _buildSectionCard(
              children: [
                _buildSectionCard(
                  children: [
                    // ✅ Customer Selector
                    _buildSelectorField(
                      label: 'Customer Name',
                      value: _customerDisplay,
                      icon: Icons.storefront_outlined,
                      iconColor: _accentGreen,
                      fullWidth: true,
                      onTap: () {
                        if (_isLoadingCustomers) return;

                        _showOptionPicker(
                          title: 'Select Customer',
                          options: _customers
                              .map((c) => c.displayName)
                              .toList(),
                          selected: _customerDisplay,
                          iconBuilder: (_) => Icons.storefront_outlined,
                          onSelected: (name) {
                            final selected = _customers.firstWhere(
                              (c) => c.displayName == name,
                            );

                            setState(() {
                              _customerDisplay = selected.displayName;
                              _customerName = selected.name; // 👈 IMPORTANT

                              // ✅ Auto-fill location
                              _locationController.text = selected.address ?? '';
                            });
                          },
                        );
                      },
                    ),

                    const SizedBox(height: 14),

                    // ✅ Location (READ ONLY)
                    _buildTextField(
                      label: 'Location',
                      hint: 'Auto-filled from customer',
                      controller: _locationController,
                      icon: Icons.location_on_outlined,
                      readOnly: true,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            _buildSectionCard(children: [_buildDateField()]),
            const SizedBox(height: 14),
            _buildSectionCard(
              children: [
                _buildTextField(
                  label: 'Description',
                  hint: 'Provide specific instructions for this task...',
                  controller: _descriptionController,
                  icon: Icons.notes_outlined,
                  maxLines: 5,
                ),
              ],
            ),
            const SizedBox(height: 24),
            _buildSubmitButton(),
          ],
        ),
      ),
    );
  }

  // ─── App Bar ──────────────────────────────────────────────────────────────

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
            'Create New Task',
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

  // ─── Section Card Wrapper ─────────────────────────────────────────────────

  Widget _buildSectionCard({required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  // ─── Text Field ───────────────────────────────────────────────────────────

  Widget _buildTextField({
    required String label,
    required String hint,
    required TextEditingController controller,
    required IconData icon,
    int maxLines = 1,
    bool readOnly = false, // 👈 ADD
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel(label),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          readOnly: readOnly, // 👈 ADD
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
              borderSide: const BorderSide(color: _borderColor, width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _accentGreen, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  // ─── Selector Field (replaces Dropdown) ──────────────────────────────────

  Widget _buildSelectorField({
    required String label,
    required String value,
    required IconData icon,
    required Color iconColor,
    required VoidCallback onTap,
    Color? badgeColor,
    bool fullWidth = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel(label),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: fullWidth ? double.infinity : null,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _borderColor, width: 1),
            ),
            child: Row(
              mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
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

  // ─── Date Field ───────────────────────────────────────────────────────────

  Widget _buildDateField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel('Due Date'),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _pickDate,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _dueDate != null ? _accentGreen : _borderColor,
                width: _dueDate != null ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: _accentGreen.withValues(alpha: 0.12),
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
                    _dueDate == null
                        ? 'Select a due date'
                        : _formatDate(_dueDate!),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _dueDate == null
                          ? Colors.grey[400]
                          : Colors.black87,
                    ),
                  ),
                ),
                if (_dueDate != null)
                  GestureDetector(
                    onTap: () => setState(() => _dueDate = null),
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
        if (_dueDate != null) ...[
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
                'Due ${_daysUntil(_dueDate!)}',
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
    );
  }

  String _daysUntil(DateTime d) {
    final diff = d.difference(DateTime.now()).inDays;
    if (diff == 0) return 'today';
    if (diff == 1) return 'tomorrow';
    if (diff < 0) return '${diff.abs()} days ago';
    return 'in $diff days';
  }

  // ─── Submit Task ──────────────────────────────────────────────────────────

  Future<void> _submitTask() async {
    // Validation
    if (_titleController.text.trim().isEmpty) {
      _showSnackBar('Please enter a task title', isError: true);
      return;
    }
    if (_assigneeId == null) {
      _showSnackBar('Please select an employee', isError: true);
      return;
    }
    if (_customerName == null) {
      _showSnackBar('Please select a customer', isError: true);
      return;
    }

    if (_locationController.text.trim().isEmpty) {
      _showSnackBar('Customer address missing', isError: true);
      return;
    }
    if (_dueDate == null) {
      _showSnackBar('Please select a due date', isError: true);
      return;
    }
    if (_descriptionController.text.trim().isEmpty) {
      _showSnackBar('Please enter a description', isError: true);
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final service = ZonalCreateTaskService();
      final response = await service.createTask(
        title: _titleController.text.trim(),
        type: _taskType,
        priority: _priority,
        assignedTo: _assigneeId!,
        location: _locationController.text.trim(),
        customerName: _customerName!,
        dueDate:
            "${_dueDate!.year}-${_dueDate!.month.toString().padLeft(2, '0')}-${_dueDate!.day.toString().padLeft(2, '0')}",
        description: _descriptionController.text.trim(),
      );
      if (!mounted) return;

      if (response.success) {
        _showSnackBar('Task created successfully!');
        // Clear form or navigate back
        _clearForm();
        // Optionally navigate back
        Navigator.of(context).pop();
      } else {
        _showSnackBar(response.error ?? 'Failed to create task', isError: true);
      }
    } catch (e) {
      _showSnackBar('An error occurred: ${e.toString()}', isError: true);
    } finally {
      setState(() => _isSubmitting = false);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : _accentGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _clearForm() {
    _titleController.clear();
    _locationController.clear();
    _descriptionController.clear();
    setState(() {
      _taskType = 'Dealer Visit';
      _priority = 'Medium';
      _assigneeId = null;
      _assigneeName = 'Choose Employee';
      _dueDate = null;
      _customerName = null;
      _customerDisplay = 'Choose Customer';
      _locationController.clear();
    });
  }

  // ─── Label ────────────────────────────────────────────────────────────────

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: _labelColor,
        letterSpacing: 0.3,
      ),
    );
  }

  // ─── Submit Button ────────────────────────────────────────────────────────

  Widget _buildSubmitButton() {
    return Container(
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
        icon: _isSubmitting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Icon(Icons.check_circle_outline, size: 20),
        label: Text(
          _isSubmitting ? 'Submitting...' : 'Submit Task',
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
        onPressed: _isSubmitting ? null : _submitTask,
      ),
    );
  }
}
