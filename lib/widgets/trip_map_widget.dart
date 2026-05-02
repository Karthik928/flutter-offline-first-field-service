import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'dart:math' as math;
import 'package:geolocator/geolocator.dart';

class MathCosImpl {
  static double cos(double v) => math.cos(v);
  static double sin(double v) => math.sin(v);
}

class MathSinImpl {
  static double sin(double v) => math.sin(v);
}

class TripMapWidget extends StatefulWidget {
  final LatLng? currentLocation;
  final LatLng? destination;
  final List<LatLng> routePoints;
  final bool isMapLoading;
  final Function(LatLng) onMapTapped;
  final Function(LatLng) onLocationChanged;
  final VoidCallback? onMyLocationPressed;

  final int recenterTrigger;

  final Set<Polyline>? polylines; // 👈 NEW
  final ValueChanged<CameraPosition>? onCameraMove; // 👈 NEW
  final VoidCallback? onUserGesture; // 👈 NEW
  final bool trafficEnabled; // 👈 NEW
  final bool showMarkers; // 👈 NEW

  // +++ add to TripMapWidget fields + constructor + default values
  final bool followCamera; // auto-follow user
  final bool courseUp; // rotate map to travel bearing
  final int followSuspendMs; // how long to pause after user pans
  final bool myLocationEnabled;
  final bool myLocationButtonEnabled;

  const TripMapWidget({
    super.key,
    this.currentLocation,
    this.destination,
    this.routePoints = const [],
    this.isMapLoading = false,
    required this.onMapTapped,
    required this.onLocationChanged,
    this.onMyLocationPressed,
    this.recenterTrigger = 0, // default
    this.polylines,
    this.onCameraMove, // 👈 NEW
    this.onUserGesture, // 👈 NEW
    this.trafficEnabled = false, // 👈 NEW (default OFF)
    this.showMarkers = true, // 👈 NEW
    this.followCamera = true, // NEW
    this.courseUp = true, // NEW
    this.followSuspendMs = 5000, // NEW (5s)
    this.myLocationEnabled = false,
    this.myLocationButtonEnabled = true,
  });

  @override
  State<TripMapWidget> createState() => _TripMapWidgetState();
}

class _TripMapWidgetState extends State<TripMapWidget> {
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  bool _isMapReady = false;
  bool _mapInitializationFailed = false;
  bool _didInitialFocus = false;
  MapType _mapType = MapType.normal;

  @override
  void initState() {
    super.initState();
    _updateMarkersAndPolylines();

    // Fallback guard: mark init failure if map doesn't become ready soon
    Future.delayed(const Duration(seconds: 10), () {
      if (!_isMapReady && mounted) {
        setState(() => _mapInitializationFailed = true);
      }
    });
  }

  @override
  void didUpdateWidget(TripMapWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    final locChanged = oldWidget.currentLocation != widget.currentLocation;
    final destChanged = oldWidget.destination != widget.destination;
    final ptsChanged = oldWidget.routePoints != widget.routePoints;
    final plsChanged = oldWidget.polylines != widget.polylines;

    if (locChanged || destChanged || ptsChanged || plsChanged) {
      _updateMarkersAndPolylines();

      // 🔧 Defer any rebuilds/camera animations until after this build frame
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        setState(() {}); // safe post-frame repaint to reflect new markers

        if (_isMapReady && _mapController != null) {
          if (_hasParentPolylines() ||
              widget.routePoints.isNotEmpty ||
              widget.destination != null) {
            await _fitToCoverage();
          } else if (locChanged && widget.currentLocation != null) {
            if (widget.followCamera) {
              await _autoFollowTo(widget.currentLocation!);
            }
          }
        }
        // if (locChanged &&
        //     widget.currentLocation != null &&
        //     _mapController != null) {
        //   _moveToCurrentLocation(); // instead of calling _animateTo directly
        // }
      });
    }

    // recenter trigger stays the same, but also do it post-frame to be safe
    if (oldWidget.recenterTrigger != widget.recenterTrigger &&
        widget.currentLocation != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted || _mapController == null) return;
        //_animateTo(widget.currentLocation!, zoom: 16);
        //_moveToCurrentLocation();
        await _mapController!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: widget.currentLocation!, zoom: 16),
          ),
        );
      });
    }
  }

  Future<void> _introFocus(LatLng loc) async {
    if (_mapController == null) return;
    // Step 1: snap in a bit wider
    await _mapController!.moveCamera(
      CameraUpdate.newCameraPosition(CameraPosition(target: loc, zoom: 12)),
    );
    // Step 2: quick ease to your normal nav view
    await Future.delayed(const Duration(milliseconds: 120));
    await _mapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: loc, zoom: 16, tilt: 30),
      ),
    );
  }

  LatLng? _prevLoc;
  DateTime? _prevTs;
  DateTime? _suspendUntil; // set when user gestures

  double _bearingDeg(LatLng a, LatLng b) {
    // Returns [0,360)
    final dLon = (b.longitude - a.longitude) * (3.141592653589793 / 180.0);
    final lat1 = a.latitude * (3.141592653589793 / 180.0);
    final lat2 = b.latitude * (3.141592653589793 / 180.0);
    final y = MathCosImpl.sin(dLon) * MathCosImpl.cos(lat2);
    final x =
        MathCosImpl.cos(lat1) * MathSinImpl.sin(lat2) -
        MathSinImpl.sin(lat1) * MathCosImpl.cos(lat2) * MathCosImpl.cos(dLon);
    double brng = math.atan2(y, x) * 180.0 / 3.141592653589793;
    if (brng < 0) brng += 360.0;
    return brng;
  }

  double _speedKmh(LatLng a, DateTime ta, LatLng b, DateTime tb) {
    final dt = tb.difference(ta).inMilliseconds / 1000.0;
    if (dt <= 0) return 0;
    final meters = Geolocator.distanceBetween(
      a.latitude,
      a.longitude,
      b.latitude,
      b.longitude,
    );
    return (meters / dt) * 3.6;
  }

  Future<void> _autoFollowTo(LatLng loc) async {
    if (_mapController == null) return;

    final now = DateTime.now();
    if (widget.followCamera &&
        (_suspendUntil == null || now.isAfter(_suspendUntil!))) {
      double zoom = 16.0;
      double tilt = 0.0;
      double bearing = 0.0;

      // derive speed & bearing from previous fix
      if (_prevLoc != null && _prevTs != null) {
        final v = _speedKmh(_prevLoc!, _prevTs!, loc, now);
        // speed-based zoom/tilt
        if (v < 10) {
          zoom = 16.5;
          tilt = 0;
        } else if (v < 30) {
          zoom = 15.5;
          tilt = 30;
        } else {
          zoom = 14.5;
          tilt = 45;
        }
        if (widget.courseUp) {
          bearing = _bearingDeg(_prevLoc!, loc);
        }
      }

      await _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: loc, zoom: zoom, tilt: tilt, bearing: bearing),
        ),
      );
    }

    _prevLoc = loc;
    _prevTs = now;
  }

  void _updateMarkersAndPolylines() {
    _markers.clear();

    if (widget.showMarkers) {
      _markers.addAll([
        // if (widget.currentLocation != null)
        //   Marker(
        //     markerId: const MarkerId('current_location'),
        //     position: widget.currentLocation!,
        //     icon: BitmapDescriptor.defaultMarkerWithHue(
        //       BitmapDescriptor.hueGreen,
        //     ),
        //     infoWindow: const InfoWindow(
        //       title: 'Current Location',
        //       snippet: 'You are here',
        //     ),
        //   ),
        if (widget.destination != null)
          Marker(
            markerId: const MarkerId('destination'),
            position: widget.destination!,
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueRed,
            ),
            infoWindow: const InfoWindow(
              title: 'Destination',
              snippet: 'Your destination',
            ),
          ),
      ]);
    } else {
      // show ONLY the final destination marker
      if (widget.destination != null) {
        _markers.add(
          Marker(
            markerId: const MarkerId('final_destination'),
            position: widget.destination!,
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueAzure,
            ), // pick any hue
            infoWindow: const InfoWindow(
              title: 'Final Destination',
              snippet: 'Selected stop',
            ),
          ),
        );
      }
    }

    // _polylines
    //   ..clear()
    //   ..addAll([
    //     if (widget.routePoints.isNotEmpty)
    //       Polyline(
    //         polylineId: const PolylineId('route'),
    //         points: widget.routePoints,
    //         color: const Color(0xFF1AB69C),
    //         width: 5,
    //       ),
    //   ]);

    //if (mounted) setState(() {});
  }

  bool _hasParentPolylines() => (widget.polylines?.isNotEmpty ?? false);

  List<LatLng> _collectCoveragePoints() {
    // Prefer parent polylines (all segments), else fall back to legacy routePoints
    final pts = <LatLng>[];
    if (_hasParentPolylines()) {
      for (final pl in widget.polylines!) {
        pts.addAll(pl.points);
      }
    } else if (widget.routePoints.isNotEmpty) {
      pts.addAll(widget.routePoints);
    }
    // Include endpoints to keep markers in view
    if (widget.currentLocation != null) pts.add(widget.currentLocation!);
    if (widget.destination != null) pts.add(widget.destination!);
    return pts;
  }

  Future<void> _fitToCoverage() async {
    if (_mapController == null) return;

    final points = _collectCoveragePoints();
    if (points.length < 2) {
      // Not enough to build bounds — just center if we can
      if (widget.currentLocation != null) {
        await _animateTo(widget.currentLocation!, zoom: 16);
      }
      return;
    }

    final bounds = _boundsFromLatLngList(points);
    try {
      await _mapController!.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, 80),
      );
    } catch (_) {
      await Future.delayed(const Duration(milliseconds: 150));
      await _mapController!.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, 80),
      );
    }
  }

  void _onMapCreated(GoogleMapController controller) {
    try {
      _mapController = controller;
      _isMapReady = true;
      _mapInitializationFailed = false;
      debugPrint("Google Maps initialized successfully!");

      // ✅ Prefer parent polylines/coverage, else fall back
      if (_hasParentPolylines() ||
          widget.routePoints.isNotEmpty ||
          widget.destination != null) {
        _fitToCoverage();
      } else if (widget.currentLocation != null) {
        _animateTo(widget.currentLocation!, zoom: 16);
      } else {
        _animateTo(
          const LatLng(17.3850, 78.4867),
          zoom: 12,
        ); // Hyderabad default
      }
      if (!_didInitialFocus && widget.currentLocation != null) {
        _didInitialFocus = true;
        _introFocus(widget.currentLocation!);
      }

      setState(() {});
    } catch (e) {
      debugPrint("Error initializing Google Maps: $e");
      _isMapReady = false;
    }
  }

  void _onMapTapped(LatLng location) => widget.onMapTapped(location);

  Future<void> _animateTo(LatLng target, {double zoom = 15}) async {
    if (_mapController == null) return;
    await _mapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: target, zoom: zoom),
      ),
    );
  }

  Future<void> _moveToCurrentLocation() async {
    if (widget.currentLocation != null) {
      await _animateTo(widget.currentLocation!, zoom: 16);
    } else {
      // Fallback to Hyderabad if we don't have a fix yet
      await _animateTo(const LatLng(17.3850, 78.4867), zoom: 12);
    }
    widget.onMyLocationPressed?.call();
  }

  LatLngBounds _boundsFromLatLngList(List<LatLng> list) {
    double? minLat, maxLat, minLng, maxLng;
    for (final p in list) {
      minLat = (minLat == null)
          ? p.latitude
          : (p.latitude < minLat ? p.latitude : minLat);
      maxLat = (maxLat == null)
          ? p.latitude
          : (p.latitude > maxLat ? p.latitude : maxLat);
      minLng = (minLng == null)
          ? p.longitude
          : (p.longitude < minLng ? p.longitude : minLng);
      maxLng = (maxLng == null)
          ? p.longitude
          : (p.longitude > maxLng ? p.longitude : maxLng);
    }
    return LatLngBounds(
      southwest: LatLng(minLat!, minLng!),
      northeast: LatLng(maxLat!, maxLng!),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1), // fixed
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            SizedBox(
              width: double.infinity,
              height: 280,
              child: GoogleMap(
                onMapCreated: _onMapCreated,
                initialCameraPosition: CameraPosition(
                  target:
                      widget.currentLocation ?? const LatLng(17.3850, 78.4867),
                  zoom: widget.currentLocation != null ? 16 : 12,
                ),
                onCameraMoveStarted: () {
                  widget.onUserGesture?.call();
                  _suspendUntil = DateTime.now().add(
                    Duration(milliseconds: widget.followSuspendMs),
                  );
                },
                mapType: _mapType, // dynamic map type
                markers: _markers,
                polylines: widget.polylines ?? <Polyline>{},
                onTap: _onMapTapped,
                onCameraMove: (cam) {
                  widget.onCameraMove?.call(cam);
                  widget.onLocationChanged(cam.target);
                },
                myLocationEnabled: widget.myLocationEnabled,
                myLocationButtonEnabled: widget.myLocationButtonEnabled,

                zoomControlsEnabled: false,
                mapToolbarEnabled: false,
                compassEnabled: true,
                rotateGesturesEnabled: true,
                scrollGesturesEnabled: true,
                tiltGesturesEnabled: true,
                zoomGesturesEnabled: true,
                buildingsEnabled: true,
                trafficEnabled: false,
                indoorViewEnabled: true,
                liteModeEnabled: false,

                gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                  Factory<OneSequenceGestureRecognizer>(
                    () => EagerGestureRecognizer(),
                  ),
                },
              ),
            ),

            // Loading overlay
            if (widget.isMapLoading ||
                (!_isMapReady && !_mapInitializationFailed))
              Positioned.fill(
                child: Container(
                  alignment: Alignment.center,
                  color: Colors.white.withValues(alpha: 0.8), // fixed
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Color(0xFF1AB69C),
                        ),
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Loading map...',
                        style: TextStyle(
                          color: Color(0xFF1AB69C),
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Map initialization failed overlay
            if (_mapInitializationFailed)
              Positioned.fill(
                child: Container(
                  alignment: Alignment.center,
                  color: Colors.white.withValues(alpha: 0.9), // fixed
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.map_outlined,
                        size: 64,
                        color: Colors.grey,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Map unavailable',
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Please check your internet connection\nand Google Maps API key',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey, fontSize: 14),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _mapInitializationFailed = false;
                            _isMapReady = false;
                          });
                          // retry guard again
                          Future.delayed(const Duration(seconds: 10), () {
                            if (!_isMapReady && mounted) {
                              setState(() => _mapInitializationFailed = true);
                            }
                          });
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1AB69C),
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),

            // Map controls
            Positioned(
              top: 16,
              right: 16,
              child: Column(
                children: [
                  // My Location Button
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1), // fixed
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: IconButton(
                      icon: const Icon(
                        Icons.my_location,
                        color: Color(0xFF1AB69C),
                      ),
                      onPressed: _moveToCurrentLocation,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Fit to Route Button
                  // Fit to Route Button
                  if ((widget.polylines?.isNotEmpty ?? false) ||
                      widget.routePoints.isNotEmpty)
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: IconButton(
                        icon: const Icon(
                          Icons.fit_screen,
                          color: Color(0xFF1AB69C),
                        ),
                        onPressed:
                            _fitToCoverage, // ✅ use the new coverage-based fitter
                      ),
                    ),
                ],
              ),
            ),

            // Map Type Selector (dynamic)
            Positioned(
              bottom: 16,
              right: 16,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1), // fixed
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: PopupMenuButton<MapType>(
                  icon: const Icon(Icons.layers, color: Color(0xFF1AB69C)),
                  onSelected: (mapType) => setState(() => _mapType = mapType),
                  itemBuilder: (BuildContext context) => const [
                    PopupMenuItem(value: MapType.normal, child: Text('Normal')),
                    PopupMenuItem(
                      value: MapType.satellite,
                      child: Text('Satellite'),
                    ),
                    PopupMenuItem(
                      value: MapType.terrain,
                      child: Text('Terrain'),
                    ),
                    PopupMenuItem(value: MapType.hybrid, child: Text('Hybrid')),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }
}
