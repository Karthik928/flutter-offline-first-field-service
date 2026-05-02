import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:FieldService_app/config.dart';
import 'package:FieldService_app/main.dart';
import 'package:FieldService_app/offline/request_envelope.dart';
import 'package:FieldService_app/utils/mediaoptimizer.dart'; // NEW

class OtherVisitScreen extends StatefulWidget {
  const OtherVisitScreen({super.key});

  @override
  State<OtherVisitScreen> createState() => _OtherVisitScreenState();
}

class _OtherVisitScreenState extends State<OtherVisitScreen> {
  File? _imageFile;
  final TextEditingController _reasonController = TextEditingController();

  bool _isLoading = false;
  Position? _position;
  String? _timestamp;
  String? _addressFromStamp;

  // ----------------------------------------------------------
  // STAMP TEXT ON IMAGE (USING CANVAS)
  // ----------------------------------------------------------
  // ... other imports

  Future<File> stampImage(
    File imageFile,
    Position pos,
    String time,
    String address,
  ) async {
    try {
      final bytes = await imageFile.readAsBytes();

      // Reliable decoding
      final ui.Codec codec = await ui.instantiateImageCodec(bytes);
      final ui.FrameInfo frame = await codec.getNextFrame();
      final ui.Image image = frame.image;

      final int width = image.width;
      final int height = image.height;

      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final ui.Canvas canvas = ui.Canvas(
        recorder,
        ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      );

      // Draw the main image
      canvas.drawImage(image, ui.Offset.zero, ui.Paint());

      // ---- TEXT TO DRAW ----
      final String text =
          "Address: $address\n"
          "Lat: ${pos.latitude.toStringAsFixed(6)}\n"
          "Lng: ${pos.longitude.toStringAsFixed(6)}\n"
          "Time: $time";

      final double fontSize = (width / 15).clamp(22, 60);

      final TextPainter painter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: Colors.white,
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            shadows: [
              Shadow(
                color: Colors.black.withValues(alpha: 0.9),
                blurRadius: 5,
                offset: Offset(2, 2),
              ),
            ],
          ),
        ),
        textAlign: TextAlign.left,
        textDirection: ui.TextDirection.ltr, // <-- THIS IS FINE HERE
      );

      // const double pad = 30; // <-- MORE PADDING
      // final double dx = pad;
      // final double dy = height - painter.height - pad - 0; // <-- MOVE UP A BIT

      painter.layout(maxWidth: width * 0.9);

      const double pad = 50;
      final double dx = pad;
      final double dy = height - painter.height - pad;

      // Background for readability
      final bgRect = ui.Rect.fromLTWH(
        dx - 10,
        dy - 10,
        painter.width + 20,
        painter.height + 20,
      );

      final bgPaint = ui.Paint()..color = const Color(0x99000000);
      canvas.drawRRect(
        ui.RRect.fromRectAndRadius(bgRect, const ui.Radius.circular(12)),
        bgPaint,
      );

      painter.paint(canvas, Offset(dx, dy));

      final ui.Picture picture = recorder.endRecording();
      final ui.Image stampedImage = await picture.toImage(width, height);

      final byteData = await stampedImage.toByteData(
        format: ui.ImageByteFormat.png,
      );

      final stampedPath =
          "${imageFile.parent.path}/stamped_${DateTime.now().millisecondsSinceEpoch}.png";

      final stampedFile = File(stampedPath);
      await stampedFile.writeAsBytes(byteData!.buffer.asUint8List());

      debugPrint("STAMPED: $stampedPath");
      debugPrint("SIZE: ${await stampedFile.length()} bytes");

      return stampedFile;
    } catch (e, st) {
      debugPrint("STAMP ERROR: $e\n$st");
      return imageFile;
    }
  }

  // ----------------------------------------------------------
  // GET LOCATION
  // ----------------------------------------------------------
  Future<void> _getLocation() async {
    bool enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      _showError("Enable GPS to continue.");
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _showError("Location permission denied.");
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      _showError("Location permanently denied. Enable in settings.");
      return;
    }

    final pos = await Geolocator.getCurrentPosition();
    if (!mounted) return;
    setState(() => _position = pos);
  }

  // ----------------------------------------------------------
  // PICK IMAGE AND STAMP
  // ----------------------------------------------------------
  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.camera);

    if (picked == null) return;

    setState(() => _isLoading = true);

    // Get GPS
    await _getLocation();
    if (_position == null) {
      setState(() => _isLoading = false);
      _showError("Unable to fetch location.");
      return;
    }

    // ----- NEW: FORMATTED DATE -----
    _timestamp = DateFormat("yyyy-MM-dd HH:mm:ss").format(DateTime.now());

    // ----- NEW: REVERSE GEOCODING (GET ADDRESS) -----
    List<Placemark> placemarks = await placemarkFromCoordinates(
      _position!.latitude,
      _position!.longitude,
    );

    final place = placemarks.first;
    final address = [
      place.name,
      place.street,
      place.subLocality,
      place.locality,
      place.subAdministrativeArea,
      place.administrativeArea,
      place.postalCode,
      place.country,
    ].where((e) => e != null && e.trim().isNotEmpty).join(", ");

    final original = File(picked.path);

    // ----- NEW: PASS ADDRESS TO STAMP -----
    final stamped = await stampImage(
      original,
      _position!,
      _timestamp!,
      address,
    );

    _addressFromStamp = address;

    // ------------------------------
    // 📏 BEFORE OPTIMIZATION LOG
    // ------------------------------
    final beforeBytes = await stamped.length();
    final beforeMB = beforeBytes / (1024 * 1024);

    debugPrint(
      "📸 BEFORE OPTIMIZATION: "
      "${beforeMB.toStringAsFixed(2)} MB ($beforeBytes bytes)",
    );

    // ------------------------------
    // 🔧 OPTIMIZE IMAGE (STAMPED)
    // ------------------------------
    final optimized =
        await MediaOptimizer.getOptimizedImage(stamped) ?? stamped;

    // ------------------------------
    // 📉 AFTER OPTIMIZATION LOG
    // ------------------------------
    final afterBytes = await optimized.length();
    final afterMB = afterBytes / (1024 * 1024);

    debugPrint(
      "✅ AFTER OPTIMIZATION: "
      "${afterMB.toStringAsFixed(2)} MB ($afterBytes bytes)",
    );

    // ------------------------------
    // 🧮 SAVINGS LOG
    // ------------------------------
    final savedPercent = ((beforeBytes - afterBytes) / beforeBytes * 100).clamp(
      0,
      100,
    );

    debugPrint("📉 SIZE REDUCTION: ${savedPercent.toStringAsFixed(1)}%");

    // ------------------------------
    // USE OPTIMIZED FILE
    // ------------------------------
    setState(() {
      _imageFile = optimized;
      _isLoading = false;
    });
  }

  // ----------------------------------------------------------
  // SUBMIT
  // ----------------------------------------------------------
  Future<void> _submit() async {
    if (_imageFile == null) {
      _showError("Capture an image first.");
      return;
    }

    if (_reasonController.text.trim().isEmpty) {
      _showError("Enter Visit Details.");
      return;
    }

    if (_position == null) {
      _showError("Location not detected.");
      return;
    }

    setState(() => _isLoading = true);

    try {
      // -----------------------------------------
      // GET EMPLOYEE ID
      // -----------------------------------------
      final prefs = await SharedPreferences.getInstance();
      final employeeId = prefs.getString("userId") ?? "";
      final tripId = prefs.getString('currentTripId') ?? '';
      final tripCompleted = prefs.getBool('tripCompleted') ?? false;
      final effectiveTripId = tripCompleted == true ? tripId : '';
      debugPrint("Employee ID: $employeeId");
      debugPrint("Trip ID: $tripId");
      debugPrint("Effective Trip ID: $effectiveTripId");
      if (employeeId.isEmpty) {
        _showError("Missing employeeId. Please login again.");
        return;
      }

      // -----------------------------------------
      // BUILD JSON BODY
      // -----------------------------------------
      final body = {
        "employeeId": employeeId,
        if (effectiveTripId.isNotEmpty) "tripId": effectiveTripId,
        //"idOfVisitor": "",
        //"idOfVisitor[id]": "",
        //"idOfVisitor[type]": "",
        "purpose": "OtherVisit",
        "reason": _reasonController.text.trim(),
        "address": _addressFromStamp ?? "Unknown Address",
      };

      // -----------------------------------------
      // PREPARE FILE FOR MULTIPART UPLOAD
      // -----------------------------------------
      final ext = _imageFile!.path.split('.').last.toLowerCase();
      final mime = ext == 'jpg' || ext == 'jpeg' ? 'image/jpeg' : 'image/png';

      final visitFile = QueuedFile(
        field: "images",
        path: _imageFile!.path,
        filename: "visit_${DateTime.now().millisecondsSinceEpoch}.$ext",
        contentType: mime,
      );

      // -----------------------------------------
      // SEND OR QUEUE
      // -----------------------------------------
      final resp = await apiClient.sendOrQueue(
        method: HttpVerb.post,
        path: AppConfig.othervisits,
        jsonBody: body,
        files: [visitFile],
        optimisticOk: true, // treat queued as success from UI side
      );

      // -----------------------------------------
      // OFFLINE → QUEUED
      // -----------------------------------------
      if (resp == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("📡 Offline — visit saved & will auto-sync"),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context, true);
        return;
      }

      // -----------------------------------------
      // SERVER RESPONSE
      // -----------------------------------------
      final status = resp.statusCode;
      if (status == 200 || status == 201) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Visit created successfully")),
        );
        Navigator.pop(context, true);
      } else {
        _showError("Failed ($status): ${resp.body}");
      }
    } catch (e) {
      _showError("Error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ----------------------------------------------------------
  // ERROR HANDLER
  // ----------------------------------------------------------
  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ----------------------------------------------------------
  // UI
  // ----------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          appBar: PreferredSize(
            preferredSize: const Size.fromHeight(60),
            child: Container(
              decoration: const BoxDecoration(
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(24),
                ),
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
                  borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(24),
                  ),
                ),
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back_sharp, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
                title: const Text(
                  'Other Visit',
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
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GestureDetector(
                  onTap: _pickImage,
                  child: Container(
                    height: 550,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Color(0xFF1AB69C)),
                      color: Colors.grey.shade200,
                    ),
                    child: _imageFile == null
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(
                                Icons.camera_alt,
                                size: 48,
                                color: Color(0xFF1AB69C),
                              ),
                              SizedBox(height: 8),
                              Text("Tap to capture image"),
                            ],
                          )
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.file(
                              File(_imageFile!.path),
                              key: ValueKey(
                                _imageFile!.path,
                              ), // <-- Forces rebuild
                              fit: BoxFit.cover,
                              alignment: Alignment.bottomCenter,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: 24),

                TextField(
                  controller: _reasonController,
                  maxLength: 100,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: "Reason / Visit Details",
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                        color: Color(0xFF1AB69C), // your custom border color
                        width: 1.5,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                        color: Color(0xFF1AB69C),
                        width: 1.5,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                        color: Color(0xFF1AB69C),
                        width: 2.0, // slightly thicker when focused
                      ),
                    ),
                  ),
                ),

                // const SizedBox(height: 20),

                // if (_position != null)
                //   Text(
                //     "Location: ${_position!.latitude}, ${_position!.longitude}",
                //     style: const TextStyle(
                //       fontSize: 14,
                //       fontWeight: FontWeight.w500,
                //     ),
                //   ),

                // if (_timestamp != null)
                //   Text(
                //     "Time: $_timestamp",
                //     style: const TextStyle(
                //       fontSize: 14,
                //       fontWeight: FontWeight.w500,
                //     ),
                //   ),
                const SizedBox(height: 24),

                ElevatedButton(
                  onPressed: _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFF1AB69C),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    "Submit Visit",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ),

        if (_isLoading)
          Container(
            color: Colors.black.withValues(alpha: 0.4),
            child: const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          ),
      ],
    );
  }
}
