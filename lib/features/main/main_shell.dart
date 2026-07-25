import 'package:flutter/material.dart';

import '../club/clubs_hub_screen.dart';
import '../home/home_screen.dart';
import '../messaging/club_work_screen.dart';
import '../profile/profile_screen.dart';
import '../search/global_search_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int index = 0;
  int discoverRevision = 0;
  final home = const HomeScreen();
  final work = const ClubWorkScreen();
  final clubs = const ClubsHubScreen();
  final profile = const ProfileScreen();

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      home,
      GlobalSearchScreen(key: ValueKey(discoverRevision)),
      work,
      clubs,
      profile,
    ];
    return Scaffold(
      body: IndexedStack(
        index: index,
        children: [
          for (var pageIndex = 0; pageIndex < pages.length; pageIndex++)
            HeroMode(enabled: pageIndex == index, child: pages[pageIndex]),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() {
          index = value;
          if (value == 1) discoverRevision++;
        }),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Home'),
          NavigationDestination(
              icon: Icon(Icons.explore_outlined),
              selectedIcon: Icon(Icons.explore),
              label: 'Discover'),
          NavigationDestination(
              icon: Icon(Icons.forum_outlined),
              selectedIcon: Icon(Icons.forum),
              label: 'Work'),
          NavigationDestination(
              icon: Icon(Icons.groups_outlined),
              selectedIcon: Icon(Icons.groups),
              label: 'Clubs'),
          NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Profile'),
        ],
      ),
    );
  }
}
