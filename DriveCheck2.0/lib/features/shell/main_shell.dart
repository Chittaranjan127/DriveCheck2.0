import 'package:flutter/material.dart';

import '../../shared/widgets/app_bottom_nav.dart';
import '../home/home_screen.dart';
import '../inspections/inspections_screen.dart';
import '../profile/profile_screen.dart';

/// Bottom-nav shell. Hosts Home, Inspections, Profile.
/// (Settings was rolled into the profile screen: language picker +
/// AI-assistant toggle + logout all live there now, alongside the
/// jockey's identity + stats. The third tab used to be Settings.)
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  static const _pages = <Widget>[
    HomeScreen(),
    InspectionsScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: AppBottomNav(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
      ),
    );
  }
}
