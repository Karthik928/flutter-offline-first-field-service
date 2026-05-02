// FILE: lib/screena/lead_purpose_screen.dart
// LeadPurposeScreen — shows dealer details (same UI as DealerTicketScreen),
// then a camera-only file upload (preview), current location (lat/lng) and
// a required description text field. Submits via apiClient.sendOrQueue.
//
// Call example:
// Navigator.push(
//   context,
//   MaterialPageRoute(
//     builder: (_) => LeadPurposeScreen(
//       dealerId: dealerId,
//       dealerName: dealerName,
//       shopName: shopName,
//       address: address,
//       mobile: mobile,
//       latitude: lat,
//       longitude: lng,
//     ),
//   ),
// );

import 'dart:convert';
import 'dart:io';
import 'package:image/image.dart' as img;

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
import 'package:FieldService_app/utils/mediaoptimizer.dart';

class DealerLeadPurposeScreen extends StatefulWidget {
  // You can pass either a pre-built dealers list OR individual dealer fields.
  final List<DealerLite>? dealers;
  final DealerLite? preselected;

  // fields accepted by your call-site
  final String? dealerId;
  final String? dealerName;
  final String? shopName;
  final String? address;
  final String? mobile;
  final dynamic latitude; // accepts double/int/String (will be parsed)
  final dynamic longitude;
  final double pendingAmount;

  const DealerLeadPurposeScreen({
    super.key,
    this.dealers,
    this.preselected,
    this.dealerId,
    this.dealerName,
    this.shopName,
    this.address,
    this.mobile,
    this.latitude,
    this.longitude,
    required this.pendingAmount, // ✅ ADD
  });

  @override
  State<DealerLeadPurposeScreen> createState() =>
      _DealerLeadPurposeScreenState();
}

class _DealerLeadPurposeScreenState extends State<DealerLeadPurposeScreen> {
  final Color appGreen = const Color(0xFF2E7D32);

  // dealer list & selection (same behaviour as DealerTicketScreen)
  late List<DealerLite> _dealers;
  DealerLite? _selected;
  final String _search = '';
  String? _inlineBanner;

  // upload + location + description
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

  Future<File> _fixExifRotation(File file) async {
    final bytes = await file.readAsBytes();
    final original = img.decodeImage(bytes);
    if (original == null) return file;

    // This applies EXIF rotation into pixels
    final fixed = img.bakeOrientation(original);

    final newPath =
        "${file.parent.path}/fixed_${DateTime.now().millisecondsSinceEpoch}.jpg";

    final fixedFile = File(newPath)
      ..writeAsBytesSync(img.encodeJpg(fixed, quality: 100));

    return fixedFile;
  }

  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    try {
      return double.parse(v.toString());
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();

    // Build list: prefer provided dealers list; otherwise create one from fields
    if (widget.dealers != null && widget.dealers!.isNotEmpty) {
      _dealers = widget.dealers!;
    } else {
      final d = DealerLite(
        id: widget.dealerId,
        dealerName: widget.dealerName,
        shopName: widget.shopName,
        shopAddress: widget.address,
        mobile: widget.mobile,
        latitude: _toDouble(widget.latitude),
        longitude: _toDouble(widget.longitude),
      );
      _dealers = [d];
    }

    // preselected precedence: explicit preselected -> prefilled single dealer
    if (widget.preselected != null) {
      _selected = widget.preselected;
    } else if (_dealers.isNotEmpty) {
      _selected = _dealers.first;
    }
  }

  @override
  void dispose() {
    _descriptionCtrl.dispose();
    super.dispose();
  }

  List<DealerLite> get _filtered {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return _dealers;
    return _dealers.where((d) {
      return (d.dealerName?.toLowerCase().contains(q) ?? false) ||
          (d.shopName?.toLowerCase().contains(q) ?? false) ||
          (d.shopAddress?.toLowerCase().contains(q) ?? false) ||
          (d.mobile?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  void _errorTop(String msg) => _safeSet(() => _inlineBanner = msg);

  Future<void> _pickImageFromCamera() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.camera);

      if (picked == null) return;

      setState(() {
        _uploadingImage = true;
      });

      // ----------------------------
      // 1️⃣ GET LOCATION
      // ----------------------------
      await _fetchLocation();
      if (_latitude == null || _longitude == null) {
        _errorTop("Unable to capture location.");
        setState(() => _uploadingImage = false);
        return;
      }

      // ----------------------------
      // 2️⃣ PREPARE DATA
      // ----------------------------
      final timestamp = DateFormat(
        "yyyy-MM-dd HH:mm:ss",
      ).format(DateTime.now());

      final address = _locationAddress ?? "Unknown Address";
      final original = File(picked.path);

      // ----------------------------
      // 3️⃣ STAMP (RAW IMAGE)
      // ----------------------------
      final fixedFile = await _fixExifRotation(original);

      final stamped = await _stampImage(
        fixedFile,
        _latitude!,
        _longitude!,
        timestamp,
        address,
      );

      // ----------------------------
      // 4️⃣ OPTIMIZE (AFTER STAMP)
      // ----------------------------
      final optimized =
          await MediaOptimizer.getOptimizedImage(stamped) ?? stamped;

      // ----------------------------
      // 5️⃣ SET FINAL IMAGE
      // ----------------------------
      if (!mounted) return;
      setState(() {
        _imageFile = optimized;
        _uploadingImage = false;
      });
    } catch (e) {
      _errorTop("Camera error: $e");
      if (mounted) setState(() => _uploadingImage = false);
    }
  }

  // ----------------- Update _removeImage -----------------
  void _removeImage() {
    _safeSet(() {
      _imageFile = null;
      _latitude = null;
      _longitude = null;
      _locationAddress = null; // Reset address too
    });
  }

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

      // compute font size in doubles and ensure result is a double
      final fontSize = (width.toDouble() / 15.0).clamp(22.0, 60.0).toDouble();

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
          "${imageFile.parent.path}/lead_stamp_${DateTime.now().millisecondsSinceEpoch}.png";

      final stampedFile = File(stampedPath);
      await stampedFile.writeAsBytes(byteData!.buffer.asUint8List());

      debugPrint("IMAGE HEIGHT: $height");
      debugPrint("TEXT HEIGHT: ${painter.height}");
      debugPrint("DY: $dy");

      return stampedFile;
    } catch (e) {
      debugPrint("STAMP ERROR: $e");
      return imageFile;
    }
  }

  // ---------- Location (Geolocator) ----------
  Future<void> _fetchLocation() async {
    try {
      _safeSet(() {});

      // --- Permissions ---
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

      // --- Coordinates ---
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(accuracy: LocationAccuracy.high),
      );

      _safeSet(() {
        _latitude = pos.latitude;
        _longitude = pos.longitude;
      });

      // --- Reverse Geocode (Full Address) ---
      // --- Reverse Geocode (Hybrid: Google → placemark → offline) ---
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
        _locationAddress = addr ?? "Offline — address unavailable";
      });
    } catch (e) {
      _errorTop("Failed to get location: $e");
    }
  }

  // ---------- Submit lead ----------
  bool get _canSubmit =>
      _selected != null &&
      (_imageFile != null) &&
      (_descriptionCtrl.text.trim().isNotEmpty) &&
      !_submitting;

  Future<void> _submitLead() async {
    FocusScope.of(context).unfocus();

    if (_selected == null) {
      _errorTop('Please select a dealer first.');
      return;
    }
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
        _safeSet(() => _submitting = false);
        return;
      }

      final dealer = _selected!;
      final address = _locationAddress ?? "Unknown Address";

      debugPrint("Dealer ID: ${dealer.id}");

      // --------------------------------------------
      // BUILD JSON BODY
      // --------------------------------------------
      final body = {
        "employeeId": employeeId,
        if (effectiveTripId.isNotEmpty) "tripId": effectiveTripId,
        "idOfVisitor[id]": widget.dealerId,
        "idOfVisitor[type]": "Dealer",
        "purpose": "Lead",
        "reason": _descriptionCtrl.text.trim(),
        "address": address,
      };

      // --------------------------------------------
      // PREPARE FILE FOR MULTIPART (sent as QueuedFile)
      // --------------------------------------------
      final ext = _imageFile!.path.split('.').last.toLowerCase();
      final mime = ext == 'jpg' || ext == 'jpeg' ? 'image/jpeg' : 'image/png';

      final imageFile = QueuedFile(
        field: "images",
        path: _imageFile!.path,
        filename: "lead_${DateTime.now().millisecondsSinceEpoch}.$ext",
        contentType: mime,
      );

      // --------------------------------------------
      // SEND OR QUEUE
      // --------------------------------------------
      final resp = await apiClient.sendOrQueue(
        method: HttpVerb.post,
        path: AppConfig.othervisits,
        jsonBody: body,
        files: [imageFile],
        optimisticOk: true,
      );

      if (!mounted) return;

      // --------------------------------------------
      // OFFLINE → QUEUED
      // --------------------------------------------
      if (resp == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("📡 Offline — saved and will auto-sync"),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
        _safeReset();
        return;
      }

      // --------------------------------------------
      // SERVER RESPONSE
      // --------------------------------------------
      if (resp.statusCode == 200 || resp.statusCode == 201) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("submitted successfully")));
        _safeReset();
        Navigator.pop(context);
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
      _selected = null;
      _imageFile = null;
      _latitude = null;
      _longitude = null;
      _descriptionCtrl.clear();
    });
  }

  // ---------- Build UI ----------
  @override
  Widget build(BuildContext context) {
    final items = _filtered;

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: Container(
          decoration: const BoxDecoration(
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
            gradient: LinearGradient(
              colors: [
                Color(0xFF52D494), // top
                Color(0xFF1AB69C), // bottom
              ],
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
              'Other — Purpose',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
          ),
        ),
      ),

      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Inline banner
              if ((_inlineBanner ?? '').isNotEmpty)
                _TopBarMessage(
                  message: _inlineBanner!,
                  onClose: () => _safeSet(() => _inlineBanner = null),
                ),

              const SizedBox(height: 8),

              // Dealer list header
              // Row(
              //   children: [
              //     const Icon(Icons.store, size: 20, color: Color(0xFF1AB69C)),
              //     const SizedBox(width: 8),
              //     Expanded(
              //       child: Text(
              //         'Selected dealer',
              //         style: TextStyle(color: Colors.grey[700]),
              //       ),
              //     ),
              //   ],
              // ),
              const SizedBox(height: 4),

              // Dealer list
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: items.isEmpty ? 1 : items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  if (items.isEmpty) {
                    return _EmptyState(
                      icon: Icons.store,
                      title: 'No dealers found',
                    );
                  }
                  final d = items[i];
                  return _DealerTile(
                    dealer: d,
                    pendingAmount: widget.pendingAmount, // ✅ PASS IT
                  );
                },
              ),

              const SizedBox(height: 12),

              // ----------------- Camera + Location preview -----------------
              // ----------------- Camera + Location preview (Card UI) -----------------
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: const BorderSide(
                    color: Color(0xFF1AB69C), // <-- border color
                    width: 1.3, // optional
                  ),
                ),
                clipBehavior: Clip.hardEdge,
                child: Container(
                  height: 220,
                  color: Theme.of(context).colorScheme.surface,
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      // ----------------------------
                      // LEFT : IMAGE PREVIEW
                      // ----------------------------
                      Expanded(
                        flex: 2,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: _imageFile == null
                              ? Material(
                                  color: Theme.of(context).colorScheme.onSurface
                                      .withValues(alpha: 0.03),
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
                                                  size: 28,
                                                  color: Color(0xFF1AB69C),
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
                                    Image.file(
                                      _imageFile!,
                                      fit: BoxFit.contain,
                                    ),

                                    // gradient overlay
                                    Container(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: [
                                            Colors.black.withValues(
                                              alpha: 0.12,
                                            ),
                                            Colors.transparent,
                                          ],
                                        ),
                                      ),
                                    ),

                                    // remove button
                                    Positioned(
                                      right: 8,
                                      top: 8,
                                      child: Material(
                                        color: Colors.black45,
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

                      // ----------------------------
                      // RIGHT : ADDRESS + LAT/LNG
                      // ----------------------------
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
                                  color: Theme.of(context).colorScheme.onSurface
                                      .withValues(alpha: 0.02),
                                  borderRadius: BorderRadius.circular(8),
                                ),

                                // -----------------------------------
                                // SHOW LOADER HERE WHEN IMAGE UPLOADING
                                // -----------------------------------
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
                        labelText: 'Description / Details',
                        filled: true,
                        fillColor: Colors.grey.withValues(alpha: 0.06),

                        // Border when NOT focused
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Color(0xFF1AB69C), // green border
                            width: 1.5,
                          ),
                        ),

                        // Border when focused
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Color(0xFF1AB69C),
                            width: 2,
                          ),
                        ),

                        // Border when error
                        errorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Colors.red,
                            width: 1.5,
                          ),
                        ),

                        // Border when focused + error
                        focusedErrorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Colors.red,
                            width: 2,
                          ),
                        ),
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
                        backgroundColor: Color(0xFF1AB69C),
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
                                valueColor: AlwaysStoppedAnimation(
                                  Colors.white,
                                ),
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
      ),
    );
  }
}

/* ========================= Supporting models & widgets (copied style) ========================= */

class DealerLite {
  final String? id;
  final String? dealerName;
  final String? shopName;
  final String? shopAddress;
  final String? mobile;
  final double? latitude;
  final double? longitude;

  DealerLite({
    this.id,
    this.dealerName,
    this.shopName,
    this.shopAddress,
    this.mobile,
    this.latitude,
    this.longitude,
  });
}

class _DealerTile extends StatelessWidget {
  const _DealerTile({
    required this.dealer,
    required this.pendingAmount, // ✅ ADD
  });

  final DealerLite dealer;
  final double pendingAmount; // ✅ ADD

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Color(0xFF1AB69C), width: 1.3),
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
          // Left icon
          const Icon(Icons.store, size: 28, color: (Color(0xFF1AB69C))),
          const SizedBox(width: 10),

          // Dealer info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                /// Dealer Name (bold)
                if ((dealer.dealerName?.trim().isNotEmpty ?? false))
                  Text(
                    dealer.dealerName!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),

                /// Shop name (sub-title)
                if ((dealer.shopName?.trim().isNotEmpty ?? false))
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      dealer.shopName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[700],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),

                const SizedBox(height: 6),

                /// Mobile
                if ((dealer.mobile ?? '').isNotEmpty)
                  Row(
                    children: [
                      Icon(Icons.phone, size: 16, color: Color(0xFF1AB69C)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          dealer.mobile!,
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

                /// Address
                Row(
                  children: [
                    Icon(Icons.place, size: 16, color: Color(0xFF1AB69C)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        dealer.shopAddress ?? '-',
                        style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),

                /// Lat Lng (optional)
                if (dealer.latitude != null && dealer.longitude != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Lat: ${dealer.latitude}, Lng: ${dealer.longitude}',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                ],
                const SizedBox(height: 12),

                Row(
                  children: [
                    Icon(
                      Icons.account_balance_wallet,
                      size: 15,
                      color: Color(0xFF1AB69C),
                    ),
                    const SizedBox(width: 8),
                    Builder(
                      builder: (_) {
                        // formatter for Indian currency (₹) with thousands separators
                        final fmt = NumberFormat.currency(
                          locale: 'en_IN',
                          symbol: '₹',
                          decimalDigits: 2,
                        );
                        final pending = pendingAmount;

                        final noDue = pending <= 0.0;
                        debugPrint('pendingAmount=${pending.toString()}');
                        // Debug.log(
                        //   'Dealer ${d.shopName} pendingAmount: $pending'
                        //       as num,
                        // );
                        return Flexible(
                          child: Text(
                            noDue ? 'No Due' : 'Due: ${fmt.format(pending)}',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              color: noDue
                                  ? Colors.green
                                  : const Color.fromARGB(255, 255, 0, 0),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        );
                      },
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

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.title});
  final IconData icon;
  final String title;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: Colors.grey[500]),
            const SizedBox(height: 10),
            Text(title, style: TextStyle(color: Colors.grey[700])),
          ],
        ),
      ),
    );
  }
}
