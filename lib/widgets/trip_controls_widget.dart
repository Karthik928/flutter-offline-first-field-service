import 'package:flutter/material.dart';
import 'package:FieldService_app/Screens/dealers_screen.dart';
import 'package:FieldService_app/Screens/farmer_visit_screen.dart';
import 'package:FieldService_app/Screens/other_visit_screen.dart';

class TripControlsWidget extends StatelessWidget {
  final bool isTripStarted;
  final bool tripCompleted;

  final Duration elapsedTime;
  final double distanceTraveled;
  final Duration? tripDuration;
  final double? kmCovered;
  final double? routeDistance;
  final double? routeDuration;
  final bool isEditing;
  final VoidCallback? onStartTrip;
  final VoidCallback? onEndTrip;
  final VoidCallback? onStartTripWithoutDestination;
  final VoidCallback? onResetTrip;
  final VoidCallback? onOpenInGoogleMaps;
  final double? distanceRemainingKm; // Y km left
  final double? durationRemainingMin; // X min left
  final DateTime? etaLastUpdatedAt;

  const TripControlsWidget({
    super.key,
    required this.isTripStarted,
    required this.tripCompleted,
    required this.elapsedTime,
    required this.distanceTraveled,
    this.tripDuration,
    this.kmCovered,
    this.routeDistance,
    this.routeDuration,
    this.isEditing = false,
    this.onStartTrip,
    this.onEndTrip,
    this.onStartTripWithoutDestination,
    this.onResetTrip,
    this.onOpenInGoogleMaps,
    this.distanceRemainingKm,
    this.durationRemainingMin,
    this.etaLastUpdatedAt, // 👈 NEW
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Quick Start Button (without destination)
        if (!isTripStarted && !tripCompleted)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),

            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: Color(0xFF1EB89C), // ← your border color
                width: 1,
              ),
            ),

            child: ElevatedButton(
              onPressed: onStartTripWithoutDestination,

              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                elevation: 0, // remove shadow so border looks clean
                minimumSize: const Size(double.infinity, 56),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),

              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.play_arrow, size: 24),
                  SizedBox(width: 8),
                  Text(
                    "Start Trip Without Destination",
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),

        // Route Info Card
        if (routeDistance != null && routeDuration != null && !isEditing)
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Color(0xFF1AB69C).withValues(alpha: 0.5),
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
                Expanded(
                  child: _buildRouteInfoItem(
                    Icons.directions_car,
                    "${routeDistance!.toStringAsFixed(1)} km",
                    "Distance",
                    const Color(0xFF3B82F6),
                  ),
                ),
                Container(width: 1, height: 40, color: Colors.grey[200]),
                Expanded(
                  child: _buildRouteInfoItem(
                    Icons.access_time,
                    _getEtaRange(routeDuration!, routeDistance!),
                    "ETA",
                    const Color(0xFFF59E0B),
                  ),
                ),
              ],
            ),
          ),

        const SizedBox(height: 12),

        // Trip Control Buttons
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),

          child: Row(
            children: [
              Expanded(
                child: _buildTripButton(
                  title: "Start Trip",
                  icon: Icons.play_arrow,
                  color: Color(0xFF1EB89C), // ← your border color

                  onPressed: (!isTripStarted && !tripCompleted)
                      ? onStartTrip
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildTripButton(
                  title: "End Trip",
                  icon: Icons.stop,
                  color: const Color(0xFFEF4444),
                  onPressed: isTripStarted ? onEndTrip : null,
                ),
              ),
            ],
          ),
        ),

        // === Trip in-progress card ===
        if (isTripStarted && !tripCompleted) ...[
          const SizedBox(height: 16),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1EB89C), Color(0xFF1EB89C)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: const Color.fromARGB(
                    255,
                    7,
                    7,
                    7,
                  ).withValues(alpha: 0.3),
                  blurRadius: 15,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: [
                const Text(
                  "Trip in Progress",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),

                // NAVIGATED: show Remaining time (fresh ETA from API), optional subline
                if (durationRemainingMin != null &&
                    distanceRemainingKm != null) ...[
                  // Show fresh ETA directly without countdown
                  Builder(
                    builder: (_) {
                      final pretty = _formatCountdown(
                        ((durationRemainingMin ?? 0) * 60).round(),
                      );
                      return Text(
                        'Remaining: $pretty',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    // optional subline — keep it if useful, or remove the whole Text(...)
                    '${distanceRemainingKm!.clamp(0.0, double.infinity).toStringAsFixed(1)} km left • '
                    '${distanceTraveled.toStringAsFixed(2)} km traveled',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ] else ...[
                  // FREE-RIDE: original two tiles
                  Row(
                    children: [
                      Expanded(
                        child: _buildTripStatItem(
                          Icons.timer,
                          formatDuration(elapsedTime),
                          "Duration",
                          Colors.white,
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 40,
                        color: Colors.white.withValues(alpha: 0.3),
                      ),
                      Expanded(
                        child: _buildTripStatItem(
                          Icons.speed,
                          "${distanceTraveled.toStringAsFixed(2)} km",
                          "Distance",
                          Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],

        const SizedBox(height: 12),

        // Google Maps button — only for trips started WITH destination
        if (isTripStarted &&
            !tripCompleted &&
            durationRemainingMin != null &&
            distanceRemainingKm != null &&
            onOpenInGoogleMaps != null)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: ElevatedButton.icon(
              onPressed: onOpenInGoogleMaps,
              icon: const Icon(
                Icons.map_outlined,
                color: Color.fromARGB(255, 255, 255, 255),
              ),
              label: const Text("Open in Google Maps"),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1AB69C),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 56),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 4,
              ),
            ),
          ),

        const SizedBox(height: 16),

        // Trip Summary
        if (tripCompleted)
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF1AB69C), width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                const Text(
                  "Trip Summary",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color((0xFF1AB69C)),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _buildTripStatItem(
                        Icons.timer,
                        tripDuration != null
                            ? formatDuration(tripDuration!)
                            : "0m 0s",
                        "Total Time",
                        const Color(0xFF1AB69C),
                      ),
                    ),
                    Container(width: 1, height: 40, color: Color(0xFF1AB69C)),
                    Expanded(
                      child: _buildTripStatItem(
                        Icons.speed,
                        kmCovered != null
                            ? "${kmCovered!.toStringAsFixed(2)} km"
                            : "0.00 km",
                        "Total Distance",
                        const Color(0xFF1AB69C),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // 2×2 Grid Buttons (Dealer, Farmer, Other, New Trip)
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 2.2,
                  children: [
                    // Dealer Visit
                    ElevatedButton(
                      onPressed: () async {
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                const DealersScreen(display: true),
                          ),
                        );
                        if (result == "refreshDealers") {}
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1AB69C),
                        foregroundColor: const Color.fromARGB(
                          255,
                          255,
                          255,
                          255,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 4,
                      ),
                      child: const Text(
                        "Dealer Visit",
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),

                    // Farmer Visit
                    ElevatedButton(
                      onPressed: () async {
                        final saved = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                const FarmerVisitScreen(display: true),
                          ),
                        );
                        if (saved == true) {}
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1AB69C),
                        foregroundColor: const Color.fromARGB(
                          255,
                          255,
                          255,
                          255,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 4,
                      ),
                      child: const Text(
                        "Farmer Visit",
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),

                    // Other Visit (NEW)
                    ElevatedButton(
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const OtherVisitScreen(),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(0xFF1AB69C),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 4,
                      ),
                      child: const Text(
                        "Other Visit",
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),

                    // Start New Trip
                    ElevatedButton(
                      onPressed: onResetTrip,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1AB69C),
                        foregroundColor: const Color.fromARGB(
                          255,
                          255,
                          255,
                          255,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 4,
                      ),
                      child: const Text(
                        "Reset Trip",
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  String _formatCountdown(int seconds) {
    if (seconds < 0) seconds = 0;
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}m';
    return '$m min';
  }

  String formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;

    if (hours > 0) {
      return "${hours}h ${minutes}m ${seconds}s";
    } else {
      return "${minutes}m ${seconds}s";
    }
  }

  Widget _buildRouteInfoItem(
    IconData icon,
    String value,
    String label,
    Color color,
  ) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }

  Widget _buildTripStatItem(
    IconData icon,
    String value,
    String label,
    Color color,
  ) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 10, color: color.withValues(alpha: 0.7)),
        ),
      ],
    );
  }

  Widget _buildTripButton({
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback? onPressed,
  }) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        elevation: 4,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  String _getEtaRange(double minutes, double distanceKm) {
    int minMinutes = minutes.floor();

    // Buffer rules
    int buffer;
    if (distanceKm < 5) {
      buffer = 5;
    } else if (distanceKm < 20) {
      buffer = 15;
    } else if (distanceKm < 50) {
      buffer = 30;
    } else {
      buffer = 50;
    }

    int maxMinutes = (minutes + buffer).ceil();

    String format(int mins) {
      Duration d = Duration(minutes: mins);
      int days = d.inDays;
      int hours = d.inHours % 24;
      int minutes = d.inMinutes % 60;

      String result = "";
      if (days > 0) result += "$days d ";
      if (hours > 0) result += "$hours h ";
      if (minutes > 0) result += "$minutes m";
      return result.trim().isEmpty ? "0 m" : result.trim();
    }

    return "${format(minMinutes)} – ${format(maxMinutes)}";
  }
}
