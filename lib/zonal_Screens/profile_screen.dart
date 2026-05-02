import 'package:flutter/material.dart';

/// A static "Profile" screen matching the provided design.
///
/// This screen is a UI-only representation of the profile layout shown in the screenshot.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  static const _background = Color(0xFFF2F6F3);
  static const _headerGreen = Color(0xFF2E7D32);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                children: [
                  _buildHeader(),
                  const SizedBox(height: 18),
                  _buildContactCard(),
                  const SizedBox(height: 22),
                  _buildSectionTitle('ACCOUNT SETTINGS'),
                  const SizedBox(height: 10),
                  _buildOptionTile(
                    icon: Icons.lock_outline,
                    label: 'Change Password',
                    onTap: () {},
                  ),
                  _buildOptionTile(
                    icon: Icons.settings_outlined,
                    label: 'App Settings',
                    onTap: () {},
                  ),
                  _buildOptionTile(
                    icon: Icons.notifications_none,
                    label: 'Notifications',
                    onTap: () {},
                  ),
                  _buildOptionTile(
                    icon: Icons.location_on_outlined,
                    label: 'Zone Configuration',
                    onTap: () {},
                  ),
                  _buildOptionTile(
                    icon: Icons.help_outline,
                    label: 'Support & Help',
                    onTap: () {},
                  ),
                  const SizedBox(height: 22),
                  _buildLogoutButton(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: _headerGreen,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      padding: const EdgeInsets.only(top: 20, bottom: 26),
      child: Column(
        children: [
          Container(
            width: 88,
            height: 88,
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
          const SizedBox(height: 14),
          const Text(
            'Vikram Chandra',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Zonal Manager - South Delta',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactCard() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Column(
        children: [
          _buildContactRow(
            icon: Icons.email_outlined,
            title: 'EMAIL ADDRESS',
            value: 'v.chandra@agriflow.com',
          ),
          const Divider(height: 22),
          _buildContactRow(
            icon: Icons.phone_outlined,
            title: 'CONTACT NUMBER',
            value: '+91 98765 43210',
          ),
        ],
      ),
    );
  }

  Widget _buildContactRow({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.grey.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 20, color: Colors.black54),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Colors.black54,
                ),
              ),
              const SizedBox(height: 4),
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
    );
  }

  Widget _buildSectionTitle(String text) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Colors.black54,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _buildOptionTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ListTile(
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: Colors.grey.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, size: 20, color: Colors.black54),
        ),
        title: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.black38),
        onTap: onTap,
      ),
    );
  }

  Widget _buildLogoutButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Color(0xFFEB5757)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        icon: const Icon(Icons.logout, color: Color(0xFFEB5757)),
        label: const Text(
          'Log Out',
          style: TextStyle(
            color: Color(0xFFEB5757),
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
        onPressed: () {},
      ),
    );
  }
}
