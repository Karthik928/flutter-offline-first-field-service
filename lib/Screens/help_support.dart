import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class HelpSupport extends StatefulWidget {
  const HelpSupport({super.key});

  @override
  State<HelpSupport> createState() => _HelpSupportState();
}

class _HelpSupportState extends State<HelpSupport>
    with TickerProviderStateMixin {
  final TextEditingController _descriptionController = TextEditingController();

  late AnimationController _fadeController;
  late AnimationController _slideController;

  // Theme Colors
  final Color appGreen = const Color(0xFF1AB69C);
  final Color borderColor = const Color(0xFF1AB69C);
  final Color backgroundColor = const Color(0xFFF5F5F5);

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _fadeController.forward();
    _slideController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _contactMethods => [
    {
      'title': 'Email Support',
      'subtitle': 'info@FieldServicebio.com',
      'icon': Icons.email_outlined,
      'color': Color(0xFF1AB69C),
      'action': () => _launchEmail(),
    },
    {
      'title': 'Phone Support',
      'subtitle': '+91 9293953333',
      'icon': Icons.phone_outlined,
      'color': Color(0xFF1AB69C),
      'action': () => _launchPhone(),
    },
  ];

  // ---------------------------------------------------------------------------

  Future<void> _launchEmail() async {
  final Uri emailUri = Uri.parse(
    'mailto:info@FieldServicebio.com?subject=Support Request&body=Hello, I need help with...',
  );

  try {
    await launchUrl(
      emailUri,
      mode: LaunchMode.externalApplication,
    );
  } catch (e) {
    debugPrint('Error launching email: $e');
  }
}

  Future<void> _launchPhone() async {
    final Uri phoneUri = Uri(scheme: 'tel', path: '9293953333');
    if (await canLaunchUrl(phoneUri)) launchUrl(phoneUri);
  }

  // ---------------------------------------------------------------------------

  Widget _buildContactCard(Map<String, dynamic> contact) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: contact['action'],
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: borderColor, // <--- FIXED border color everywhere
                width: 1.3,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: contact['color'].withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: borderColor),
                  ),
                  child: Icon(
                    contact['icon'],
                    color: contact['color'],
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        contact['title'],
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        contact['subtitle'],
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  size: 16,
                  color: Colors.grey[400],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,

      // ---------------- APP BAR WITH GRADIENT ----------------
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
            centerTitle: true,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_sharp, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
            ),
            title: const Text(
              'Help & Support',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
                fontSize: 20,
                shadows: [
                  Shadow(
                    offset: Offset(1, 1), // Direction of shadow
                    blurRadius: 4, // Softness of shadow
                    color: Colors.black38, // Shadow color
                  ),
                ],
              ),
            ),
          ),
        ),
      ),

      // ---------------- BODY ----------------
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'How can we help you?',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),

              const Text(
                'If you need assistance, please contact us at:',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 4),

              const Text(
                '📧 info@FieldServicebio.com\n📞 9293953333',
                style: TextStyle(fontSize: 16, color: Colors.black87),
              ),

              const SizedBox(height: 30),

              // ---------------- CONTACT METHODS ----------------
              const Text(
                'Contact Us',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 15),

              ..._contactMethods.map(_buildContactCard),

              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }
}
