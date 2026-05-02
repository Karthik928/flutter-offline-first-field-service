import 'package:flutter/material.dart';

/// A static "Field Officer Profile" screen matching the provided design.
///
/// This screen is purely UI and modeled after the screenshot shared.
class FieldOfficerProfileScreen extends StatelessWidget {
  const FieldOfficerProfileScreen({super.key});

  static const _background = Color(0xFFF2F6F3);
  static const _headerGreen = Color(0xFF2E7D32);
  static const _cardBg = Colors.white;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: _buildProfileCard(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileCard(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [_buildHeader(), _buildContent(context)],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(top: 20, bottom: 18),
      decoration: BoxDecoration(
        color: _headerGreen,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.6),
                width: 3,
              ),
              image: const DecorationImage(
                image: NetworkImage(
                  'https://images.unsplash.com/photo-1527980965255-d3b416303d12?auto=format&fit=crop&w=200&q=80',
                ),
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Rajesh Kumar',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Field Officer',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildPerformanceRow(),
          const SizedBox(height: 16),
          _buildInfoRow(),
          const SizedBox(height: 18),
          const Text(
            'CONTACT DETAILS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.black54,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 10),
          _buildContactTile(icon: Icons.phone, label: '+91 98480 12345'),
          const SizedBox(height: 10),
          _buildContactTile(
            icon: Icons.email_outlined,
            label: 'rajesh.k@agriflow.com',
          ),
          const SizedBox(height: 18),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: _headerGreen,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: () {},
            icon: const Icon(Icons.bar_chart, size: 18),
            label: const Text(
              'View Monthly Report',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPerformanceRow() {
    return Row(
      children: [
        Expanded(
          child: Row(
            children: const [
              Icon(Icons.show_chart, size: 16, color: _headerGreen),
              SizedBox(width: 8),
              Text(
                'PERFORMANCE',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: Colors.black54,
                ),
              ),
            ],
          ),
        ),
        const Text(
          '88%',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: _headerGreen,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow() {
    return Row(
      children: [
        Expanded(
          child: _InfoChip(
            label: 'TERRITORY',
            value: 'West Delta',
            icon: Icons.location_on_outlined,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _InfoChip(
            label: 'STATUS',
            value: 'Active',
            icon: Icons.circle,
            iconColor: _headerGreen,
          ),
        ),
      ],
    );
  }

  Widget _buildContactTile({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFFE8F4EA),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 18, color: _headerGreen),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: Colors.black87),
            ),
          ),
          const Icon(Icons.chevron_right, color: Colors.black38),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color iconColor;

  const _InfoChip({
    required this.label,
    required this.value,
    required this.icon,
    this.iconColor = const Color(0xFF7C7C7C),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F6F3),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
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
