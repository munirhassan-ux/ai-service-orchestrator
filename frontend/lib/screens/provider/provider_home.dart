import 'package:flutter/material.dart';
import 'chat_screen.dart';
import 'jobs_screen.dart';
import 'provider_alerts_screen.dart';
import 'provider_dashboard_screen.dart';

class ProviderHome extends StatefulWidget {
  const ProviderHome({super.key});
  @override
  State<ProviderHome> createState() => _ProviderHomeState();
}

class _ProviderHomeState extends State<ProviderHome> {
  int _tab = 0;
  final _screens = const [ProviderChatScreen(), JobsScreen(), ProviderAlertsScreen(), ProviderDashboardScreen()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _tab, children: _screens),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(color: Color(0xFF1E293B), border: Border(top: BorderSide(color: Colors.white10))),
        child: BottomNavigationBar(
          currentIndex: _tab,
          onTap: (i) => setState(() => _tab = i),
          backgroundColor: Colors.transparent,
          selectedItemColor: Colors.amber,
          unselectedItemColor: Colors.white38,
          type: BottomNavigationBarType.fixed,
          elevation: 0,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.chat_bubble_outline_rounded), activeIcon: Icon(Icons.chat_bubble_rounded), label: "Chat"),
            BottomNavigationBarItem(icon: Icon(Icons.work_outline_rounded), activeIcon: Icon(Icons.work_rounded), label: "My Jobs"),
            BottomNavigationBarItem(icon: Icon(Icons.notifications_none_rounded), activeIcon: Icon(Icons.notifications_rounded), label: "Alerts"),
            BottomNavigationBarItem(icon: Icon(Icons.dashboard_outlined), activeIcon: Icon(Icons.dashboard_rounded), label: "Dashboard"),
          ],
        ),
      ),
    );
  }
}
