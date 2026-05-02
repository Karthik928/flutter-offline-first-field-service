// import 'package:flutter/material.dart';

// class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
//   final String title;
//   final VoidCallback? onBack;
//   final VoidCallback? onSettings;
//   final double height;

//   const CustomAppBar({
//     super.key,
//     required this.title,
//     this.onBack,
//     this.onSettings,
//     this.height = kToolbarHeight,
//   });

//   @override
//   Size get preferredSize => Size.fromHeight(height);

//   @override
//   Widget build(BuildContext context) {
//     return AppBar(
//       automaticallyImplyLeading: false,
//       backgroundColor: const Color(0xFF96CD9E),
//       elevation: 0,
//       toolbarHeight: height,
//       centerTitle: true,
//       shape: const RoundedRectangleBorder(
//         borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
//       ),
//       // leading: IconButton(
//       //   onPressed: onBack,
//       //   icon: const Icon(
//       //     Icons.arrow_back,
//       //     color: Colors.black87,
//       //     size: 24,
//       //   ),
//       // ),
//       title: Text(
//         title,
//         style: const TextStyle(
//           fontSize: 20,
//           fontWeight: FontWeight.bold,
//           color: Colors.black87,
//         ),
//       ),
//       // actions: [
//       //   IconButton(
//       //     onPressed: onSettings,
//       //     icon: const Icon(
//       //       Icons.settings,
//       //       color: Colors.black87,
//       //       size: 24,
//       //     ),
//       //   ),
//       // ],
//     );
//   }
// }


