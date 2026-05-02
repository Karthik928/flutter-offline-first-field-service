import 'package:flutter/material.dart';
import 'package:FieldService_app/config.dart';
import 'package:FieldService_app/services/employee_task_service.dart';

/// A polished bottom sheet that displays full details of a completed task,
/// including the completion image, description, location, and metadata.
class TaskDetailsSheet extends StatelessWidget {
  final TaskItem task;

  static const _accentGreen = Color(0xFF1AB69C);
  static const _background = Color(0xFFF2F6F3);

  const TaskDetailsSheet({super.key, required this.task});

  /// Call this static helper to show the sheet.
  static Future<void> show(BuildContext context, {required TaskItem task}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TaskDetailsSheet(task: task),
    );
  }

  @override
  Widget build(BuildContext context) {
    //final screenHeight = MediaQuery.of(context).size.height;

    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: _background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              // ── Drag handle ──────────────────────────────
              _DragHandle(),

              // ── Header ───────────────────────────────────
              _SheetHeader(task: task),

              // ── Scrollable body ──────────────────────────
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  children: [
                    // Completion image
                    if (task.updateImage != null &&
                        task.updateImage!.isNotEmpty)
                      _CompletionImageCard(imageUrl: task.updateImage!),

                    const SizedBox(height: 16),

                    // Status banner
                    _CompletionBanner(),

                    const SizedBox(height: 16),

                    // Task info grid
                    _InfoGrid(task: task),

                    const SizedBox(height: 16),

                    // Description
                    _SectionCard(
                      icon: Icons.description_outlined,
                      title: 'Task Description',
                      child: Text(
                        task.description,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF374151),
                          height: 1.55,
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Completion note
                    if (task.updateDescription != null &&
                        task.updateDescription!.isNotEmpty)
                      _SectionCard(
                        icon: Icons.check_circle_outline,
                        title: 'Completion Note',
                        iconColor: _accentGreen,
                        child: Text(
                          task.updateDescription!,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF374151),
                            height: 1.55,
                          ),
                        ),
                      ),

                    const SizedBox(height: 12),

                    // Location
                    _SectionCard(
                      icon: Icons.location_on_outlined,
                      title: 'Location',
                      child: Text(
                        task.location,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF374151),
                          height: 1.55,
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Assignment info
                    _AssignmentCard(task: task),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _DragHandle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Center(
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: const Color(0xFFD1D5DB),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }
}

class _SheetHeader extends StatelessWidget {
  final TaskItem task;

  static const _gradientStart = Color(0xFF52D494);
  static const _gradientEnd = Color(0xFF1AB69C);
  static const _accentGreen = Color(0xFF1AB69C);

  const _SheetHeader({required this.task});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_gradientStart, _gradientEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _accentGreen.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          // Task type icon bubble
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.task_alt_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          // Title + type
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    task.type,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Close button
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, color: Colors.white, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompletionImageCard extends StatefulWidget {
  final String imageUrl;

  const _CompletionImageCard({required this.imageUrl});

  @override
  State<_CompletionImageCard> createState() => _CompletionImageCardState();
}

class _CompletionImageCardState extends State<_CompletionImageCard> {
  bool _expanded = false;

  String get _fullUrl => '${AppConfig.apiBase}${widget.imageUrl}';

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            children: [
              Image.network(
                _fullUrl,
                width: double.infinity,
                height: _expanded ? 280 : 180,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Container(
                    height: 180,
                    color: const Color(0xFFE5F5EF),
                    child: Center(
                      child: CircularProgressIndicator(
                        value: loadingProgress.expectedTotalBytes != null
                            ? loadingProgress.cumulativeBytesLoaded /
                                  loadingProgress.expectedTotalBytes!
                            : null,
                        color: const Color(0xFF1AB69C),
                        strokeWidth: 2.5,
                      ),
                    ),
                  );
                },
                errorBuilder: (_, _, _) => Container(
                  height: 180,
                  color: const Color(0xFFE5F5EF),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.broken_image_outlined,
                        color: Color(0xFF1AB69C),
                        size: 36,
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Image not available',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Overlay label
              Positioned(
                top: 10,
                left: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.photo_camera, color: Colors.white, size: 12),
                      SizedBox(width: 5),
                      Text(
                        'Completion Photo',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Expand hint
              Positioned(
                bottom: 10,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _expanded
                            ? Icons.zoom_out_rounded
                            : Icons.zoom_in_rounded,
                        color: Colors.white,
                        size: 12,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _expanded ? 'Collapse' : 'Expand',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
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
    );
  }
}

class _CompletionBanner extends StatelessWidget {
  static const _accentGreen = Color(0xFF1AB69C);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _accentGreen.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _accentGreen.withValues(alpha: 0.25)),
      ),
      child: const Row(
        children: [
          Icon(Icons.check_circle_rounded, color: _accentGreen, size: 22),
          SizedBox(width: 10),
          Text(
            'Task Successfully Completed',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: _accentGreen,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoGrid extends StatelessWidget {
  final TaskItem task;

  static const _accentGreen = Color(0xFF1AB69C);

  const _InfoGrid({required this.task});

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
    return Row(
      children: [
        Expanded(
          child: _InfoTile(
            icon: Icons.flag_outlined,
            label: 'Priority',
            value: task.priority,
            color: _priorityColor(),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _InfoTile(
            icon: Icons.calendar_today_outlined,
            label: 'Due Date',
            value: task.dueDateLabel,
            color: _accentGreen,
          ),
        ),
      ],
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF9CA3AF),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: color,
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

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;
  final Color? iconColor;

  const _SectionCard({
    required this.icon,
    required this.title,
    required this.child,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = iconColor ?? const Color(0xFF6B7280);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 7),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, thickness: 0.5, color: Color(0xFFF0F0F0)),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _AssignmentCard extends StatelessWidget {
  final TaskItem task;

  static const _accentGreen = Color(0xFF1AB69C);

  const _AssignmentCard({required this.task});

  String _roleLabel(String? role) {
    if (role == null) return 'Admin';
    switch (role.toLowerCase()) {
      case 'zonal_manager':
        return 'Zonal Manager';
      case 'admin':
        return 'Admin';
      default:
        return role;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section title
          const Row(
            children: [
              Icon(Icons.people_outline, color: Color(0xFF6B7280), size: 16),
              SizedBox(width: 7),
              Text(
                'Assignment Info',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF6B7280),
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, thickness: 0.5, color: Color(0xFFF0F0F0)),
          const SizedBox(height: 12),

          // Assigned to
          _AssignmentRow(
            label: 'Assigned To',
            name: task.assignedToName,
            icon: Icons.person_outline,
            color: _accentGreen,
          ),

          if (task.assignedByName != null &&
              task.assignedByName!.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Divider(height: 1, thickness: 0.5, color: Color(0xFFF3F4F6)),
            const SizedBox(height: 10),
            _AssignmentRow(
              label: 'Assigned By',
              name: task.assignedByName!,
              icon: Icons.supervisor_account_outlined,
              color: const Color(0xFF8B5CF6),
              badge: _roleLabel(task.roleAssignedBy),
            ),
          ],
        ],
      ),
    );
  }
}

class _AssignmentRow extends StatelessWidget {
  final String label;
  final String name;
  final IconData icon;
  final Color color;
  final String? badge;

  const _AssignmentRow({
    required this.label,
    required this.name,
    required this.icon,
    required this.color,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF9CA3AF),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                name,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1F2937),
                ),
              ),
            ],
          ),
        ),
        if (badge != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF8B5CF6).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(
                color: const Color(0xFF8B5CF6).withValues(alpha: 0.25),
              ),
            ),
            child: Text(
              badge!,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Color(0xFF8B5CF6),
              ),
            ),
          ),
      ],
    );
  }
}
