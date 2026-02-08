import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:getready_bmx/providers/theme_provider.dart';
import 'package:getready_bmx/providers/auth_provider.dart';

class BottomNav extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;

  const BottomNav({required this.currentIndex, required this.onTap});

  void handleTap(BuildContext context, int index) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (!authProvider.isAuthenticated) {
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
      return;
    }
    onTap(index);
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final primary = themeProvider.primaryColor;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            height: 70,
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withOpacity(0.08)
                  : Colors.black.withOpacity(0.05),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: isDark
                    ? Colors.white.withOpacity(0.1)
                    : Colors.black.withOpacity(0.05),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _NavItem(
                  icon: Icons.live_tv_outlined,
                  activeIcon: Icons.live_tv,
                  isActive: currentIndex == 1,
                  onTap: () => handleTap(context, 1),
                  activeColor: primary,
                ),
                _NavItem(
                  icon: Icons.history_outlined,
                  activeIcon: Icons.history,
                  isActive: currentIndex == 2,
                  onTap: () => handleTap(context, 2),
                  activeColor: primary,
                ),
                const SizedBox(width: 48), // Space for Home FAB
                _NavItem(
                  icon: Icons.leaderboard_outlined,
                  activeIcon: Icons.leaderboard,
                  isActive: currentIndex == 3,
                  onTap: () => handleTap(context, 3),
                  activeColor: primary,
                ),
                _NavItem(
                  icon: Icons.settings_outlined,
                  activeIcon: Icons.settings,
                  isActive: currentIndex == 4,
                  onTap: () => handleTap(context, 4),
                  activeColor: primary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final bool isActive;
  final VoidCallback onTap;
  final Color activeColor;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.isActive,
    required this.onTap,
    required this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isActive ? activeColor.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Icon(
          isActive ? activeIcon : icon,
          color: isActive ? activeColor : Colors.grey.withOpacity(0.7),
          size: 28,
        ),
      ),
    );
  }
}
