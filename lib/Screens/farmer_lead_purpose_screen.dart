// FILE: lib/screena/farmer_lead_purpose_screen.dart
//
// FarmerLeadPurposeScreen — shows farmer details,
// camera-only photo capture, current location (lat/lng),
// and a required description field.
// Submits via the Other Visit API (/api/othervisits/)
// with:
//   purpose     = "Lead Purpose"
//   idOfVisitor = farmerId
//   reason      = description
//   address     = reverse-geocoded full address
//   images      = multipart

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:FieldService_app/config.dart';
import 'package:FieldService_app/main.dart';
import 'package:FieldService_app/offline/request_envelope.dart';

import 'dart:ui' as ui;
import 'package:intl/intl.dart';
import 'package:image/image.dart' as img;
import 'package:FieldService_app/utils/mediaoptimizer.dart';

class FarmerLeadPurposeScreen extends StatefulWidget {
  final String farmerId;
  final String farmerName;
  final String address;
  final String mobile;

  const FarmerLeadPurposeScreen({
    super.key,
    required this.farmerId,
    required this.farmerName,
    required this.address,
    required this.mobile,
  });

  @override
  State<FarmerLeadPurposeScreen> createState() =>
      _FarmerLeadPurposeScreenState();
}

class _FarmerLeadPurposeScreenState extends State<FarmerLeadPurposeScreen> {
  final Color appGreen = const Color(0xFF2E7D32);

  String? _inlineBanner;

  File? _imageFile;
  bool _uploadingImage = false;

  double? _latitude;
  double? _longitude;
  String? _locationAddress;

  final _descriptionCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _submitting = false;

  void _safeSet(void Function() fn) {
    if (!mounted) return;
    setState(fn);
  }

  @override
  void dispose() {
    _descriptionCtrl.dispose();
    super.dispose();
  }

  void _errorTop(String msg) => _safeSet(() => _inlineBanner = msg);

  // ----- NEW: fix EXIF rotation (bake orientation) -----
  Future<File> _fixExifRotation(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final original = img.decodeImage(bytes);
      if (original == null) return file;

      final fixed = img.bakeOrientation(original);

      final newPath =
          "${file.parent.path}/fixed_${DateTime.now().millisecondsSinceEpoch}.jpg";

      final fixedFile = File(newPath)
        ..writeAsBytesSync(img.encodeJpg(fixed, quality: 100));

      return fixedFile;
    } catch (e) {
      debugPrint("EXIF FIX ERROR: $e");
      return file;
    }
  }

  // ----- NEW: stamp image with address/lat/lng/time using canvas -----
  Future<File> _stampImage(
    File imageFile,
    double lat,
    double lng,
    String time,
    String address,
  ) async {
    try {
      final bytes = await imageFile.readAsBytes();

      final ui.Codec codec = await ui.instantiateImageCodec(bytes);
      final ui.FrameInfo frame = await codec.getNextFrame();
      final ui.Image image = frame.image;

      final int width = image.width;
      final int height = image.height;

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(
        recorder,
        ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      );

      // draw original
      canvas.drawImage(image, ui.Offset.zero, ui.Paint());

      final text =
          "Address: $address\n"
          "Lat: ${lat.toStringAsFixed(6)}\n"
          "Lng: ${lng.toStringAsFixed(6)}\n"
          "Time: $time";

      // compute font size safely as double
      final double fontSize = (width.toDouble() / 15.0)
          .clamp(22.0, 60.0)
          .toDouble();

      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: Colors.white,
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            shadows: const [
              Shadow(color: Colors.black, blurRadius: 6, offset: Offset(2, 2)),
            ],
          ),
        ),
        textDirection: ui.TextDirection.ltr,
      );

      painter.layout(maxWidth: width * 0.9);

      const double pad = 40.0;
      final double dx = pad;

      double dy = height.toDouble() - painter.height - pad;
      if (dy < pad) dy = pad;

      // background
      final bgRect = ui.Rect.fromLTWH(
        dx - 12,
        dy - 12,
        painter.width + 24,
        painter.height + 24,
      );

      canvas.drawRRect(
        ui.RRect.fromRectAndRadius(bgRect, const ui.Radius.circular(14)),
        ui.Paint()..color = const Color(0x99000000),
      );

      painter.paint(canvas, Offset(dx, dy));

      final picture = recorder.endRecording();
      final stampedImage = await picture.toImage(width, height);
      final byteData = await stampedImage.toByteData(
        format: ui.ImageByteFormat.png,
      );

      final stampedPath =
          "${imageFile.parent.path}/farmer_stamp_${DateTime.now().millisecondsSinceEpoch}.png";

      final stampedFile = File(stampedPath);
      await stampedFile.writeAsBytes(byteData!.buffer.asUint8List());

      debugPrint("STAMPED: $stampedPath");
      debugPrint("IMAGE HEIGHT: $height");
      debugPrint("TEXT HEIGHT: ${painter.height}");
      debugPrint("DY: $dy");

      return stampedFile;
    } catch (e, st) {
      debugPrint("STAMP ERROR: $e\n$st");
      return imageFile;
    }
  }

  // ---------- Camera capture ----------
  Future<void> _pickImageFromCamera() async {
    try {
      final XFile? picked = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 90,
      );

      if (picked == null) return;

      // show a preview immediately (will be replaced after stamp/opt)
      _safeSet(() => _imageFile = File(picked.path));

      // Start loader while we fetch location and process image
      _safeSet(() => _uploadingImage = true);

      // 1) get location
      await _fetchLocation();

      if (_latitude == null || _longitude == null) {
        _errorTop("Unable to capture location.");
        _safeSet(() => _uploadingImage = false);
        return;
      }

      // prepare metadata
      final timestamp = DateFormat(
        "yyyy-MM-dd HH:mm:ss",
      ).format(DateTime.now());
      final address = _locationAddress ?? "Unknown Address";
      final original = File(picked.path);

      // 2) fix EXIF rotation (important!)
      final fixedFile = await _fixExifRotation(original);

      // 3) stamp
      final stamped = await _stampImage(
        fixedFile,
        _latitude!,
        _longitude!,
        timestamp,
        address,
      );

      // 4) optimize (after stamp)
      final optimized =
          await MediaOptimizer.getOptimizedImage(stamped) ?? stamped;

      // 5) set final image
      if (!mounted) return;
      _safeSet(() {
        _imageFile = optimized;
        _uploadingImage = false;
      });
    } catch (e, st) {
      debugPrint("CAMERA FLOW ERROR: $e\n$st");
      _errorTop('Failed to capture/process image: $e');
      if (mounted) _safeSet(() => _uploadingImage = false);
    }
  }

  void _removeImage() {
    _safeSet(() {
      _imageFile = null;
      _latitude = null;
      _longitude = null;
      _locationAddress = null;
    });
  }

  // ---------- Location (Geolocator + reverse geocode) ----------
  Future<void> _fetchLocation() async {
    try {
      // Permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _errorTop('Location permission denied');
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        _errorTop('Location permission permanently denied');
        return;
      }

      // Coordinates
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      _safeSet(() {
        _latitude = pos.latitude;
        _longitude = pos.longitude;
      });

      // Reverse geocode
      String? addr;
      try {
        // --- GOOGLE GEOCODING API ---
        final key = AppConfig.googleMapsApiKey;
        final url =
            "https://maps.googleapis.com/maps/api/geocode/json"
            "?latlng=${pos.latitude},${pos.longitude}"
            "&key=$key";

        final resp = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 4));

        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body);

          if (data["status"] == "OK" && data["results"].isNotEmpty) {
            addr = data["results"][0]["formatted_address"];
          } else {
            throw Exception("Google returned no results");
          }
        } else {
          throw Exception("Google returned ${resp.statusCode}");
        }
      } catch (googleErr) {
        // GOOGLE FAILED → TRY placemark
        try {
          final placemarks = await placemarkFromCoordinates(
            pos.latitude,
            pos.longitude,
          ).timeout(const Duration(seconds: 4));

          if (placemarks.isNotEmpty) {
            final p = placemarks.first;

            addr = [
              p.name,
              p.street,
              p.subLocality,
              p.locality,
              p.subAdministrativeArea,
              p.administrativeArea,
              p.postalCode,
              p.country,
            ].where((e) => e != null && e.trim().isNotEmpty).join(", ");
          } else {
            throw Exception("Placemark empty");
          }
        } catch (localErr) {
          // BOTH FAILED → OFFLINE
          addr = "Offline — address unavailable";
        }
      }

      _safeSet(() {
        _locationAddress = addr ?? 'Offline — address unavailable';
      });
    } catch (e) {
      _errorTop('Failed to get location: $e');
    }
  }

  // ---------- Submit lead ----------
  bool get _canSubmit =>
      _imageFile != null && // final image ready
      !_uploadingImage && // stamping + compression finished
      _latitude != null &&
      _longitude != null &&
      _locationAddress != null && // address fetched
      _locationAddress!.trim().isNotEmpty &&
      _descriptionCtrl.text.trim().isNotEmpty &&
      !_submitting;

  Future<void> _submitLead() async {
    FocusScope.of(context).unfocus();

    if (_imageFile == null) {
      _errorTop('Please capture a photo (camera).');
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) {
      _errorTop('Please add a description.');
      return;
    }
    if (_latitude == null || _longitude == null) {
      _errorTop("Location not captured.");
      return;
    }

    _safeSet(() => _submitting = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final employeeId = prefs.getString('userId') ?? "";
      final tripId = prefs.getString('currentTripId') ?? '';
      final tripCompleted = prefs.getBool('tripCompleted') ?? false;
      final effectiveTripId = tripCompleted == true ? tripId : '';

      if (employeeId.isEmpty) {
        _errorTop("Missing employeeId. Please login again.");
        return;
      }

      // -----------------------------
      // Build the full address
      // -----------------------------
      final address = _locationAddress?.trim().isNotEmpty == true
          ? _locationAddress!
          : widget.address;

      debugPrint("Farmer ID: ${widget.farmerId}");

      // -----------------------------
      // JSON BODY
      // -----------------------------
      final body = {
        "employeeId": employeeId,
        if (effectiveTripId.isNotEmpty) "tripId": effectiveTripId,
        "idOfVisitor[id]": widget.farmerId,
        "idOfVisitor[type]": "Farmer",
        "purpose": "Lead Purpose",
        "reason": _descriptionCtrl.text.trim(),
        "address": address,
      };

      // Prepare image for QueuedFile (detect ext/mime)
      // -----------------------------
      final ext = _imageFile!.path.split('.').last.toLowerCase();
      final mime = (ext == 'jpg' || ext == 'jpeg') ? 'image/jpeg' : 'image/png';

      final img = QueuedFile(
        field: "images",
        path: _imageFile!.path,
        filename: "farmer_lead_${DateTime.now().millisecondsSinceEpoch}.$ext",
        contentType: mime,
      );

      // -----------------------------
      // SEND OR QUEUE
      // -----------------------------
      final resp = await apiClient.sendOrQueue(
        method: HttpVerb.post,
        path: AppConfig.othervisits,
        jsonBody: body,
        files: [img],
        optimisticOk: true, // treat queue as success in UI
      );

      if (!mounted) return;

      // -----------------------------
      // OFFLINE QUEUED
      // -----------------------------
      if (resp == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("📡 Offline — farmer lead saved & will auto-sync"),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
        _safeReset();
        Navigator.of(context).pop(true);
        return;
      }

      // -----------------------------
      // ONLINE SERVER RESPONSE
      // -----------------------------
      if (resp.statusCode == 200 || resp.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Farmer lead submitted successfully")),
        );
        _safeReset();
        Navigator.of(context).pop(true);
      } else {
        _errorTop("Failed (${resp.statusCode}): ${resp.body}");
      }
    } catch (e) {
      _errorTop("Network error: $e");
    } finally {
      if (mounted) _safeSet(() => _submitting = false);
    }
  }

  void _safeReset() {
    _safeSet(() {
      _imageFile = null;
      _latitude = null;
      _longitude = null;
      _locationAddress = null;
      _descriptionCtrl.clear();
    });
  }

  // ---------- Build UI ----------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Other - Purpose',
          style: TextStyle(color: Colors.white),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_sharp, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
            gradient: LinearGradient(
              colors: [Color(0xFF52D494), Color(0xFF1AB69C)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if ((_inlineBanner ?? '').isNotEmpty)
              _TopBarMessage(
                message: _inlineBanner!,
                onClose: () => _safeSet(() => _inlineBanner = null),
              ),

            const SizedBox(height: 8),

            // Header
            Row(
              children: [
                const Icon(
                  Icons.agriculture,
                  size: 20,
                  color: Color(0xFF1AB69C),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Selected farmer',
                    style: TextStyle(color: Colors.grey[700]),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 4),

            _FarmerTile(
              farmerName: widget.farmerName,
              address: widget.address,
              mobile: widget.mobile,
            ),

            const SizedBox(height: 12),

            // Camera + Location card
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: Color(0xFF1AB69C), width: 1.2),
              ),
              clipBehavior: Clip.hardEdge,
              child: Container(
                height: 220,
                color: Theme.of(context).colorScheme.surface,
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    // LEFT: Image preview
                    Expanded(
                      flex: 2,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),

                        child: _imageFile == null
                            ? Material(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.03),
                                child: InkWell(
                                  onTap: _uploadingImage
                                      ? null
                                      : _pickImageFromCamera,
                                  child: Center(
                                    child: _uploadingImage
                                        ? const CircularProgressIndicator()
                                        : Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: const [
                                              Icon(
                                                Icons.camera_alt_outlined,
                                                color: Color(0xFF1AB69C),
                                                size: 28,
                                              ),
                                              SizedBox(height: 6),
                                              Text(
                                                'Tap to capture\n(camera only)',
                                                textAlign: TextAlign.center,
                                              ),
                                            ],
                                          ),
                                  ),
                                ),
                              )
                            : Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image.file(_imageFile!, fit: BoxFit.cover),
                                  Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          Colors.black.withValues(alpha: 0.12),
                                          Colors.transparent,
                                        ],
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    right: 8,
                                    top: 8,
                                    child: Material(
                                      color: Colors.white,
                                      shape: const CircleBorder(),
                                      child: InkWell(
                                        customBorder: const CircleBorder(),
                                        onTap: _removeImage,
                                        child: const Padding(
                                          padding: EdgeInsets.all(6),
                                          child: Icon(
                                            Icons.close,
                                            size: 18,
                                            color: Color(0xFF1AB69C),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),

                    const SizedBox(width: 12),

                    // RIGHT: Address + Lat/Lng
                    Expanded(
                      flex: 1,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 8),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.02),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: _uploadingImage
                                  ? const Center(
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                      ),
                                    )
                                  : (_latitude != null && _longitude != null)
                                  ? Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        if (_locationAddress != null &&
                                            _locationAddress!.isNotEmpty) ...[
                                          Text(
                                            _locationAddress!,
                                            textAlign: TextAlign.right,
                                            maxLines: 8,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: Colors.grey[800],
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                        ],
                                        Text(
                                          'Lat: ${_latitude!.toStringAsFixed(6)}',
                                          textAlign: TextAlign.right,
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            color: Colors.grey[700],
                                          ),
                                        ),
                                        Text(
                                          'Lng: ${_longitude!.toStringAsFixed(6)}',
                                          textAlign: TextAlign.right,
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            color: Colors.grey[700],
                                          ),
                                        ),
                                        const Spacer(),
                                      ],
                                    )
                                  : Center(
                                      child: Text(
                                        'No location captured.\nTap camera to take photo.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: Colors.grey[600],
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Description + Submit
            Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _descriptionCtrl,
                    minLines: 2,
                    maxLines: 5,
                    decoration: InputDecoration(
                      labelText: 'Description / Details (required)',
                      filled: true,
                      fillColor: Colors.grey.withValues(alpha: 0.06),

                      // ──────────────── FIXED BORDER COLORS ────────────────
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Color(0xFF1AB69C),
                          width: 1.2,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Color(0xFF1AB69C),
                          width: 1.8,
                        ),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Colors.red,
                          width: 1.2,
                        ),
                      ),
                      focusedErrorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Colors.red,
                          width: 1.8,
                        ),
                      ),
                      // ──────────────────────────────────────────────────────
                    ),
                    validator: (v) => (v ?? '').trim().isEmpty
                        ? 'Description is required'
                        : null,
                    onChanged: (_) => _safeSet(() {}),
                  ),

                  const SizedBox(height: 12),

                  ElevatedButton(
                    onPressed: _canSubmit ? _submitLead : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1AB69C),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _submitting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(Colors.white),
                            ),
                          )
                        : const Text(
                            'Submit Lead',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                  ),

                  const SizedBox(height: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    // );
  }
}

/* ========================= Supporting widgets ========================= */

class _FarmerTile extends StatelessWidget {
  final String farmerName;
  final String address;
  final String mobile;

  const _FarmerTile({
    required this.farmerName,
    required this.address,
    required this.mobile,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Color(0xFF1AB69C), // <-- your border color here
          width: 1.2, // optional
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.agriculture, size: 28, color: Color(0xFF1AB69C)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  farmerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                if (mobile.trim().isNotEmpty)
                  Row(
                    children: [
                      Icon(Icons.phone, size: 16, color: Color(0xFF1AB69C)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          mobile,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[700],
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.place, size: 16, color: Color(0xFF1AB69C)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        address,
                        style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
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
}

class _TopBarMessage extends StatelessWidget {
  const _TopBarMessage({required this.message, required this.onClose});
  final String message;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    if (message.trim().isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFE8E8),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFFC2C2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.red, fontSize: 13.5),
            ),
          ),
          InkWell(
            onTap: onClose,
            child: const Icon(Icons.close, size: 18, color: Colors.red),
          ),
        ],
      ),
    );
  }
}
