// FILE: lib/screena/farmer_ticket_screen.dart
// FarmerTicketScreen — same UI & behavior as your Farmer tab but
// accepts a list of farmers (no network GET). Copy this file to
// lib/screena/farmer_ticket_screen.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart'; // ✅ NEW
import 'dart:io';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:FieldService_app/config.dart';
import 'package:FieldService_app/main.dart';
import 'package:FieldService_app/offline/request_envelope.dart';
import 'package:FieldService_app/services/secure_storage_service.dart';
import 'package:FieldService_app/utils/mediaoptimizer.dart';

class FarmerTicketScreen extends StatefulWidget {
  final String farmerId;
  final String farmerName;
  final String address;
  final String mobile;
  final bool? tripCompleted;
  final num pendingAmount; // NEW: pending due amount

  const FarmerTicketScreen({
    super.key,
    required this.farmerId,
    required this.farmerName,
    required this.address,
    required this.mobile,
    required this.tripCompleted,
    required this.pendingAmount,
  });

  @override
  State<FarmerTicketScreen> createState() => _FarmerTicketScreenState();
}

class _FarmerTicketScreenState extends State<FarmerTicketScreen> {
  final Color appGreen = const Color(0xFF1AB69C);

  _FarmerLite? _selected; // Single farmer only

  String? _inlineBanner;

  final _formKey = GlobalKey<FormState>();
  final _farmerNameCtrl = TextEditingController();
  final _mobileCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  // ───────── MULTI-POND STATE ─────────
  final List<_PondForm> _ponds = [_PondForm()];
  static const int _maxPonds = 4;

  final _remarksCtrl = TextEditingController();

  bool _submitting = false;

  final List<XFile> _images = []; // ✅ NEW
  final ImagePicker _picker = ImagePicker(); // ✅ NEW

  // formatters

  // Integers only (up to N digits)
  TextInputFormatter intLimit(int maxDigits) =>
      LengthLimitingTextInputFormatter(maxDigits);

  // Decimal numbers: XXXX.XX
  TextInputFormatter decimalLimit({int maxInt = 4, int maxDecimal = 2}) =>
      FilteringTextInputFormatter.allow(
        RegExp(
          r'^\d{0,'
          '$maxInt'
          r'}(\.\d{0,'
          '$maxDecimal'
          r'})?$',
        ),
      );

  static final List<TextInputFormatter> _pondNameFmt = [
    FilteringTextInputFormatter.allow(RegExp(r"[A-Za-z0-9 ]")),
    LengthLimitingTextInputFormatter(40),
  ];

  static final List<TextInputFormatter> _lettersAndDigitsOnly = [
    FilteringTextInputFormatter.allow(RegExp(r"[A-Za-z0-9 ]")),
    LengthLimitingTextInputFormatter(100),
  ];

  void _addPond() {
    if (_ponds.length >= _maxPonds) {
      _errorTop('You can add up to $_maxPonds ponds only');
      return;
    }
    _safeSet(() => _ponds.add(_PondForm()));
  }

  void _removePond(int index) {
    if (_ponds.length == 1) return;
    final removed = _ponds.removeAt(index);
    removed.dispose();
    _safeSet(() {});
  }

  InputDecoration _pondDecoration(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: Colors.grey.withValues(alpha: 0.06),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: Colors.grey.withValues(alpha: 0.25),
          width: 1,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: appGreen, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red, width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red, width: 1.6),
      ),
    );
  }

  Future<void> _pickFromCamera() async {
    if (_images.length >= 3) return;
    final img = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 70,
      maxWidth: 1280,
    );
    if (img != null) _safeSet(() => _images.add(img));
  }

  Future<void> _pickFromGallery() async {
    final imgs = await _picker.pickMultiImage(imageQuality: 70, maxWidth: 1280);
    if (imgs.isNotEmpty) {
      final remaining = 3 - _images.length;
      _safeSet(() => _images.addAll(imgs.take(remaining)));
    }
  }

  void _removeImage(int index) {
    _safeSet(() => _images.removeAt(index));
  }

  //bool get _isFish => _speciesCtrl.text.trim().toLowerCase() == 'fish';

  void _safeSet(void Function() fn) {
    if (!mounted) return;
    setState(fn);
  }

  @override
  void initState() {
    super.initState();
    _selected = _FarmerLite(
      id: widget.farmerId,
      name: widget.farmerName,
      mobile: widget.mobile,
      location: widget.address,
    );

    _farmerNameCtrl.text = widget.farmerName;
    _mobileCtrl.text = widget.mobile;
    _locationCtrl.text = widget.address;
  }

  @override
  void dispose() {
    _farmerNameCtrl.dispose();
    _mobileCtrl.dispose();
    _locationCtrl.dispose();

    _remarksCtrl.dispose();

    for (final p in _ponds) {
      p.dispose();
    }
    super.dispose();
  }

  String? _vRequired(String? v, String label) {
    if ((v ?? '').trim().isEmpty) return '$label is required';
    return null;
  }

  String? _vRequiredInt(String? v, String label) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return '$label is required';
    if (!RegExp(r'^\d+$').hasMatch(s)) return '$label must be an integer';
    return null;
  }

  bool get _canSubmitFarmer =>
      _remarksCtrl.text.trim().isNotEmpty && !_submitting;

  void _errorTop(String msg) => _safeSet(() => _inlineBanner = msg);

  Future<List<QueuedFile>> _prepareTicketImages() async {
    final files = <QueuedFile>[];

    for (final image in _images) {
      final originalFile = File(image.path);
      if (!originalFile.existsSync()) {
        debugPrint('⚠️ FarmerTicket image file missing: ${image.path}');
        continue;
      }

      final optimizedFile = await MediaOptimizer.getOptimizedImage(
        originalFile,
      );
      final finalFile = optimizedFile ?? originalFile;
      final sizeMB = await MediaOptimizer.getFileSizeMB(finalFile);

      if (sizeMB > 5) {
        throw Exception(
          'Image too large (${sizeMB.toStringAsFixed(2)} MB). Please select a smaller image.',
        );
      }

      final fileName = image.name.isNotEmpty
          ? image.name
          : finalFile.path.split('/').last;
      final ext = fileName.split('.').last.toLowerCase();
      final mime = ext == 'png' ? 'image/png' : 'image/jpeg';

      debugPrint('📦 FarmerTicket image file: $fileName @ ${finalFile.path}');
      debugPrint('📊 FarmerTicket image size: ${sizeMB.toStringAsFixed(2)} MB');

      files.add(
        QueuedFile(
          field: 'images',
          path: finalFile.path,
          filename: fileName,
          contentType: mime,
        ),
      );
    }

    return files;
  }

  Future<void> _submitFarmerTicket() async {
    FocusScope.of(context).unfocus();

    if (_selected == null) {
      _errorTop('Please select a farmer.');
      return;
    }

    if (!(_formKey.currentState?.validate() ?? false)) {
      _errorTop('Please correct the highlighted fields.');
      return;
    }

    if (_remarksCtrl.text.trim().isEmpty) {
      _errorTop('Remarks are required.');
      return;
    }

    _errorTop('');
    _safeSet(() => _submitting = true);

    try {
      final prefs = await SharedPreferences.getInstance();

      final companyId = prefs.getString('companyId') ?? '';
      final employeeId = prefs.getString('userId') ?? '';
      final tripId = prefs.getString('currentTripId') ?? '';
      final tripCompleted = prefs.getBool('tripCompleted') ?? false;
      final effectiveTripId = tripCompleted == true ? tripId : '';
      final token = await SecureStorageService.getToken();

      final location = _locationCtrl.text.trim().isNotEmpty
          ? _locationCtrl.text.trim()
          : '(Offline — address unavailable)';

      final ponds = _ponds.map((p) => p.toJson()).toList();

      final List<QueuedFile> files = await _prepareTicketImages();

      final body = {
        "companyId": companyId,
        if (effectiveTripId.isNotEmpty) "tripId": effectiveTripId,
        "employeeId": employeeId,
        "farmerId": _selected!.id ?? '',
        "farmerName": _farmerNameCtrl.text.trim(),
        "mobileNumber": _mobileCtrl.text.trim(),
        "address": location,
        "remarks": _remarksCtrl.text.trim(),
        "status": "Pending", // ✅ REQUIRED (you missed this)
      };

      for (int i = 0; i < ponds.length; i++) {
        final pond = ponds[i];

        body['ponds[$i][pondName]'] = pond['pondName'].toString();
        body['ponds[$i][culturedArea]'] = pond['culturedArea'].toString();
        body['ponds[$i][culturedSpecies]'] = pond['culturedSpecies'].toString();

        // Physical
        final phys = (pond['physicalReadings'] as List).first;
        body['ponds[$i][physicalReadings][0][stockingPL]'] = phys['stockingPL']
            .toString();
        body['ponds[$i][physicalReadings][0][doc]'] = phys['doc'].toString();
        body['ponds[$i][physicalReadings][0][feedIntakePerDay]'] =
            phys['feedIntakePerDay'].toString();
        body['ponds[$i][physicalReadings][0][count]'] = phys['count']
            .toString();

        if (phys['avgWeight'] != null) {
          body['ponds[$i][physicalReadings][0][avgWeight]'] = phys['avgWeight']
              .toString();
        }

        // Chemical
        final chem = (pond['chemicalReadings'] as List).first;
        body['ponds[$i][chemicalReadings][0][salinity]'] = chem['salinity']
            .toString();
        body['ponds[$i][chemicalReadings][0][ph]'] = chem['ph'].toString();
        body['ponds[$i][chemicalReadings][0][alkalinity]'] = chem['alkalinity']
            .toString();
        body['ponds[$i][chemicalReadings][0][ammonia]'] = chem['ammonia']
            .toString();
        body['ponds[$i][chemicalReadings][0][nitrite]'] = chem['nitrite']
            .toString();
        body['ponds[$i][chemicalReadings][0][dissolvedOxygen]'] =
            chem['dissolvedOxygen'].toString();

        // Disease (optional)
        final disease = pond['diseaseReadings'] as List;
        if (disease.isNotEmpty) {
          body['ponds[$i][diseaseReadings][0][vibrios]'] = disease
              .first['vibrios']
              .toString();
        }
      }

      for (final f in files) {
        debugPrint('📤 FILE FIELD: ${f.field}');
        debugPrint('📤 FILE PATH: ${f.path}');
      }

      debugPrint('🧾 [FarmerTicket] POST ${AppConfig.farmerTicket}');
      debugPrint('🧾 [FarmerTicket] body: ${jsonEncode(body)}');

      final resp = await apiClient.sendOrQueue(
        method: HttpVerb.post,
        path: AppConfig.farmerTicket,
        jsonBody: body,
        files: files, // ✅ NEW
        headers: {'Authorization': 'Bearer $token'},
        optimisticOk: true,
      );

      if (!mounted) return;

      if (resp == null) {
        // ✅ OFFLINE QUEUE
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Queued offline — will sync automatically'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
        _safeResetFarmerForm();
      } else if (resp.statusCode == 200 || resp.statusCode == 201) {
        // ✅ ONLINE SUCCESS
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Farmer query submitted successfully'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
        _safeResetFarmerForm();
      } else {
        String msg = 'HTTP ${resp.statusCode}';
        debugPrint(msg);

        try {
          final j = jsonDecode(resp.body);
          if (j is Map && j['message'] is String) {
            msg = j['message'];
          }
        } catch (_) {}

        _errorTop('Failed to raise query: $msg');
      }
    } catch (e) {
      _errorTop('Network error: $e');
    } finally {
      _safeSet(() => _submitting = false);
    }
  }

  void _safeResetFarmerForm() {
    _safeSet(() {
      _selected = null;
      _farmerNameCtrl.clear();
      _mobileCtrl.clear();
      _locationCtrl.clear();
      _ponds.clear();
      _images.clear(); // ✅ NEW
      _ponds.add(_PondForm());
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Farmer Query',
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
      body: Column(
        children: [
          if ((_inlineBanner ?? '').isNotEmpty)
            _TopBarMessage(
              message: _inlineBanner!,
              onClose: () => _safeSet(() => _inlineBanner = null),
            ),
          // READ-ONLY FARMER CARD
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: _FarmerInfoCard(
              name: widget.farmerName,
              mobile: widget.mobile,
              address: widget.address,
              pendingAmount: widget.pendingAmount.toInt(),
            ),
          ),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              children: [_extraFormCard()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _extraFormCard() {
    return Card(
      elevation: 2,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            // Pond Name
            // ───────── PONDS HEADER ─────────
            SizedBox(height: 10),
            Row(
              children: [
                SizedBox(width: 10),
                Text(
                  'Ponds (${_ponds.length}/$_maxPonds)',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: _ponds.length >= _maxPonds ? null : _addPond,
                  icon: const Icon(Icons.add),
                  label: const Text('Add Pond'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: appGreen,
                    side: BorderSide(color: appGreen),
                  ),
                ),
                SizedBox(width: 10),
              ],
            ),

            const SizedBox(height: 10),

            // ───────── POND CARDS ─────────
            Column(
              children: List.generate(_ponds.length, (i) {
                return _pondCard(
                  index: i,
                  pf: _ponds[i],
                  onRemove: _ponds.length == 1 ? null : () => _removePond(i),
                );
              }),
            ),

            const SizedBox(height: 16),

            // ───── IMAGES ─────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Upload Images (${_images.length}/3)",
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),

                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: _images.length >= 3 ? null : _pickFromCamera,
                        icon: const Icon(Icons.camera_alt),
                        label: const Text("Camera"),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        onPressed: _images.length >= 3
                            ? null
                            : _pickFromGallery,
                        icon: const Icon(Icons.photo),
                        label: const Text("Gallery"),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  if (_images.isNotEmpty)
                    SizedBox(
                      height: 90,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _images.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 10),
                        itemBuilder: (_, i) {
                          final file = _images[i];
                          return Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.file(
                                  File(file.path),
                                  width: 90,
                                  height: 90,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Positioned(
                                top: 4,
                                right: 4,
                                child: GestureDetector(
                                  onTap: () => _removeImage(i),
                                  child: const CircleAvatar(
                                    radius: 10,
                                    backgroundColor: Colors.black54,
                                    child: Icon(
                                      Icons.close,
                                      size: 12,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Remarks
            TextFormField(
              controller: _remarksCtrl,
              decoration: InputDecoration(
                labelText: 'Remarks (required)',
                // labelStyle: const TextStyle(
                //   color: Color(0xFF1AB69C),
                // ), // label color
                filled: true,
                fillColor: Colors.grey.withValues(alpha: 0.06),

                // ───────────── BORDER COLORS (FIXED) ─────────────
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.grey, width: 1.2),
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
                  borderSide: const BorderSide(color: Colors.red, width: 1.2),
                ),
                focusedErrorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.red, width: 1.8),
                ),
                // ────────────────────────────────────────────────
              ),

              inputFormatters: _lettersAndDigitsOnly,
              maxLines: 3,
              validator: (v) => _vRequired(v, 'Remarks'),
              onChanged: (_) => _safeSet(() {}),
              cursorColor: const Color(0xFF1AB69C), // cursor color (optional)
            ),

            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _canSubmitFarmer ? _submitFarmerTicket : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(0xFF1AB69C),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 48),
                ),
                child: _submitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Raise Farmer Query'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pondCard({
    required int index,
    required _PondForm pf,
    VoidCallback? onRemove,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ───── Header ─────
          Row(
            children: [
              Text(
                'Pond ${index + 1}',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              if (onRemove != null)
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: onRemove,
                ),
            ],
          ),

          const SizedBox(height: 8),

          // ───── Pond Name ─────
          TextFormField(
            controller: pf.pondName,
            decoration: _pondDecoration('Pond Name'),
            inputFormatters: _pondNameFmt,
            validator: (v) => _vRequired(v, 'Pond name'),
          ),

          const SizedBox(height: 8),

          // ───── Pond Size ─────
          TextFormField(
            controller: pf.size,
            decoration: _pondDecoration('Pond Size (acres)'),
            inputFormatters: [decimalLimit(maxInt: 4, maxDecimal: 2)],
            keyboardType: const TextInputType.numberWithOptions(decimal: true),

            validator: (v) => _vRequired(v, 'Pond size'),
          ),

          const SizedBox(height: 10),

          // ───── Species Selector ─────
          MenuAnchor(
            controller: pf.menuCtrl,
            childFocusNode: FocusNode(),
            builder: (context, controller, _) {
              return TextFormField(
                key: pf.speciesKey,
                readOnly: true,
                decoration: _pondDecoration(
                  'Culture Species',
                ).copyWith(suffixIcon: const Icon(Icons.keyboard_arrow_down)),

                controller: TextEditingController(text: pf.species ?? ''),
                onTap: () =>
                    controller.isOpen ? controller.close() : controller.open(),
                validator: (_) =>
                    pf.species == null ? 'Species is required' : null,
              );
            },
            menuChildren: [
              _pondMenuItem('Shrimp', pf),
              _pondMenuItem('Fish', pf),
            ],
          ),

          // ───── Physical ─────
          const SizedBox(height: 12),
          const Text(
            'Physical Parameters',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1AB69C),
            ),
          ),
          const SizedBox(height: 8),

          TextFormField(
            controller: pf.stockingPL,
            decoration: _pondDecoration('Stocking PL'),

            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              intLimit(7),
            ],
            keyboardType: TextInputType.number,

            validator: (v) => _vRequiredInt(v, 'Stocking PL'),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: pf.doc,
            decoration: _pondDecoration('DOC'),
            keyboardType: TextInputType.number,
            validator: (v) => _vRequiredInt(v, 'DOC'),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: pf.feed,
            decoration: _pondDecoration('Feed Intake / Day'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            validator: (v) => _vRequired(v, 'Feed intake'),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: pf.count,
            decoration: _pondDecoration('Count'),
            keyboardType: TextInputType.number,
            validator: (v) => _vRequiredInt(v, 'Count'),
          ),
          const SizedBox(height: 10),
          if (pf.species == 'Fish')
            TextFormField(
              controller: pf.avgWeight,
              decoration: _pondDecoration('Avg Weight'),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),

          const SizedBox(height: 16),
          const Text(
            'Chemical Parameters',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1AB69C),
            ),
          ),
          const SizedBox(height: 8),

          TextFormField(
            controller: pf.salinity,
            decoration: _pondDecoration('Salinity'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),

          const SizedBox(height: 10),
          TextFormField(
            controller: pf.ph,
            decoration: _pondDecoration('pH'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),

          const SizedBox(height: 10),
          TextFormField(
            controller: pf.alkalinity,
            decoration: _pondDecoration('Alkalinity'),
            keyboardType: TextInputType.number,
          ),

          const SizedBox(height: 10),
          TextFormField(
            controller: pf.ammonia,
            decoration: _pondDecoration('Ammonia'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),

          const SizedBox(height: 10),
          TextFormField(
            controller: pf.nitrite,
            decoration: _pondDecoration('Nitrite'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),

          const SizedBox(height: 10),
          TextFormField(
            controller: pf.dissolvedOxygen,
            decoration: _pondDecoration('Dissolved Oxygen'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),

          const SizedBox(height: 16),
          const Text(
            'Disease Parameters',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1AB69C),
            ),
          ),
          const SizedBox(height: 8),

          TextFormField(
            controller: pf.vibrios,
            decoration: _pondDecoration('Vibrios (CFU/ml)'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
        ],
      ),
    );
  }

  Widget _pondMenuItem(String value, _PondForm pf) {
    final selected = pf.species == value;

    return InkWell(
      onTap: () {
        setState(() {
          pf.species = value;
          if (value != 'Fish') {
            pf.avgWeight.clear();
          }
        });
        pf.menuCtrl.close();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        color: selected
            ? const Color(0xFF1AB69C).withValues(alpha: 0.12)
            : null,
        child: Row(
          children: [
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: selected ? const Color(0xFF1AB69C) : Colors.black,
              ),
            ),
            const Spacer(),
            if (selected)
              const Icon(
                Icons.check_circle,
                size: 18,
                color: Color(0xFF1AB69C),
              ),
          ],
        ),
      ),
    );
  }
}

class _FarmerInfoCard extends StatelessWidget {
  final String name;
  final String mobile;
  final String address;
  final int pendingAmount; // NEW

  const _FarmerInfoCard({
    required this.name,
    required this.mobile,
    required this.address,
    required this.pendingAmount,
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
            color: const Color.fromARGB(
              255,
              180,
              64,
              64,
            ).withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.agriculture, size: 28, color: Color(0xFF1AB69C)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),

                if (mobile.isNotEmpty)
                  Row(
                    children: [
                      Icon(Icons.phone, size: 16, color: Color(0xFF1AB69C)),
                      const SizedBox(width: 6),
                      Text(
                        mobile,
                        style: TextStyle(fontSize: 13, color: Colors.grey[700]),
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
                        final fmt = NumberFormat.currency(
                          locale: 'en_IN',
                          symbol: '₹',
                          decimalDigits: 2,
                        );
                        final pending = pendingAmount;
                        final noDue = pending <= 0.0;
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

class _FarmerLite {
  final String? id;
  final String? name;
  final String? mobile;
  final String? location;

  _FarmerLite({this.id, this.name, this.mobile, this.location});
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

class SpeciesSelector extends StatefulWidget {
  final String? initialValue;
  final ValueChanged<String?> onChanged;

  const SpeciesSelector({
    super.key,
    this.initialValue,
    required this.onChanged,
  });

  @override
  State<SpeciesSelector> createState() => _SpeciesSelectorState();
}

class _SpeciesSelectorState extends State<SpeciesSelector> {
  final MenuController _menuCtrl = MenuController();
  final TextEditingController _ctrl = TextEditingController();
  String? _species;

  @override
  void initState() {
    super.initState();
    _species = widget.initialValue;
    _ctrl.text = _species ?? '';
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _selectSpecies(String value) {
    setState(() {
      _species = value;
      _ctrl.text = value;
    });
    widget.onChanged(value);
    _menuCtrl.close();
  }

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      controller: _menuCtrl,
      childFocusNode: FocusNode(),
      builder: (context, controller, _) {
        return TextFormField(
          readOnly: true,
          controller: _ctrl,
          decoration: InputDecoration(
            labelText: 'Culture Species',
            hintText: 'Select species',
            filled: true,
            fillColor: Colors.grey.withValues(alpha: 0.06),
            suffixIcon: const Icon(Icons.keyboard_arrow_down),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 14,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
            ),
            focusedBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(10)),
              borderSide: BorderSide(color: Color(0xFF1AB69C), width: 1.2),
            ),
          ),
          onTap: () =>
              controller.isOpen ? controller.close() : controller.open(),
          validator: (_) => _species == null ? 'Species is required' : null,
        );
      },
      menuChildren: [
        Builder(
          builder: (context) {
            final fieldWidth =
                (context.findRenderObject() as RenderBox?)?.size.width ?? 250;
            return Material(
              elevation: 6,
              borderRadius: BorderRadius.circular(12),
              color: Colors.white,
              child: SizedBox(
                width: fieldWidth, // match TextFormField width
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [_menuItem('Shrimp'), _menuItem('Fish')],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _menuItem(String value) {
    final selected = value == _species;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _selectSpecies(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        color: selected
            ? const Color(0xFF1AB69C).withValues(alpha: 0.12)
            : null,
        child: Row(
          children: [
            Icon(
              value == 'Shrimp' ? Icons.set_meal : Icons.phishing,
              size: 20,
              color: selected ? const Color(0xFF1AB69C) : Colors.grey.shade700,
            ),
            const SizedBox(width: 10),
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: selected ? const Color(0xFF1AB69C) : Colors.black87,
              ),
            ),
            const Spacer(),
            if (selected)
              const Icon(
                Icons.check_circle,
                size: 18,
                color: Color(0xFF1AB69C),
              ),
          ],
        ),
      ),
    );
  }
}

class _PondForm {
  final GlobalKey speciesKey = GlobalKey();
  final MenuController menuCtrl = MenuController();

  String? species;

  final pondName = TextEditingController();
  final size = TextEditingController();

  final stockingPL = TextEditingController();
  final doc = TextEditingController();
  final feed = TextEditingController();
  final count = TextEditingController();
  final avgWeight = TextEditingController();

  final salinity = TextEditingController();
  final ph = TextEditingController();
  final alkalinity = TextEditingController();
  final ammonia = TextEditingController();
  final nitrite = TextEditingController();
  final dissolvedOxygen = TextEditingController();

  final vibrios = TextEditingController();

  Map<String, dynamic> toJson() {
    double d(String v) => double.tryParse(v.trim()) ?? 0.0;
    int i(String v) => int.tryParse(v.trim()) ?? 0;

    return {
      "pondName": pondName.text.trim(),
      "culturedArea": d(size.text),
      "culturedSpecies": species,
      "physicalReadings": [
        {
          "stockingPL": i(stockingPL.text),
          "doc": i(doc.text),
          "feedIntakePerDay": d(feed.text),
          "count": i(count.text),
          "avgWeight": species == 'Fish' ? d(avgWeight.text) : null,
        },
      ],
      "chemicalReadings": [
        {
          "salinity": d(salinity.text),
          "ph": d(ph.text),
          "alkalinity": i(alkalinity.text),
          "ammonia": d(ammonia.text),
          "nitrite": d(nitrite.text),
          "dissolvedOxygen": d(dissolvedOxygen.text),
        },
      ],
      "diseaseReadings": vibrios.text.trim().isEmpty
          ? []
          : [
              {"vibrios": int.tryParse(vibrios.text.trim()) ?? 0},
            ],
    };
  }

  void dispose() {
    pondName.dispose();
    size.dispose();
    stockingPL.dispose();
    doc.dispose();
    feed.dispose();
    count.dispose();
    avgWeight.dispose();
    salinity.dispose();
    ph.dispose();
    alkalinity.dispose();
    ammonia.dispose();
    nitrite.dispose();
    dissolvedOxygen.dispose();
    vibrios.dispose();
  }
}
class QueryData {
  final String remarks;
  final List<Map<String, dynamic>> ponds;
  final List<QueuedFile> files;

  QueryData({
    required this.remarks,
    required this.ponds,
    required this.files,
  });
}