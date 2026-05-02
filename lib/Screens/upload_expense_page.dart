import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:FieldService_app/Screens/expenses_list_page.dart';
import 'package:FieldService_app/config.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as path;
import 'package:FieldService_app/main.dart';
import 'package:FieldService_app/offline/request_envelope.dart';
import 'package:FieldService_app/utils/mediaoptimizer.dart';

class UploadExpensePage extends StatefulWidget {
  const UploadExpensePage({super.key});

  @override
  State<UploadExpensePage> createState() => _UploadExpensePageState();
}

class _UploadExpensePageState extends State<UploadExpensePage> {
  File? _selectedFile;
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  bool _isUploading = false;

  Future<File> _stampExpenseImage(
    File imageFile,
    Position pos,
    String time,
    String address,
  ) async {
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

    // Draw original
    canvas.drawImage(image, Offset.zero, Paint());

    // Text
    final String text =
        "Address: $address\n"
        "Lat: ${pos.latitude.toStringAsFixed(6)}\n"
        "Lng: ${pos.longitude.toStringAsFixed(6)}\n"
        "Time: $time";

    final double fontSize = (width / 15).clamp(22, 60);

    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: Colors.white,
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          shadows: [
            Shadow(
              color: Colors.black.withValues(alpha: 0.9),
              blurRadius: 6,
              offset: Offset(3, 3),
            ),
          ],
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    );

    painter.layout(maxWidth: width * 0.92);

    const pad = 30.00;
    final dx = pad;
    final dy = height - painter.height - pad - 20;

    // Background
    final bg = ui.Rect.fromLTWH(
      dx - 15,
      dy - 15,
      painter.width + 30,
      painter.height + 30,
    );

    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(bg, const ui.Radius.circular(18)),
      Paint()..color = const Color(0x99000000),
    );

    // Draw text
    painter.paint(canvas, Offset(dx, dy));

    final picture = recorder.endRecording();
    final stampedImage = await picture.toImage(width, height);
    final byteData = await stampedImage.toByteData(
      format: ui.ImageByteFormat.png,
    );

    final stampedPath =
        "${imageFile.parent.path}/expense_stamp_${DateTime.now().millisecondsSinceEpoch}.png";

    final stampedFile = File(stampedPath);
    await stampedFile.writeAsBytes(byteData!.buffer.asUint8List());

    return stampedFile;
  }

  Future<void> uploadExpense() async {
    if (_selectedFile == null ||
        _descriptionController.text.trim().isEmpty ||
        _amountController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please attach a file and enter details."),
        ),
      );
      return;
    }

    setState(() => _isUploading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final companyId = prefs.getString('companyId');
      final employeeId = prefs.getString('userId');

      if (companyId == null || employeeId == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("User session data missing.")),
        );
        return;
      }

      // ---------- BUILD JSON BODY ----------
      final body = {
        'companyId': companyId,
        'employeeId': employeeId,
        'amount': _amountController.text.trim(),
        'remark': _descriptionController.text.trim(),
      };

      // ---------- PREPARE FILE AS QueuedFile ----------
      final filePath = _selectedFile!.path;
      final fileName = path.basename(filePath);
      String? mimeType = lookupMimeType(filePath) ?? 'application/octet-stream';

      final files = <QueuedFile>[
        QueuedFile(
          field: 'image',
          path: filePath,
          filename: fileName,
          contentType: mimeType,
        ),
      ];

      // ---------- SEND OR QUEUE ----------
      final resp = await apiClient.sendOrQueue(
        method: HttpVerb.post,
        path: AppConfig.expenseUpload,
        jsonBody: body,
        files: files,
        optimisticOk: true,
      );

      if (!mounted) return;

      if (resp == null) {
        // OFFLINE → QUEUED
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('📡 Offline – saved to queue, will auto-sync later'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );

        setState(() {
          _selectedFile = null;
          _descriptionController.clear();
          _amountController.clear();
        });

        return;
      }

      // ---------- SERVER RESPONSE ----------
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        // SUCCESS
        setState(() {
          _selectedFile = null;
          _descriptionController.clear();
          _amountController.clear();
        });

        // SAME SUCCESS BOTTOM SHEET YOU ALREADY BUILT
        showModalBottomSheet(
          context: context,
          isDismissible: false,
          enableDrag: false,
          backgroundColor: Colors.transparent,
          builder: (context) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFFDCFCE7),
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(16),
                    child: const Icon(
                      Icons.check_circle_rounded,
                      color: Color(0xFF1AB69C),
                      size: 60,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "Expense Uploaded!",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "Your expense was uploaded successfully.\nYou can view all expenses anytime.",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.black54),
                  ),
                  const SizedBox(height: 25),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            side: const BorderSide(
                              color: Color(0xFF1AB69C),
                              width: 1.5, // optional
                            ),
                          ),
                          onPressed: () => Navigator.pop(context),
                          child: const Text(
                            "Close",
                            style: TextStyle(color: Colors.black),
                          ),
                        ),
                      ),

                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Color(0xFF1AB69C),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),

                          onPressed: () {
                            Navigator.pop(context); // close sheet
                            Navigator.pop(context); // close page
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ExpensesListPage(),
                              ),
                            );
                          },
                          child: const Text(
                            "View Expenses",
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Upload failed: ${resp.body}"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e"), backgroundColor: Colors.redAccent),
      );
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _pickFromCamera() async {
    final pickedFile = await ImagePicker().pickImage(
      source: ImageSource.camera,
    );

    if (pickedFile == null) return;

    setState(() => _isUploading = true);

    // --- 1. GET LOCATION ---
    Position pos;

    try {
      bool enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) throw "GPS_OFF";

      LocationPermission perm = await Geolocator.checkPermission();

      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }

      if (perm == LocationPermission.denied) {
        throw "PERMISSION_DENIED";
      }

      if (perm == LocationPermission.deniedForever) {
        throw "PERMISSION_DENIED_FOREVER";
      }

      // ✅ 1. Try LAST KNOWN POSITION (FAST, NO GPS HIT)
      final lastPos = await Geolocator.getLastKnownPosition();

      if (lastPos != null &&
          DateTime.now().difference(lastPos.timestamp).inMinutes < 5) {
        pos = lastPos;
      } else {
        pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 6),
          ),
        );
      }
    } catch (e) {
      setState(() => _isUploading = false);

      if (!mounted) return;

      String message;

      switch (e.toString()) {
        case "GPS_OFF":
          message = "Please turn on GPS";
          break;
        case "PERMISSION_DENIED":
          message = "Location permission denied";
          break;
        case "PERMISSION_DENIED_FOREVER":
          message = "Enable location permission from settings";
          break;
        default:
          message = "Unable to fetch location";
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));

      return;
    }

    Future<String> safeAddressLookup(Position pos) async {
      // --- 1) GOOGLE GEOCODING API ---
      try {
        final key = AppConfig.googleMapsApiKey;
        final url =
            "https://maps.googleapis.com/maps/api/geocode/json"
            "?latlng=${pos.latitude},${pos.longitude}"
            "&key=$key";

        final resp = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 4));

        if (resp.statusCode == 200) {
          final json = jsonDecode(resp.body);

          if (json["status"] == "OK" && json["results"].isNotEmpty) {
            return json["results"][0]["formatted_address"];
          } else {
            throw Exception("Google empty results");
          }
        } else {
          throw Exception("Google HTTP ${resp.statusCode}");
        }
      } catch (googleErr) {
        debugPrint("⚠️ Google geocode failed: $googleErr");
      }

      // --- 2) FALLBACK → placemarkFromCoordinates ---
      try {
        final placemarks = await placemarkFromCoordinates(
          pos.latitude,
          pos.longitude,
        ).timeout(const Duration(seconds: 4), onTimeout: () => []);

        if (placemarks.isNotEmpty) {
          final p = placemarks.first;

          return [
            p.name,
            p.street,
            p.subLocality,
            p.locality,
            p.subAdministrativeArea,
            p.administrativeArea,
            p.postalCode,
            p.country,
          ].where((v) => v != null && v.trim().isNotEmpty).join(", ");
        }
      } catch (localErr) {
        debugPrint("⚠️ Placemark fallback failed: $localErr");
      }

      // --- 3) LAST RESORT ---
      return "Offline / Address Unavailable";
    }

    // --- 2. TIMESTAMP ---
    final timestamp = DateFormat("yyyy-MM-dd HH:mm:ss").format(DateTime.now());

    // --- 3. ADDRESS LOOKUP ---
    final address = await safeAddressLookup(pos);

    // --- 4. STAMP IMAGE ---
    final original = File(pickedFile.path);

    // 1️⃣ Stamp image (GPS + time burned in)
    final stamped = await _stampExpenseImage(original, pos, timestamp, address);

    // 2️⃣ Compress + resize stamped image
    final optimized =
        await MediaOptimizer.getOptimizedImage(stamped) ?? stamped;

    // 3️⃣ Use optimized file for upload / queue
    setState(() {
      _selectedFile = optimized;
      _isUploading = false;
    });
  }

  Future<void> _pickFromGallery() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
    );
    if (result != null && result.files.single.path != null) {
      setState(() => _selectedFile = File(result.files.single.path!));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isImage =
        _selectedFile != null &&
        [
          '.jpg',
          '.jpeg',
          '.png',
        ].any((ext) => _selectedFile!.path.endsWith(ext));

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        elevation: 0,
        title: const Text(
          "Submit Expense",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_sharp, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),

        // Rounded bottom shape
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
        ),

        // HERE is the gradient fix
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color(0xFF52D494), // top color
                Color(0xFF1AB69C), // bottom color
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
          ),
        ),
      ),

      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFF7F8FA), Color(0xFFEFF1F5)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 125, 20, 30),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height,
            ),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // HEADER
                  const Text(
                    "Upload Your Bill or Receipt",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "Submit expense details for record keeping.",
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
                  ),
                  const SizedBox(height: 20),

                  // Upload Section
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _pickFromCamera,
                                icon: const Icon(Icons.camera_alt_outlined),
                                label: const Text("Capture Bill"),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Color(0xFF1AB69C),
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _pickFromGallery,
                                icon: const Icon(Icons.folder_open_rounded),
                                label: const Text("Choose File"),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Color(0xFF1AB69C),
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 20),

                        if (_selectedFile != null)
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Color(0xFF1AB69C)),
                            ),
                            child: Column(
                              children: [
                                if (isImage)
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: Image.file(
                                      _selectedFile!,
                                      height: 180,
                                      width: double.infinity,
                                      fit: BoxFit.cover,
                                    ),
                                  )
                                else
                                  ListTile(
                                    leading: const Icon(
                                      Icons.picture_as_pdf,
                                      color: Colors.red,
                                    ),
                                    title: Text(
                                      _selectedFile!.path.split('/').last,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    subtitle: const Text("PDF Document"),
                                  ),
                                const SizedBox(height: 10),
                                TextButton.icon(
                                  onPressed: () =>
                                      setState(() => _selectedFile = null),
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    color: Colors.red,
                                  ),
                                  label: const Text(
                                    "Remove File",
                                    style: TextStyle(color: Colors.red),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 30),

                  // Description
                  const Text(
                    "Amount in Rupees",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _amountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'^\d*\.?\d{0,2}$'),
                      ),
                    ],
                    maxLines: 1,
                    decoration: InputDecoration(
                      hintText: "Ex: 9999.90",
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                        borderSide: BorderSide(
                          color: Color(0xFF1AB69C),
                          width: 1.4,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 30),

                  // Description
                  const Text(
                    "Description",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _descriptionController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: "Ex: Petrol Expense",
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                        borderSide: BorderSide(
                          color: Color(0xFF1AB69C),
                          width: 1.4,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 35),

                  // Submit Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isUploading ? null : uploadExpense,
                      icon: _isUploading
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.cloud_upload_rounded),
                      label: Text(
                        _isUploading ? "Uploading..." : "Submit Expense",
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(0xFF1AB69C),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
