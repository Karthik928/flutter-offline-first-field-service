// import 'package:flutter/material.dart';

// /// A static "Onboard New Dealer" screen matching the provided design.
// ///
// /// This screen is built like a modal dialog and mirrors the screenshot.
// class DealerOnboardScreen extends StatefulWidget {
//   const DealerOnboardScreen({super.key});

//   @override
//   State<DealerOnboardScreen> createState() => _DealerOnboardScreenState();
// }

// class _DealerOnboardScreenState extends State<DealerOnboardScreen> {
//   final _shopController = TextEditingController();
//   final _locationController = TextEditingController();
//   final _contactController = TextEditingController(text: '+91 00000 00000');

//   String _owner = 'Self (Manager)';
//   final _owners = const [
//     'Self (Manager)',
//     'Rajesh Kumar',
//     'Anil Varma',
//     'Suresh G.',
//   ];

//   @override
//   void dispose() {
//     _shopController.dispose();
//     _locationController.dispose();
//     _contactController.dispose();
//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: const Color(0x99000000),
//       body: SafeArea(
//         child: Center(
//           child: Padding(
//             padding: const EdgeInsets.symmetric(horizontal: 16),
//             child: Container(
//               constraints: const BoxConstraints(maxWidth: 420),
//               decoration: BoxDecoration(
//                 color: const Color(0xFFF2F6F3),
//                 borderRadius: BorderRadius.circular(18),
//                 boxShadow: [
//                   BoxShadow(
//                     color: Colors.black.withValues(alpha: 0.16),
//                     blurRadius: 24,
//                     offset: const Offset(0, 10),
//                   ),
//                 ],
//               ),
//               padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
//               child: Column(
//                 mainAxisSize: MainAxisSize.min,
//                 children: [
//                   Row(
//                     children: [
//                       const Expanded(
//                         child: Text(
//                           'Onboard New Dealer',
//                           style: TextStyle(
//                             fontSize: 18,
//                             fontWeight: FontWeight.bold,
//                             color: Colors.black87,
//                           ),
//                         ),
//                       ),
//                       InkWell(
//                         borderRadius: BorderRadius.circular(12),
//                         onTap: () => Navigator.of(context).maybePop(),
//                         child: const Padding(
//                           padding: EdgeInsets.all(6),
//                           child: Icon(
//                             Icons.close,
//                             size: 20,
//                             color: Colors.black54,
//                           ),
//                         ),
//                       ),
//                     ],
//                   ),
//                   const SizedBox(height: 14),
//                   _buildTextField(
//                     label: 'Shop Name',
//                     hint: 'Enter shop name',
//                     controller: _shopController,
//                   ),
//                   const SizedBox(height: 12),
//                   _buildTextField(
//                     label: 'Location',
//                     hint: 'Enter location',
//                     controller: _locationController,
//                   ),
//                   const SizedBox(height: 12),
//                   _buildTextField(
//                     label: 'Contact Number',
//                     hint: '+91 00000 00000',
//                     controller: _contactController,
//                     keyboardType: TextInputType.phone,
//                   ),
//                   const SizedBox(height: 12),
//                   _buildDropdownField(
//                     label: 'Assign Owner',
//                     value: _owner,
//                     options: _owners,
//                     onChanged: (value) => setState(() {
//                       _owner = value;
//                     }),
//                   ),
//                   const SizedBox(height: 18),
//                   SizedBox(
//                     width: double.infinity,
//                     child: ElevatedButton(
//                       style: ElevatedButton.styleFrom(
//                         backgroundColor: const Color(0xFF2E7D32),
//                         padding: const EdgeInsets.symmetric(vertical: 14),
//                         shape: RoundedRectangleBorder(
//                           borderRadius: BorderRadius.circular(12),
//                         ),
//                       ),
//                       onPressed: () {},
//                       child: const Text(
//                         'Confirm Onboarding',
//                         style: TextStyle(
//                           fontSize: 14,
//                           fontWeight: FontWeight.w600,
//                         ),
//                       ),
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//           ),
//         ),
//       ),
//     );
//   }

//   Widget _buildTextField({
//     required String label,
//     required String hint,
//     required TextEditingController controller,
//     TextInputType keyboardType = TextInputType.text,
//   }) {
//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         Text(
//           label,
//           style: const TextStyle(
//             fontSize: 12,
//             fontWeight: FontWeight.w700,
//             color: Colors.black54,
//           ),
//         ),
//         const SizedBox(height: 6),
//         TextField(
//           controller: controller,
//           keyboardType: keyboardType,
//           decoration: InputDecoration(
//             hintText: hint,
//             filled: true,
//             fillColor: Colors.white,
//             contentPadding: const EdgeInsets.symmetric(
//               horizontal: 14,
//               vertical: 12,
//             ),
//             enabledBorder: OutlineInputBorder(
//               borderRadius: BorderRadius.circular(12),
//               borderSide: const BorderSide(color: Color(0xFFB9D4C0)),
//             ),
//             focusedBorder: OutlineInputBorder(
//               borderRadius: BorderRadius.circular(12),
//               borderSide: const BorderSide(color: Color(0xFF2E7D32)),
//             ),
//           ),
//         ),
//       ],
//     );
//   }

//   Widget _buildDropdownField({
//     required String label,
//     required String value,
//     required List<String> options,
//     required ValueChanged<String> onChanged,
//   }) {
//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         Text(
//           label,
//           style: const TextStyle(
//             fontSize: 12,
//             fontWeight: FontWeight.w700,
//             color: Colors.black54,
//           ),
//         ),
//         const SizedBox(height: 6),
//         Container(
//           padding: const EdgeInsets.symmetric(horizontal: 14),
//           decoration: BoxDecoration(
//             color: Colors.white,
//             borderRadius: BorderRadius.circular(12),
//             border: Border.all(color: const Color(0xFFB9D4C0)),
//           ),
//           child: DropdownButtonHideUnderline(
//             child: DropdownButton<String>(
//               value: value,
//               isExpanded: true,
//               icon: const Icon(
//                 Icons.keyboard_arrow_down,
//                 color: Colors.black45,
//               ),
//               items: options
//                   .map(
//                     (option) => DropdownMenuItem<String>(
//                       value: option,
//                       child: Text(option, style: const TextStyle(fontSize: 13)),
//                     ),
//                   )
//                   .toList(),
//               onChanged: (newValue) {
//                 if (newValue != null) onChanged(newValue);
//               },
//             ),
//           ),
//         ),
//       ],
//     );
//   }
// }
