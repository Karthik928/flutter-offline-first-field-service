// FILE: lib/Screens/farmer_order_screen.dart
// Standalone screen similar to DealerOrderScreen but for FARMERS
// No coordinates, no directions, no copy-coordinates

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:FieldService_app/Screens/products_screen.dart';

class FarmerOrderScreen extends StatefulWidget {
  final String farmerId;
  final String farmerName;
  final String address;
  final String mobile;
  final double latitude;
  final double longitude;
  final num pendingAmount;

  const FarmerOrderScreen({
    super.key,
    required this.farmerId,
    required this.farmerName,
    required this.address,
    required this.mobile,
    required this.latitude,
    required this.longitude,
    required this.pendingAmount,
  });

  @override
  State<FarmerOrderScreen> createState() => _FarmerOrderScreenState();
}

class _FarmerOrderScreenState extends State<FarmerOrderScreen> {
  final Color appGreen = const Color(0xFF2E7D32);

  Future<void> _callFarmer() async {
    final phone = widget.mobile.trim();
    if (phone.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No mobile number found'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final uri = Uri(scheme: 'tel', path: phone);

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open dialer'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Uri _webDirectionsUri() => Uri.parse(
    'https://www.google.com/maps/dir/?api=1&destination=${widget.latitude},${widget.longitude}&travelmode=driving',
  );

  Uri _iosGoogleMapsUri() => Uri.parse(
    'comgooglemaps://?daddr=${widget.latitude},${widget.longitude}&directionsmode=driving',
  );

  Future<void> _openDirections() async {
    final gmapsUrl = _iosGoogleMapsUri();
    final webUrl = _webDirectionsUri();

    if (Theme.of(context).platform == TargetPlatform.iOS &&
        await canLaunchUrl(gmapsUrl)) {
      await launchUrl(gmapsUrl, mode: LaunchMode.externalApplication);
      return;
    }

    if (await canLaunchUrl(webUrl)) {
      await launchUrl(webUrl, mode: LaunchMode.externalApplication);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not open Maps')));
    }
  }

  Future<void> _copyCoordinates() async {
    final coords = '${widget.latitude}, ${widget.longitude}';
    await Clipboard.setData(ClipboardData(text: coords));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Coordinates copied')));
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = widget.mobile.trim().isNotEmpty
        ? widget.mobile.trim()
        : '';

    return Scaffold(
      backgroundColor: Colors.white,
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
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
            ),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_sharp, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            title: const Text(
              'Order Farmer',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
          ),
        ),
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _farmerHeaderCard(subtitle),
            const SizedBox(height: 12),
            _orderArea(),
          ],
        ),
      ),
    );
  }

  Widget _farmerHeaderCard(String subtitle) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF1AB69C).withValues(alpha: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // FARMER HEADER
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF1AB69C).withValues(alpha: 0.15),

                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.agriculture, color: Color(0xFF1AB69C)),
              ),
              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.farmerName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),

                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 12.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // ADDRESS ONLY (NO COORDS)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.place, size: 18, color: Colors.grey[600]),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.address,
                  style: const TextStyle(color: Colors.black87),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                Icons.account_balance_wallet,
                size: 15,
                color: const Color(0xFF1AB69C),
              ),
              const SizedBox(width: 8),
              Builder(
                builder: (_) {
                  final fmt = NumberFormat.currency(
                    locale: 'en_IN',
                    symbol: '₹',
                    decimalDigits: 2,
                  );
                  final pending = widget.pendingAmount;
                  final noDue = pending <= 0.0;
                  return Text(
                    noDue ? 'No Due' : 'Due: ${fmt.format(pending)}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: noDue
                          ? Colors.green
                          : const Color.fromARGB(255, 255, 0, 0),
                    ),
                  );
                },
              ),
            ],
          ),

          const SizedBox(height: 12),

          // CALL BUTTON
          Container(
            //padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Container(
              //padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: _openDirections,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1AB69C),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: const Icon(Icons.directions_rounded),
                      label: const Text('Get Directions'),
                    ),

                    const SizedBox(width: 8),

                    OutlinedButton.icon(
                      onPressed: _callFarmer,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFF1AB69C)),
                        foregroundColor: const Color(0xFF1AB69C),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: const Icon(Icons.call_rounded),
                      label: const Text('Call'),
                    ),

                    const SizedBox(width: 8),

                    Tooltip(
                      message: 'Copy coordinates',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: _copyCoordinates,
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.grey.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.grey.withValues(alpha: 0.15),
                            ),
                          ),
                          alignment: Alignment.center,
                          child: const Icon(Icons.copy_all_rounded, size: 22),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _orderArea() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF1AB69C).withValues(alpha: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Order Purpose',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text(
            'Browse the product catalog, add to cart, and proceed to create an order.',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 12),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1AB69C),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.shopping_bag_outlined),
              label: const Text(
                'Browse Products',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProductsScreen(
                      customerId: widget.farmerId,
                      type: "Farmer",
                      condition: true,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
