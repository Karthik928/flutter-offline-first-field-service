// import 'package:flutter/material.dart';
// import '../services/connectivity_service.dart';

// class ConnectivityWrapper extends StatefulWidget {
//   final Widget child;
//   final bool checkOnInit;

//   const ConnectivityWrapper({
//     super.key,
//     required this.child,
//     this.checkOnInit = true,
//   });

//   @override
//   State<ConnectivityWrapper> createState() => _ConnectivityWrapperState();
// }

// class _ConnectivityWrapperState extends State<ConnectivityWrapper> {
//   final ConnectivityService _connectivityService = ConnectivityService();

//   @override
//   void initState() {
//     super.initState();
//     if (widget.checkOnInit) {
//       WidgetsBinding.instance.addPostFrameCallback((_) {
//         _checkConnectivity();
//       });
//     }
//   }

//   void _checkConnectivity() {
//     if (!_connectivityService.isConnected) {
//       _connectivityService.showNoInternetDialog(context);
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     return widget.child;
//   }
// }
