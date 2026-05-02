// // ignore_for_file: unrelated_type_equality_checks, use_build_context_synchronously, deprecated_member_use

// import 'dart:convert';
// import 'dart:io';
// import 'dart:async';
// import 'package:image/image.dart' as img;
// import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
// import 'package:image_picker/image_picker.dart';
// import 'package:connectivity_plus/connectivity_plus.dart';
// import 'package:http/http.dart' as http;
// import 'package:app_settings/app_settings.dart';
// import 'package:shared_preferences/shared_preferences.dart';
// import 'package:FieldService_app/Screens/tickets.dart';
// import 'package:geolocator/geolocator.dart';
// import 'package:geocoding/geocoding.dart';
// import 'package:http_parser/http_parser.dart';
// import 'package:FieldService_app/config.dart';

// /// ======= THEME & UI HELPERS =======

// const appGreen = Color(0xFF2E7D32);

// BoxDecoration cardDecoration() => BoxDecoration(
//   color: Colors.white,
//   borderRadius: BorderRadius.circular(16),
//   boxShadow: [
//     BoxShadow(
//       color: Colors.black.withValues(alpha: 0.05),
//       blurRadius: 8,
//       offset: const Offset(0, 2),
//     ),
//   ],
// );

// InputDecoration inputDecoration(String label, {IconData? icon}) =>
//     InputDecoration(
//       labelText: label,
//       labelStyle: const TextStyle(
//         color: Colors.black,
//         fontWeight: FontWeight.w500,
//       ),
//       prefixIcon: icon != null ? Icon(icon, color: appGreen) : null,
//       filled: true,
//       fillColor: Colors.white,
//       enabledBorder: OutlineInputBorder(
//         borderRadius: BorderRadius.circular(16),
//         borderSide: BorderSide(color: Colors.black12.withAlpha(40)),
//       ),
//       focusedBorder: OutlineInputBorder(
//         borderRadius: BorderRadius.circular(16),
//         borderSide: const BorderSide(color: appGreen, width: 2),
//       ),
//       contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
//     );

// extension SnackX on BuildContext {
//   void showSnack(
//     String msg, {
//     Color color = appGreen,
//     Duration duration = const Duration(seconds: 2),
//   }) {
//     ScaffoldMessenger.of(this).showSnackBar(
//       SnackBar(content: Text(msg), backgroundColor: color, duration: duration),
//     );
//   }
// }

// /// ======= DIALOGS =======

// Future<void> showNoInternetDialog(BuildContext context) async {
//   return showDialog(
//     context: context,
//     barrierDismissible: false,
//     builder: (BuildContext context) {
//       return Dialog(
//         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
//         insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
//         child: Container(
//           padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
//           decoration: BoxDecoration(
//             color: Colors.white,
//             borderRadius: BorderRadius.circular(20),
//             boxShadow: [
//               BoxShadow(
//                 color: Colors.black.withValues(alpha: 0.1),
//                 blurRadius: 20,
//                 offset: const Offset(0, 8),
//               ),
//             ],
//           ),
//           child: Column(
//             mainAxisSize: MainAxisSize.min,
//             children: [
//               const Icon(
//                 Icons.signal_cellular_connected_no_internet_4_bar,
//                 size: 50,
//                 color: Colors.redAccent,
//               ),
//               const SizedBox(height: 16),
//               const Text(
//                 "No Internet Connection",
//                 textAlign: TextAlign.center,
//                 style: TextStyle(
//                   fontSize: 20,
//                   fontWeight: FontWeight.w600,
//                   color: Colors.black87,
//                 ),
//               ),
//               const SizedBox(height: 12),
//               const Text(
//                 "You are offline. Please enable mobile data or Wi-Fi to continue.",
//                 textAlign: TextAlign.center,
//                 style: TextStyle(
//                   fontSize: 15,
//                   color: Colors.black54,
//                   height: 1.4,
//                 ),
//               ),
//               const SizedBox(height: 24),
//               Row(
//                 children: [
//                   Expanded(
//                     child: TextButton(
//                       onPressed: () => Navigator.of(context).pop(),
//                       style: TextButton.styleFrom(
//                         padding: const EdgeInsets.symmetric(vertical: 14),
//                         shape: RoundedRectangleBorder(
//                           borderRadius: BorderRadius.circular(14),
//                         ),
//                         backgroundColor: Colors.grey.shade200,
//                       ),
//                       child: const Text(
//                         "OK",
//                         style: TextStyle(
//                           fontSize: 16,
//                           color: Colors.black87,
//                           fontWeight: FontWeight.w600,
//                         ),
//                       ),
//                     ),
//                   ),
//                   const SizedBox(width: 12),
//                   Expanded(
//                     child: TextButton(
//                       onPressed: () {
//                         Navigator.of(context).pop();
//                         AppSettings.openAppSettings(type: AppSettingsType.wifi);
//                       },
//                       style: TextButton.styleFrom(
//                         padding: const EdgeInsets.symmetric(vertical: 14),
//                         shape: RoundedRectangleBorder(
//                           borderRadius: BorderRadius.circular(14),
//                         ),
//                         backgroundColor: appGreen,
//                       ),
//                       child: const Text(
//                         "Settings",
//                         style: TextStyle(
//                           fontSize: 16,
//                           color: Colors.white,
//                           fontWeight: FontWeight.w600,
//                         ),
//                       ),
//                     ),
//                   ),
//                 ],
//               ),
//             ],
//           ),
//         ),
//       );
//     },
//   );
// }

// /// ======= SERVICES (INTERNET & LOCATION) =======

// class ConnectivityService {
//   static Future<bool> hasInternet() async {
//     final connectivityResult = await Connectivity().checkConnectivity();
//     if (connectivityResult == ConnectivityResult.none) return false;
//     try {
//       final r = await http
//           .get(Uri.parse('https://www.google.com'))
//           .timeout(const Duration(seconds: 5));
//       return r.statusCode == 200;
//     } catch (_) {
//       return false;
//     }
//   }
// }

// class LocationService {
//   static Future<(Position, String?)?> getPositionAndArea() async {
//     final permission = await Geolocator.requestPermission();
//     if (permission == LocationPermission.denied ||
//         permission == LocationPermission.deniedForever) {
//       return null;
//     }

//     final pos = await Geolocator.getCurrentPosition(
//       desiredAccuracy: LocationAccuracy.high,
//     );
//     try {
//       final placemarks = await placemarkFromCoordinates(
//         pos.latitude,
//         pos.longitude,
//       );
//       if (placemarks.isNotEmpty) {
//         final p = placemarks.first;
//         final parts = <String>[];
//         if ((p.subLocality ?? '').isNotEmpty) parts.add(p.subLocality!);
//         if ((p.locality ?? '').isNotEmpty) parts.add(p.locality!);
//         if ((p.subAdministrativeArea ?? '').isNotEmpty) {
//           parts.add(p.subAdministrativeArea!);
//         }
//         if ((p.administrativeArea ?? '').isNotEmpty) {
//           parts.add(p.administrativeArea!);
//         }
//         if ((p.country ?? '').isNotEmpty) parts.add(p.country!);
//         return (
//           pos,
//           parts.isNotEmpty ? parts.join(', ') : 'Location available',
//         );
//       }
//     } catch (_) {}
//     return (pos, 'Location available');
//   }
// }

// /// ======= IMAGE MODEL =======

// class ImageWithMetadata {
//   final XFile file;
//   final double? latitude;
//   final double? longitude;
//   final String? areaName;
//   final DateTime dateTime;

//   ImageWithMetadata({
//     required this.file,
//     this.latitude,
//     this.longitude,
//     this.areaName,
//     required this.dateTime,
//   });
// }

// /// ======= IMAGE PICKER STRIP WIDGET =======

// class ImagePickerStrip extends StatelessWidget {
//   final List<ImageWithMetadata> images;
//   final VoidCallback onAdd;
//   final void Function(int index) onRemove;
//   final void Function(ImageWithMetadata data) onTap;

//   const ImagePickerStrip({
//     super.key,
//     required this.images,
//     required this.onAdd,
//     required this.onRemove,
//     required this.onTap,
//   });

//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       decoration: cardDecoration(),
//       padding: const EdgeInsets.all(16),
//       child: SizedBox(
//         height: 120,
//         child: ListView.separated(
//           scrollDirection: Axis.horizontal,
//           itemCount: images.length + 1,
//           separatorBuilder: (_, __) => const SizedBox(width: 12),
//           itemBuilder: (context, i) {
//             if (i == images.length) {
//               return InkWell(
//                 onTap: onAdd,
//                 child: Container(
//                   width: 100,
//                   decoration: BoxDecoration(
//                     gradient: const LinearGradient(
//                       colors: [Color(0xFFE8F5E8), Color(0xFFF1F8E9)],
//                       begin: Alignment.topLeft,
//                       end: Alignment.bottomRight,
//                     ),
//                     borderRadius: BorderRadius.circular(16),
//                     border: Border.all(color: appGreen, width: 2),
//                   ),
//                   child: const Column(
//                     mainAxisAlignment: MainAxisAlignment.center,
//                     children: [
//                       Icon(Icons.camera_alt, size: 32, color: appGreen),
//                       SizedBox(height: 4),
//                       Text(
//                         'Add Photo',
//                         style: TextStyle(
//                           fontSize: 12,
//                           fontWeight: FontWeight.w600,
//                           color: appGreen,
//                         ),
//                       ),
//                     ],
//                   ),
//                 ),
//               );
//             }
//             final img = images[i];
//             return InkWell(
//               onTap: () => onTap(img),
//               child: Container(
//                 width: 100,
//                 decoration: BoxDecoration(
//                   borderRadius: BorderRadius.circular(16),
//                   boxShadow: [
//                     BoxShadow(
//                       color: Colors.black.withValues(alpha: 0.2),
//                       blurRadius: 4,
//                       offset: const Offset(0, 2),
//                     ),
//                   ],
//                 ),
//                 child: ClipRRect(
//                   borderRadius: BorderRadius.circular(16),
//                   child: Stack(
//                     children: [
//                       Image.file(
//                         File(img.file.path),
//                         width: 100,
//                         height: 120,
//                         fit: BoxFit.cover,
//                       ),
//                       if (img.latitude != null && img.longitude != null)
//                         const Positioned(
//                           top: 4,
//                           left: 4,
//                           child: CircleAvatar(
//                             radius: 10,
//                             backgroundColor: appGreen,
//                             child: Icon(
//                               Icons.location_on,
//                               size: 12,
//                               color: Colors.white,
//                             ),
//                           ),
//                         ),
//                       Positioned(
//                         top: 4,
//                         right: 4,
//                         child: InkWell(
//                           onTap: () => onRemove(i),
//                           child: const CircleAvatar(
//                             radius: 12,
//                             backgroundColor: Colors.red,
//                             child: Icon(
//                               Icons.close,
//                               size: 14,
//                               color: Colors.white,
//                             ),
//                           ),
//                         ),
//                       ),
//                     ],
//                   ),
//                 ),
//               ),
//             );
//           },
//         ),
//       ),
//     );
//   }
// }

// /// ======= MAIN SCREEN =======

// class FarmerTicketScreen extends StatefulWidget {
//   const FarmerTicketScreen({super.key});

//   @override
//   State<FarmerTicketScreen> createState() => _FarmerTicketScreenState();
// }

// class _FarmerTicketScreenState extends State<FarmerTicketScreen> {
//   final _formKey = GlobalKey<FormState>();

//   final TextEditingController _farmerNameController = TextEditingController(
//     text: '',
//   );
//   final TextEditingController _mobileNumberController = TextEditingController(
//     text: '',
//   );
//   final TextEditingController _farmerAddressController =
//       TextEditingController();

//   String? _selectedArea; // issue type
//   String? _selectedWaterType; // water type

//   final ImagePicker _picker = ImagePicker();
//   final List<ImageWithMetadata> _pickedImages = [];

//   // Location related variables
//   Position? _currentPosition;
//   String? _currentAreaName;
//   bool _isGettingLocation = false;

//   void safeSetState(VoidCallback fn) {
//     if (!mounted) return;
//     setState(fn);
//   }

//   @override
//   void initState() {
//     super.initState();
//     _getCurrentLocationAndTime();
//   }

//   @override
//   void dispose() {
//     _farmerNameController.dispose();
//     _mobileNumberController.dispose();
//     _farmerAddressController.dispose();
//     super.dispose();
//   }

//   Future<void> _getCurrentLocationAndTime() async {
//     try {
//       final loc = await LocationService.getPositionAndArea();
//       if (loc == null) return;
//       final (pos, area) = loc;
//       safeSetState(() {
//         _currentPosition = pos;
//         _currentAreaName = area;
//         // ✅ Auto-fill address text if empty
//         if ((_farmerAddressController.text).trim().isEmpty &&
//             (area != null && area.trim().isNotEmpty)) {
//           _farmerAddressController.text = area;
//         }
//       });
//     } catch (e) {
//       debugPrint('Error getting location: $e');
//     }
//   }

//   Future<void> _pickImage(ImageSource source) async {
//     try {
//       final XFile? pickedFile = await _picker.pickImage(
//         source: source,
//         imageQuality: 70,
//       );
//       if (pickedFile == null) return;

//       // Use latest known location; fetch if null
//       Position? imagePosition = _currentPosition;
//       String? imageAreaName = _currentAreaName;
//       final imageDateTime = DateTime.now();

//       if (imagePosition == null) {
//         final loc = await LocationService.getPositionAndArea();
//         if (loc != null) {
//           imagePosition = loc.$1;
//           imageAreaName = loc.$2;
//         }
//       }

//       safeSetState(() {
//         _pickedImages.add(
//           ImageWithMetadata(
//             file: pickedFile,
//             latitude: imagePosition?.latitude,
//             longitude: imagePosition?.longitude,
//             areaName: imageAreaName,
//             dateTime: imageDateTime,
//           ),
//         );
//       });

//       if (!mounted) return;
//       var locationInfo = '';
//       if (imagePosition != null) {
//         locationInfo =
//             '\n📍 Location: ${imagePosition.latitude.toStringAsFixed(6)}, ${imagePosition.longitude.toStringAsFixed(6)}';
//         if (imageAreaName != null) {
//           locationInfo += '\n🏘️ Area: $imageAreaName';
//         }
//       }
//       context.showSnack('Photo captured successfully!$locationInfo');
//     } catch (e) {
//       if (!mounted) return;
//       context.showSnack('Error picking image: $e', color: Colors.red);
//     }
//   }

//   void _showPickOptionsDialog() {
//     showDialog(
//       context: context,
//       builder: (context) => AlertDialog(
//         title: const Text('Select Image Source'),
//         content: Column(
//           mainAxisSize: MainAxisSize.min,
//           children: [
//             ListTile(
//               leading: const Icon(Icons.camera_alt),
//               title: const Text('Open Camera'),
//               onTap: () {
//                 Navigator.pop(context);
//                 _pickImage(ImageSource.camera);
//               },
//             ),
//             // ListTile(
//             //   leading: const Icon(Icons.photo_library),
//             //   title: const Text('Gallery'),
//             //   onTap: () {
//             //     Navigator.pop(context);
//             //     _pickImage(ImageSource.gallery);
//             //   },
//             // ),
//           ],
//         ),
//       ),
//     );
//   }

//   Future<void> _generateTicket() async {
//     // Connectivity check
//     final hasInternet = await ConnectivityService.hasInternet();
//     if (!hasInternet) {
//       if (!mounted) return;
//       await showNoInternetDialog(context);
//       return;
//     }

//     if ((_farmerAddressController.text).trim().isEmpty &&
//         _currentAreaName != null) {
//       _farmerAddressController.text = _currentAreaName!;
//     }

//     if (!_formKey.currentState!.validate() ||
//         _selectedArea == null ||
//         _selectedWaterType == null ||
//         _currentPosition == null) {
//       if (!mounted) return;
//       context.showSnack('Please fill all required fields', color: Colors.red);
//       return;
//     }
//     if (_pickedImages.isEmpty) {
//       if (!mounted) return;
//       context.showSnack('Please add at least one photo', color: Colors.red);
//       return;
//     }

//     // Loader
//     if (mounted) {
//       showDialog(
//         context: context,
//         barrierDismissible: false,
//         builder: (_) => const Center(
//           child: CircularProgressIndicator(
//             valueColor: AlwaysStoppedAnimation(appGreen),
//           ),
//         ),
//       );
//     }

//     try {
//       final prefs = await SharedPreferences.getInstance();
//       final tripId = prefs.getString("currentTripId");
//       final employeeId = prefs.getString("userId");
//       final companyId = prefs.getString("companyId");
//       final token = prefs.getString("token"); // ✅ unified key

//       // Use the Postman-success values to avoid enum mismatch
//       String issueTypeValue = _selectedArea!;
//       String waterTypeValue = _selectedWaterType!;
//       if (issueTypeValue.toLowerCase().contains('water')) {
//         issueTypeValue = 'Leakage';
//       }
//       if (waterTypeValue.toLowerCase().contains('fresh')) {
//         waterTypeValue = 'Drinking';
//       }

//       // Build location EXACTLY like Postman (JSON string)
//       final locJsonString = jsonEncode({
//         "longitude": _currentPosition!.longitude.toString(),
//         "latitude": _currentPosition!.latitude.toString(),
//       });

//       // ✅ Use AppConfig instead of hardcoded URL
//       final uri = AppConfig.u('/api/tickets/create-ticket');
//       final request = http.MultipartRequest("POST", uri);

//       if (token != null && token.isNotEmpty) {
//         request.headers["Authorization"] = "Bearer $token";
//       }

//       // Fields
//       request.fields['formerName'] = _farmerNameController.text.trim();
//       request.fields['mobileNumber'] = _mobileNumberController.text.trim();
//       request.fields['formerAddress'] = locJsonString;
//       request.fields['issueType'] = issueTypeValue;
//       request.fields['waterType'] = waterTypeValue;
//       request.fields['tripId'] = tripId ?? '';
//       request.fields['employeeId'] = employeeId ?? '';
//       request.fields['companyId'] = companyId ?? '';

//       // === FILES ===
//       for (final picked in _pickedImages) {
//         final pngBytes = await _forceToPngBytes(File(picked.file.path));
//         final filename = 'photo_${DateTime.now().millisecondsSinceEpoch}.png';

//         request.files.add(
//           http.MultipartFile.fromBytes(
//             'photos', // ✅ exact backend key
//             pngBytes,
//             filename: filename,
//             contentType: MediaType('image', 'png'),
//           ),
//         );
//         debugPrint("📸 Attached $filename (${pngBytes.length} bytes)");
//       }

//       // Send request
//       final streamed = await request.send().timeout(AppConfig.httpTimeout);
//       final response = await http.Response.fromStream(streamed);

//       // Debug
//       debugPrint("📡 Ticket API called: ${request.url}");
//       debugPrint("➡️ Headers: ${request.headers}");
//       debugPrint("➡️ Sent fields:");
//       request.fields.forEach((k, v) => debugPrint("   - $k: $v"));
//       debugPrint(
//         "➡️ Sent files: ${request.files.map((f) => '${f.field}::${f.filename}').toList()}",
//       );
//       debugPrint("⬅️ Response status: ${response.statusCode}");
//       debugPrint("⬅️ Response body: ${response.body}");

//       if (!mounted) return;
//       Navigator.of(context).pop(); // close loader

//       if (response.statusCode == 200 || response.statusCode == 201) {
//         context.showSnack("Ticket created successfully!");
//         Navigator.push(
//           context,
//           MaterialPageRoute(builder: (_) => const Tickets()),
//         );
//       } else {
//         context.showSnack("Error: ${response.body}", color: Colors.red);
//       }
//     } catch (e) {
//       if (!mounted) return;
//       Navigator.of(context).pop();
//       debugPrint("❌ Ticket API error: $e");
//       context.showSnack("Error: $e", color: Colors.red);
//     }
//   }

//   Future<Uint8List> _forceToPngBytes(File file) async {
//     final bytes = await file.readAsBytes();
//     final decoded = img.decodeImage(bytes);
//     if (decoded == null) {
//       throw Exception("Could not decode image: ${file.path}");
//     }
//     return Uint8List.fromList(img.encodePng(decoded)); // true PNG bytes
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: const Color(0xFFF5F5F5),
//       appBar: AppBar(
//         automaticallyImplyLeading: false, // 👈 disables back button
//         backgroundColor: const Color(0xFFF5F5F5),
//         elevation: 0,
//         // leading: IconButton(
//         //   icon: const Icon(Icons.arrow_back_ios, color: appGreen),
//         //   onPressed: () => Navigator.pop(context),
//         // ),
//         title: const Text(
//           'New Farmer Ticket',
//           style: TextStyle(
//             fontSize: 20,
//             fontWeight: FontWeight.bold,
//             color: Colors.black,
//           ),
//         ),
//         centerTitle: true,
//       ),
//       body: _buildFormView(),
//     );
//   }

//   Widget _buildFormView() {
//     return SingleChildScrollView(
//       physics: const BouncingScrollPhysics(),
//       padding: const EdgeInsets.all(20),
//       child: Form(
//         key: _formKey,
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             // Header Card
//             Container(
//               width: double.infinity,
//               padding: const EdgeInsets.all(20),
//               decoration: BoxDecoration(
//                 gradient: const LinearGradient(
//                   colors: [Color(0xFF96CD9E), Color(0xFF96CD9E)],
//                   begin: Alignment.topLeft,
//                   end: Alignment.bottomRight,
//                 ),
//                 borderRadius: BorderRadius.circular(16),
//                 boxShadow: [
//                   BoxShadow(
//                     color: Colors.green.withValues(alpha: 0.3),
//                     blurRadius: 10,
//                     offset: const Offset(0, 4),
//                   ),
//                 ],
//               ),
//               child: const Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   Text(
//                     'Create New Ticket',
//                     style: TextStyle(
//                       fontSize: 24,
//                       fontWeight: FontWeight.bold,
//                       color: Colors.black,
//                     ),
//                   ),
//                   SizedBox(height: 8),
//                   Text(
//                     'Fill in the details to generate a farmer support ticket',
//                     style: TextStyle(fontSize: 14, color: Colors.black),
//                   ),
//                 ],
//               ),
//             ),
//             const SizedBox(height: 24),

//             // Form Fields
//             Container(
//               decoration: cardDecoration(),
//               child: TextFormField(
//                 controller: _farmerNameController,
//                 decoration: inputDecoration('Farmer Name', icon: Icons.person),
//                 inputFormatters: [
//                   FilteringTextInputFormatter.allow(
//                     RegExp(r'[a-zA-Z\s]'),
//                   ), // Only letters and spaces
//                 ],
//                 validator: (v) {
//                   if (v == null || v.trim().isEmpty) {
//                     return 'Required';
//                   }

//                   // No need for regex here anymore since input is already restricted
//                   return null;
//                 },
//               ),
//             ),

//             const SizedBox(height: 16),
//             Container(
//               decoration: cardDecoration(),
//               child: TextFormField(
//                 controller: _mobileNumberController,
//                 keyboardType: TextInputType.phone,
//                 decoration: inputDecoration('Mobile Number', icon: Icons.phone),
//                 inputFormatters: [
//                   FilteringTextInputFormatter.digitsOnly, // Only digits
//                   LengthLimitingTextInputFormatter(10), // Max 10 digits
//                 ],
//                 validator: (v) {
//                   if (v == null || v.trim().isEmpty) return 'Required';

//                   if (v.trim().length != 10) {
//                     return 'Enter a valid 10-digit number';
//                   }

//                   return null;
//                 },
//               ),
//             ),
//             const SizedBox(height: 16),
//             Container(
//               decoration: cardDecoration(),
//               child: TextFormField(
//                 controller: _farmerAddressController,
//                 readOnly: true,
//                 decoration:
//                     inputDecoration(
//                       'Farmer Address',
//                       icon: Icons.location_on,
//                     ).copyWith(
//                       suffixIcon: _isGettingLocation
//                           ? Padding(
//                               padding: const EdgeInsets.all(12.0),
//                               child: SizedBox(
//                                 width: 18,
//                                 height: 18,
//                                 child: CircularProgressIndicator(
//                                   strokeWidth: 2,
//                                 ),
//                               ),
//                             )
//                           : IconButton(
//                               icon: Icon(Icons.my_location),
//                               tooltip: 'Get Location',
//                               onPressed: () async {
//                                 setState(() => _isGettingLocation = true);

//                                 final location =
//                                     await LocationService.getPositionAndArea();

//                                 setState(() => _isGettingLocation = false);

//                                 if (location != null && mounted) {
//                                   final (_, address) = location;
//                                   if (address != null) {
//                                     setState(() {
//                                       _farmerAddressController.text = address;
//                                     });
//                                   }
//                                 }
//                               },
//                             ),
//                     ),
//                 validator: (v) =>
//                     (v == null || v.trim().isEmpty) ? 'Required' : null,
//               ),
//             ),

//             const SizedBox(height: 16),

//             _buildFarmingIssuesSection(),
//             const SizedBox(height: 16),

//             // Image upload
//             _buildImageUploadSection(),
//             const SizedBox(height: 16),

//             //_buildProductsSection(),
//             //const SizedBox(height: 32),

//             // Submit Button
//             SizedBox(
//               width: double.infinity,
//               height: 56,
//               child: ElevatedButton(
//                 onPressed: _generateTicket,
//                 style: ElevatedButton.styleFrom(
//                   backgroundColor: const Color(0xFF4CAF50),
//                   foregroundColor: Colors.black,
//                   elevation: 4,
//                   shadowColor: Colors.green.withValues(alpha: 0.3),
//                   shape: RoundedRectangleBorder(
//                     borderRadius: BorderRadius.circular(16),
//                   ),
//                 ),
//                 child: const Row(
//                   mainAxisAlignment: MainAxisAlignment.center,
//                   children: [
//                     Icon(Icons.check_circle_outline, size: 24),
//                     SizedBox(width: 8),
//                     Text(
//                       'Generate Ticket',
//                       style: TextStyle(
//                         fontSize: 18,
//                         fontWeight: FontWeight.bold,
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//             ),
//             const SizedBox(height: 20),
//           ],
//         ),
//       ),
//     );
//   }

//   Widget _buildImageUploadSection() {
//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         const Text(
//           'Upload Images',
//           style: TextStyle(
//             fontSize: 18,
//             fontWeight: FontWeight.bold,
//             color: Colors.black,
//           ),
//         ),
//         const SizedBox(height: 12),
//         ImagePickerStrip(
//           images: _pickedImages,
//           onAdd: _showPickOptionsDialog,
//           onRemove: (i) => safeSetState(() => _pickedImages.removeAt(i)),
//           onTap: _showImageDetails,
//         ),
//       ],
//     );
//   }

//   Widget _buildFarmingIssuesSection() {
//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         const Text(
//           'Farming Issues',
//           style: TextStyle(
//             fontSize: 18,
//             fontWeight: FontWeight.bold,
//             color: appGreen,
//           ),
//         ),
//         const SizedBox(height: 12),

//         // Issue Type (values match API)
//         Container(
//           decoration: cardDecoration(),
//           child: DropdownButtonFormField<String>(
//             value: _selectedArea,
//             hint: const Text('Select Issue Type'),
//             isExpanded: true,
//             decoration: inputDecoration('Issue Type', icon: Icons.agriculture),
//             items: const [
//               DropdownMenuItem(value: 'No Water', child: Text('No Water')),
//               DropdownMenuItem(value: 'Leakage', child: Text('Leakage Issue')),
//               DropdownMenuItem(
//                 value: 'Blocked Pipe',
//                 child: Text('Blocked Pipe Problem'),
//               ),
//             ],
//             validator: (v) => v == null ? 'Required' : null,
//             onChanged: (val) => safeSetState(() => _selectedArea = val),
//           ),
//         ),

//         const SizedBox(height: 16),

//         // Water Type (values match API)
//         Container(
//           decoration: cardDecoration(),
//           child: DropdownButtonFormField<String>(
//             value: _selectedWaterType,
//             hint: const Text('Select Water Type'),
//             isExpanded: true,
//             decoration: inputDecoration('Water Type', icon: Icons.water_drop),
//             items: const [
//               DropdownMenuItem(
//                 value: 'Drinking',
//                 child: Text('Drinking Water'),
//               ),
//               DropdownMenuItem(
//                 value: 'Irrigation',
//                 child: Text('Irrigation Water'),
//               ),
//               DropdownMenuItem(value: 'Sewage', child: Text('Sewage Water')),
//             ],
//             validator: (v) => v == null ? 'Required' : null,
//             onChanged: (val) => safeSetState(() => _selectedWaterType = val),
//           ),
//         ),
//       ],
//     );
//   }

//   // Widget _buildProductsSection() {
//   //   return GestureDetector(
//   //     onTap: () {
//   //       context.showSnack('Products selection feature coming soon!');
//   //     },
//   //     child: Container(
//   //       padding: const EdgeInsets.all(20),
//   //       decoration: BoxDecoration(
//   //         gradient: const LinearGradient(
//   //           colors: [Color(0xFFE8F5E8), Color(0xFFF1F8E9)],
//   //           begin: Alignment.topLeft,
//   //           end: Alignment.bottomRight,
//   //         ),
//   //         borderRadius: BorderRadius.circular(16),
//   //         border: Border.all(color: appGreen, width: 2),
//   //         boxShadow: [
//   //           BoxShadow(
//   //             color: Colors.green.withValues(alpha: 0.1),
//   //             blurRadius: 8,
//   //             offset: const Offset(0, 2),
//   //           ),
//   //         ],
//   //       ),
//   //       child: const Row(
//   //         children: [
//   //           Icon(Icons.add_circle_outline, color: appGreen, size: 28),
//   //           SizedBox(width: 12),
//   //           Expanded(
//   //             child: Column(
//   //               crossAxisAlignment: CrossAxisAlignment.start,
//   //               children: [
//   //                 Text(
//   //                   'Add Products',
//   //                   style: TextStyle(
//   //                     color: appGreen,
//   //                     fontSize: 18,
//   //                     fontWeight: FontWeight.bold,
//   //                   ),
//   //                 ),
//   //                 SizedBox(height: 4),
//   //                 Text(
//   //                   'Select products for this ticket',
//   //                   style: TextStyle(color: appGreen, fontSize: 14),
//   //                 ),
//   //               ],
//   //             ),
//   //           ),
//   //           Icon(Icons.arrow_forward_ios, color: appGreen, size: 20),
//   //         ],
//   //       ),
//   //     ),
//   //   );
//   // }

//   String _formatDateTime(DateTime dateTime) {
//     return '${dateTime.day}/${dateTime.month}/${dateTime.year} '
//         '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
//   }

//   void _showImageDetails(ImageWithMetadata imageData) {
//     showDialog(
//       context: context,
//       builder: (context) => AlertDialog(
//         title: const Text('Image Details'),
//         content: SingleChildScrollView(
//           child: Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             mainAxisSize: MainAxisSize.min,
//             children: [
//               Container(
//                 height: 200,
//                 width: double.infinity,
//                 decoration: BoxDecoration(
//                   borderRadius: BorderRadius.circular(8),
//                   image: DecorationImage(
//                     image: FileImage(File(imageData.file.path)),
//                     fit: BoxFit.cover,
//                   ),
//                 ),
//               ),
//               const SizedBox(height: 16),
//               if (imageData.latitude != null &&
//                   imageData.longitude != null) ...[
//                 _buildDetailRow(
//                   'Latitude',
//                   '${imageData.latitude!.toStringAsFixed(6)}°',
//                 ),
//                 _buildDetailRow(
//                   'Longitude',
//                   '${imageData.longitude!.toStringAsFixed(6)}°',
//                 ),
//               ],
//               if (imageData.areaName != null)
//                 _buildDetailRow('Area', imageData.areaName!),
//               _buildDetailRow(
//                 'Date & Time',
//                 _formatDateTime(imageData.dateTime),
//               ),
//             ],
//           ),
//         ),
//         actions: [
//           TextButton(
//             onPressed: () => Navigator.pop(context),
//             child: const Text('Close'),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildDetailRow(String label, String value) {
//     return Padding(
//       padding: const EdgeInsets.symmetric(vertical: 4),
//       child: Row(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           SizedBox(
//             width: 80,
//             child: Text(
//               '$label:',
//               style: const TextStyle(
//                 fontWeight: FontWeight.bold,
//                 color: appGreen,
//               ),
//             ),
//           ),
//           Expanded(
//             child: Text(value, style: const TextStyle(color: Colors.black87)),
//           ),
//         ],
//       ),
//     );
//   }
// }
