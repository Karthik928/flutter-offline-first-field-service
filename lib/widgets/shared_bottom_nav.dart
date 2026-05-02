import 'package:flutter/material.dart';
//import 'package:connectivity_plus/connectivity_plus.dart';
//import 'package:app_settings/app_settings.dart';

enum MenuState {
  homedashboard,
  map,
  notification,
  tripsScreen,
  productsScreen,
  dealersScreen,
}

class BottomNavbar extends StatefulWidget {
  final MenuState selectedMenu;
  final ValueChanged<MenuState> onItemSelected;
  final int unreadCount;

  const BottomNavbar({
    super.key,
    required this.selectedMenu,
    required this.onItemSelected,
    this.unreadCount = 0,
  });

  @override
  State<BottomNavbar> createState() => _BottomNavbarState();
}

class _BottomNavbarState extends State<BottomNavbar> {
  // Future<bool> _hasInternet() async {
  //   final connectivityResult = await Connectivity().checkConnectivity();
  //   if (connectivityResult.contains(ConnectivityResult.none)) {
  //     return false;
  //   }
  //   return true;
  // }

  // Future<void> _showNoInternetDialog() async {
  //   showDialog(
  //     context: context,
  //     barrierDismissible: false,
  //     builder: (BuildContext context) {
  //       return Dialog(
  //         shape: RoundedRectangleBorder(
  //           borderRadius: BorderRadius.circular(20),
  //         ),
  //         insetPadding: const EdgeInsets.symmetric(
  //           horizontal: 40,
  //           vertical: 24,
  //         ),
  //         child: Container(
  //           padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
  //           decoration: BoxDecoration(
  //             color: Colors.white,
  //             borderRadius: BorderRadius.circular(20),
  //             boxShadow: [
  //               BoxShadow(
  //                 color: Colors.black.withValues(alpha: 0.10),
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
  //                 mainAxisAlignment: MainAxisAlignment.spaceEvenly,
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
  //                         AppSettings.openAppSettings(
  //                           type: AppSettingsType.wifi,
  //                         );
  //                       },
  //                       style: TextButton.styleFrom(
  //                         padding: const EdgeInsets.symmetric(vertical: 14),
  //                         shape: RoundedRectangleBorder(
  //                           borderRadius: BorderRadius.circular(14),
  //                         ),
  //                         backgroundColor: const Color(0xFF4CAF50),
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

  Future<void> _handleNavigation(MenuState menuState) async {
    if (menuState == widget.selectedMenu) return;

    // final hasInternet = await _hasInternet();
    // if (!hasInternet) {
    //   _showNoInternetDialog();
    //   return;
    // }
    widget.onItemSelected(menuState);
  }

  @override
  Widget build(BuildContext context) {
    const Color appGreen = Color(0xFF1AB69C);
    const Color cardBackground = Colors.white;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: cardBackground,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.20),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildNavItem(
              icon: Icons.home_outlined,
              label: 'Home',
              isSelected: widget.selectedMenu == MenuState.homedashboard,
              activeColor: appGreen,
              inactiveColor: Colors.grey[600]!,
              onTap: () => _handleNavigation(MenuState.homedashboard),
            ),
            _buildNavItem(
              icon: Icons.map_outlined,
              label: 'New Trip',
              isSelected: widget.selectedMenu == MenuState.map,
              activeColor: appGreen,
              inactiveColor: Colors.grey[600]!,
              onTap: () => _handleNavigation(MenuState.map),
            ),
            _buildNavItem(
              icon: Icons.notifications_outlined,
              label: 'Alerts',
              isSelected: widget.selectedMenu == MenuState.notification,
              activeColor: appGreen,
              inactiveColor: Colors.grey[600]!,
              onTap: () => _handleNavigation(MenuState.notification),
              badgeCount: widget.unreadCount,
            ),
            _buildNavItem(
              icon: Icons.inventory_2_outlined,
              label: 'Products',
              isSelected: widget.selectedMenu == MenuState.productsScreen,
              activeColor: appGreen,
              inactiveColor: Colors.grey[600]!,
              onTap: () => _handleNavigation(MenuState.productsScreen),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required String label,
    required bool isSelected,
    required Color activeColor,
    required Color inactiveColor,
    required VoidCallback onTap,
    int badgeCount = 0,
  }) {
    // sizes
    const double topIndicatorHeight = 4;
    const double iconSize = 26;
    const double dotSize = 6;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Top indicator line
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            height: topIndicatorHeight,
            width: isSelected ? 40 : 0,
            decoration: BoxDecoration(
              color: isSelected ? activeColor : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
          ),

          const SizedBox(height: 6),

          // Icon with subtle selected background
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            padding: isSelected ? const EdgeInsets.all(6) : EdgeInsets.zero,
            decoration: BoxDecoration(
              color: isSelected
                  ? activeColor.withValues(alpha: 0.08)
                  : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Icon(
                  icon,
                  color: isSelected ? activeColor : inactiveColor,
                  size: iconSize,
                ),
                if (badgeCount > 0)
                  Positioned(
                    right: -6,
                    top: -6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 18,
                        minHeight: 18,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.redAccent,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      child: Text(
                        badgeCount > 99 ? '99+' : badgeCount.toString(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 4),

          // Label
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isSelected ? activeColor : inactiveColor,
            ),
          ),

          const SizedBox(height: 4),

          // Bottom dot (small indicator under the label)
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            height: dotSize,
            width: dotSize,
            decoration: BoxDecoration(
              color: isSelected ? activeColor : Colors.transparent,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }
}
