import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:FieldService_app/zonal_services/zonal_gps_service.dart';

/// EmployeeTrackingScreen
///
/// - Seeds the map instantly from the initial coords passed by [FieldTeamScreen]
/// - Polls [ZonalGpsService] every 10 s for fresh GPS data
/// - "Last updated" time is read from [gps.updatedAt] in the API — NOT from
///   when the HTTP call was made
class EmployeeTrackingScreen extends StatefulWidget {
  /// Initial GPS from the employee list (shown immediately on open)
  final double latitude;
  final double longitude;

  /// The [gps.updatedAt] value from the employee list API — shown as the
  /// initial "Last updated" time before the first poll completes.
  final DateTime? gpsUpdatedAt;

  final String name;
  final String empCode; // used by ZonalGpsService for the search query

  final String? role;
  final String? zone;
  final String? status;

  const EmployeeTrackingScreen({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.name,
    required this.empCode,
    this.gpsUpdatedAt,
    this.role,
    this.zone,
    this.status,
  });

  @override
  State<EmployeeTrackingScreen> createState() => _EmployeeTrackingScreenState();
}

class _EmployeeTrackingScreenState extends State<EmployeeTrackingScreen>
    with TickerProviderStateMixin {
  // ─── Brand colors ─────────────────────────────────────────────────────────
  static const _gradientStart = Color(0xFF52D494);
  static const _gradientEnd = Color(0xFF1AB69C);
  static const _accentGreen = Color(0xFF1AB69C);

  // ─── Map ──────────────────────────────────────────────────────────────────
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  final List<LatLng> _trail = [];
  LatLng _currentPosition = const LatLng(0, 0);

  // ─── State ────────────────────────────────────────────────────────────────
  /// Always set from [gps.updatedAt] — the actual device timestamp.
  DateTime? _gpsUpdatedAt;
  String _timeAgoLabel = '—';
  bool _isLive = true;
  bool _followMe = true;
  String? _gpsError;

  // ─── Services ─────────────────────────────────────────────────────────────
  late final ZonalGpsService _gpsService;
  StreamSubscription<dynamic>? _gpsSub;
  Timer? _timeAgoTimer;

  // ─── Pulse animation ──────────────────────────────────────────────────────
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();

    // Seed with initial data from the list screen
    _currentPosition = LatLng(widget.latitude, widget.longitude);
    _gpsUpdatedAt = widget.gpsUpdatedAt; // from API, may be null
    _timeAgoLabel = _ago(_gpsUpdatedAt);
    _trail.add(_currentPosition);
    _updateMarker(_currentPosition);

    // Pulse animation
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(
      begin: 0.5,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    // GPS polling service
    _gpsService = ZonalGpsService(empCode: widget.empCode);
    _gpsSub = _gpsService.stream.listen(
      _onGpsUpdate,
      onError: (e) {
        if (!mounted) return;
        setState(() => _gpsError = e.toString());
      },
    );
    _gpsService.start();

    // Refresh the "X ago" label every 30 s so it stays accurate
    _timeAgoTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _timeAgoLabel = _ago(_gpsUpdatedAt));
    });
  }

  @override
  void dispose() {
    _gpsSub?.cancel();
    _gpsService.dispose();
    _timeAgoTimer?.cancel();
    _pulseCtrl.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  // ─── GPS update ───────────────────────────────────────────────────────────
  void _onGpsUpdate(EmployeeGpsSnapshot snap) {
    if (!mounted) return;
    final pos = LatLng(snap.latitude, snap.longitude);
    setState(() {
      _currentPosition = pos;
      _gpsUpdatedAt = snap.gpsUpdatedAt; // ← from API, not DateTime.now()
      _timeAgoLabel = _ago(snap.gpsUpdatedAt);
      _gpsError = null;
      _updateMarker(pos);
      _trail.add(pos);
      if (_trail.length > 60) _trail.removeAt(0);
    });

    if (_followMe) {
      _mapController?.animateCamera(CameraUpdate.newLatLng(pos));
    }
  }

  void _updateMarker(LatLng pos) {
    _markers
      ..clear()
      ..add(
        Marker(
          markerId: const MarkerId('emp'),
          position: pos,
          infoWindow: InfoWindow(
            title: widget.name,
            snippet: widget.role ?? 'Field Employee',
          ),
        ),
      );
  }

  // ─── Time-ago helper ──────────────────────────────────────────────────────
  /// Computes a human-readable label from [gps.updatedAt] (device time).
  String _ago(DateTime? ts) {
    if (ts == null) return 'No GPS data';
    final d = DateTime.now().difference(ts);
    if (d.inSeconds < 10) return 'Just now';
    if (d.inSeconds < 60) return '${d.inSeconds}s ago';
    if (d.inMinutes == 1) return '1 min ago';
    if (d.inMinutes < 60) return '${d.inMinutes} mins ago';
    if (d.inHours == 1) return '1 hour ago';
    if (d.inHours < 24) return '${d.inHours} hours ago';
    if (d.inDays == 1) return 'Yesterday';
    return '${d.inDays} days ago';
  }

  /// Full formatted timestamp shown in the info sheet.
  String _formattedTimestamp(DateTime? ts) {
    if (ts == null) return '—';
    final local = ts.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    final months = [
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
    return '${local.day} ${months[local.month]} ${local.year},  $h:$m';
  }

  // ─── Other helpers ────────────────────────────────────────────────────────
  Color _statusColor(String? s) {
    switch (s) {
      case 'Active':
      case 'Present':
        return _accentGreen;
      case 'On Field':
        return const Color(0xFF4D8AF0);
      default:
        return Colors.grey;
    }
  }

  void _toggleLive() {
    setState(() => _isLive = !_isLive);
    _isLive ? _gpsService.resume() : _gpsService.pause();
  }

  void _centreOnEmployee() {
    setState(() => _followMe = true);
    _mapController?.animateCamera(CameraUpdate.newLatLng(_currentPosition));
  }

  // ─── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(),
      body: Stack(
        children: [
          _buildMap(),
          Positioned(bottom: 0, left: 0, right: 0, child: _buildSheet()),
          Positioned(top: 108, right: 12, child: _buildMapControls()),
          Positioned(top: 108, left: 12, child: _buildTimeAgoChip()),
          if (_gpsError != null)
            Positioned(
              top: 155,
              left: 12,
              right: 12,
              child: _buildErrorBanner(),
            ),
        ],
      ),
    );
  }

  // ─── AppBar ───────────────────────────────────────────────────────────────
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
          title: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.name,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              if (widget.zone != null)
                Text(
                  widget.zone!,
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                ),
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: GestureDetector(
                onTap: _toggleLive,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _isLive
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedBuilder(
                        animation: _pulseAnim,
                        builder: (_, _) => Opacity(
                          opacity: _isLive ? _pulseAnim.value : 0.4,
                          child: Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: _isLive ? _accentGreen : Colors.grey,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _isLive ? 'LIVE' : 'PAUSED',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: _isLive ? _accentGreen : Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Map ──────────────────────────────────────────────────────────────────
  Widget _buildMap() {
    return GoogleMap(
      onMapCreated: (c) {
        _mapController = c;
        c.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: _currentPosition, zoom: 15.5),
          ),
        );
      },
      initialCameraPosition: CameraPosition(
        target: _currentPosition,
        zoom: 15.5,
      ),
      markers: _markers,
      polylines: {
        Polyline(
          polylineId: const PolylineId('trail'),
          points: List.from(_trail),
          color: _accentGreen,
          width: 4,
        ),
      },
      myLocationEnabled: false,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
      compassEnabled: true,
      onCameraMove: (_) {
        if (_followMe) setState(() => _followMe = false);
      },
    );
  }

  // ─── Time-ago chip (floats over map) ──────────────────────────────────────
  Widget _buildTimeAgoChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.access_time_rounded,
            size: 13,
            color: Colors.black45,
          ),
          const SizedBox(width: 5),
          Text(
            _timeAgoLabel,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.black54,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Error banner ─────────────────────────────────────────────────────────
  Widget _buildErrorBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFEF4444),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 8),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_off_rounded, size: 15, color: Colors.white),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _gpsError ?? 'GPS unavailable',
              style: const TextStyle(
                fontSize: 12,
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Map controls ─────────────────────────────────────────────────────────
  Widget _buildMapControls() {
    return Column(
      children: [
        _MapBtn(
          icon: Icons.my_location_rounded,
          color: _followMe ? _accentGreen : Colors.black54,
          onTap: _centreOnEmployee,
        ),
        const SizedBox(height: 8),
        _MapBtn(
          icon: Icons.add,
          color: Colors.black54,
          onTap: () => _mapController?.animateCamera(CameraUpdate.zoomIn()),
        ),
        const SizedBox(height: 8),
        _MapBtn(
          icon: Icons.remove,
          color: Colors.black54,
          onTap: () => _mapController?.animateCamera(CameraUpdate.zoomOut()),
        ),
      ],
    );
  }

  // ─── Bottom info sheet ────────────────────────────────────────────────────
  Widget _buildSheet() {
    final status = widget.status ?? 'Active';
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Color(0x18000000),
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
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
          const SizedBox(height: 14),

          // ── Employee header ──
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: _accentGreen.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    widget.name[0],
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: _accentGreen,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.empCode,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black45,
                      ),
                    ),
                  ],
                ),
              ),
              // Status badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _statusColor(status).withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: _statusColor(status),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      status,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _statusColor(status),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),
          const Divider(height: 1, thickness: 0.5, color: Color(0xFFF0F0F0)),
          const SizedBox(height: 12),

          // ── Lat / Lng ──
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  icon: Icons.explore_outlined,
                  color: _accentGreen,
                  label: 'LATITUDE',
                  value: _currentPosition.latitude.toStringAsFixed(5),
                ),
              ),
              _vDivider(),
              Expanded(
                child: _StatTile(
                  icon: Icons.explore_outlined,
                  color: _accentGreen,
                  label: 'LONGITUDE',
                  value: _currentPosition.longitude.toStringAsFixed(5),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // ── Speed / Accuracy ──
          // Row(
          //   children: [
          //     Expanded(
          //       child: _StatTile(
          //         icon: Icons.speed_outlined,
          //         color: _speedColor(),
          //         label: 'SPEED',
          //         value: _speed > 0 ? '${_speed.toStringAsFixed(1)} km/h' : '—',
          //       ),
          //     ),
          //     _vDivider(),
          //     Expanded(
          //       child: _StatTile(
          //         icon: Icons.gps_fixed_rounded,
          //         color: const Color(0xFF4D8AF0),
          //         label: 'ACCURACY',
          //         value: _accuracy > 0
          //             ? '±${_accuracy.toStringAsFixed(0)} m'
          //             : '—',
          //       ),
          //     ),
          //   ],
          // ),
          const SizedBox(height: 14),

          // ── Last GPS timestamp card ──────────────────────────────────────
          // This shows the DEVICE time from gps.updatedAt, not when we polled
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: _isLive
                  ? _accentGreen.withValues(alpha: 0.07)
                  : Colors.grey.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _isLive
                    ? _accentGreen.withValues(alpha: 0.22)
                    : Colors.grey.withValues(alpha: 0.2),
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    // Pulsing live dot
                    AnimatedBuilder(
                      animation: _pulseAnim,
                      builder: (_, _) => Opacity(
                        opacity: _isLive ? _pulseAnim.value : 0.4,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: _isLive ? _accentGreen : Colors.grey,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _isLive ? 'Live tracking active' : 'Tracking paused',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _isLive ? _accentGreen : Colors.grey,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _timeAgoLabel,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _isLive ? _accentGreen : Colors.grey,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Exact timestamp row
                Row(
                  children: [
                    const Icon(
                      Icons.calendar_today_outlined,
                      size: 13,
                      color: Colors.black38,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Device last seen:',
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
                    const Spacer(),
                    Text(
                      _formattedTimestamp(_gpsUpdatedAt),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _vDivider() => Container(
    width: 1,
    height: 38,
    color: const Color(0xFFF0F0F0),
    margin: const EdgeInsets.symmetric(horizontal: 8),
  );
}

// ─── Reusable widgets ─────────────────────────────────────────────────────────

class _MapBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _MapBtn({required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, color: color, size: 20),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  const _StatTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, size: 17, color: color),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Colors.grey[500],
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 2),
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
      ],
    );
  }
}
