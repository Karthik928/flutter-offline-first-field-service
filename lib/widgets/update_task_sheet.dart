import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:FieldService_app/services/employee_task_service.dart';
import 'package:FieldService_app/services/update_task_service.dart';
import 'package:FieldService_app/utils/mediaoptimizer.dart';

/// Shows the update-task bottom-sheet and returns [true] when the task
/// was successfully updated so the caller can refresh its list.
///
/// Usage:
/// ```dart
/// final updated = await UpdateTaskSheet.show(context, task: task);
/// if (updated == true) _loadTasks();
/// ```
class UpdateTaskSheet extends StatefulWidget {
  const UpdateTaskSheet({super.key, required this.task});

  final TaskItem task;

  /// Convenience helper — call this instead of [showModalBottomSheet] directly.
  static Future<bool?> show(BuildContext context, {required TaskItem task}) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => UpdateTaskSheet(task: task),
    );
  }

  @override
  State<UpdateTaskSheet> createState() => _UpdateTaskSheetState();
}

class _UpdateTaskSheetState extends State<UpdateTaskSheet>
    with SingleTickerProviderStateMixin {
  // ── Constants ────────────────────────────────────────────
  static const _green = Color(0xFF1AB69C);
  static const _greenLight = Color(0xFF52D494);
  //static const _amber = Color(0xFFF59E0B);
  static const _red = Color(0xFFEF4444);
  static const _bg = Color(0xFFF2F6F3);
  static const _cardBg = Colors.white;

  // ── State ────────────────────────────────────────────────
  final _formKey = GlobalKey<FormState>();
  final _descCtrl = TextEditingController();
  File? _pickedImage;
  bool _isLoading = false;

  final _service = UpdateTaskService();
  final _picker = ImagePicker();

  late final AnimationController _animCtrl;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  // ── Image Picker ─────────────────────────────────────────
  Future<void> _pickImage(ImageSource source) async {
    Navigator.pop(context); // close source chooser
    final xFile = await _picker.pickImage(
      source: source,
      imageQuality: 70,
      maxWidth: 1280,
    );
    if (xFile == null) return;
    setState(() => _pickedImage = File(xFile.path));
  }

  void _showImageSourceSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _cardBg,
          borderRadius: BorderRadius.circular(20),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              _SourceTile(
                icon: Icons.camera_alt_rounded,
                label: 'Take a Photo',
                color: _green,
                onTap: () => _pickImage(ImageSource.camera),
              ),
              _SourceTile(
                icon: Icons.photo_library_rounded,
                label: 'Choose from Gallery',
                color: _green,
                onTap: () => _pickImage(ImageSource.gallery),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  // ── Submit ───────────────────────────────────────────────
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    // ✅ ADD THIS BLOCK
    if (_pickedImage == null) {
      _showToast('Please upload a photo before submitting', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    // 🔥 OPTIMIZE IMAGE BEFORE UPLOAD
    final optimizedImage = await MediaOptimizer.getOptimizedImage(
      _pickedImage!,
    );

    // 🔥 OPTIONAL SIZE CHECK (prevents 413 early)
    final sizeMB = await MediaOptimizer.getFileSizeMB(
      optimizedImage ?? _pickedImage!,
    );

    if (sizeMB > 5) {
      _showToast(
        'Image too large (${sizeMB.toStringAsFixed(2)} MB). Please choose smaller image.',
        isError: true,
      );
      setState(() => _isLoading = false);
      return;
    }

    final result = await _service.updateTaskStatus(
      taskId: widget.task.id,
      status: 'completed',
      description: _descCtrl.text.trim(),
      imageFile: optimizedImage ?? _pickedImage,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result.success) {
      _showToast('Task marked as completed ✓', isError: false);
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) Navigator.of(context).pop(true); // signal refresh
    } else if (result.error == 'UNAUTHORIZED') {
      Navigator.of(context).pop(false);
    } else {
      _showToast(result.error ?? 'Something went wrong', isError: true);
    }
  }

  void _showToast(String msg, {required bool isError}) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: isError ? _red : _green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return FadeTransition(
      opacity: _fadeAnim,
      child: Container(
        margin: EdgeInsets.only(bottom: bottom),
        decoration: const BoxDecoration(
          color: _cardBg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHandle(),
                  _buildHeader(),
                  const SizedBox(height: 20),
                  _buildTaskSummaryCard(),
                  const SizedBox(height: 20),
                  _buildDescriptionField(),
                  const SizedBox(height: 20),
                  _buildImagePicker(),
                  const SizedBox(height: 28),
                  _buildSubmitButton(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Sub-widgets ──────────────────────────────────────────

  Widget _buildHandle() {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 12, bottom: 4),
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.grey[300],
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_greenLight, _green],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.task_alt_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                'Complete Task',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Colors.black87,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Fill in the details to mark as done',
                style: TextStyle(fontSize: 12, color: Colors.black38),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTaskSummaryCard() {
    final priorityColor = widget.task.priorityColor;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Type badge
              _Badge(label: widget.task.type, color: _green),
              const SizedBox(width: 8),
              // Priority badge
              _Badge(label: widget.task.priority, color: priorityColor),
              const Spacer(),
              // Due date
              Row(
                children: [
                  Icon(
                    Icons.calendar_today_rounded,
                    size: 12,
                    color: Colors.grey[500],
                  ),
                  const SizedBox(width: 4),
                  Text(
                    widget.task.dueDateLabel,
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            widget.task.title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                Icons.location_on_rounded,
                size: 13,
                color: Colors.grey[500],
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  widget.task.location,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDescriptionField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _FieldLabel(text: 'Completion Notes', required: true),
        const SizedBox(height: 8),
        TextFormField(
          controller: _descCtrl,
          maxLines: 4,
          minLines: 3,
          textCapitalization: TextCapitalization.sentences,
          style: const TextStyle(fontSize: 14, color: Colors.black87),
          decoration: InputDecoration(
            hintText: 'Describe what was done...',
            hintStyle: TextStyle(fontSize: 13, color: Colors.grey[400]),
            filled: true,
            fillColor: _bg,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _green, width: 1.6),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _red),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _red, width: 1.6),
            ),
          ),
          validator: (v) {
            if (v == null || v.trim().isEmpty) {
              return 'Please enter completion notes';
            }
            if (v.trim().length < 5) {
              return 'Notes must be at least 5 characters';
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildImagePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _FieldLabel(text: 'Attach Photo', required: true),
        const SizedBox(height: 8),
        if (_pickedImage != null)
          _buildImagePreview()
        else
          _buildPickerPlaceholder(),
      ],
    );
  }

  Widget _buildPickerPlaceholder() {
    return GestureDetector(
      onTap: _showImageSourceSheet,
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          color: _bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: const Color(0xFFE5E7EB),
            style: BorderStyle.solid,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _green.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.add_a_photo_rounded,
                  color: _green,
                  size: 20,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Tap to upload photo',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _green,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Required — camera or gallery',
                style: TextStyle(fontSize: 11, color: Colors.grey[400]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImagePreview() {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.file(
            _pickedImage!,
            width: double.infinity,
            height: 160,
            fit: BoxFit.cover,
          ),
        ),
        // Overlay buttons
        Positioned(
          top: 8,
          right: 8,
          child: Row(
            children: [
              _ImageActionBtn(
                icon: Icons.edit_rounded,
                tooltip: 'Change',
                onTap: _showImageSourceSheet,
              ),
              const SizedBox(width: 8),
              _ImageActionBtn(
                icon: Icons.delete_rounded,
                tooltip: 'Remove',
                onTap: () => setState(() => _pickedImage = null),
                color: _red,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: _isLoading
          ? Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_greenLight, _green],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.5,
                  ),
                ),
              ),
            )
          : DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_greenLight, _green],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: _green.withValues(alpha: 0.35),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: _pickedImage == null ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Mark as Completed',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

// ── Reusable helper widgets ───────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.text, this.required = false});

  final String text;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          text,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
        if (required) ...[
          const SizedBox(width: 3),
          const Text(
            '*',
            style: TextStyle(color: Color(0xFFEF4444), fontSize: 13),
          ),
        ],
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _ImageActionBtn extends StatelessWidget {
  const _ImageActionBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Tooltip(
        message: tooltip,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color ?? Colors.white, size: 18),
        ),
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    );
  }
}
