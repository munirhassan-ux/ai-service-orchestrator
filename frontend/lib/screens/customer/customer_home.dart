import 'package:flutter/material.dart';
import 'chat_screen.dart';
import 'bookings_screen.dart';
import 'alerts_screen.dart';
import 'profile_screen.dart';

class CustomerHome extends StatefulWidget {
  const CustomerHome({super.key});
  @override
  State<CustomerHome> createState() => _CustomerHomeState();
}

class _CustomerHomeState extends State<CustomerHome> {
  int _tab = 0;
  final _screens = const [ChatScreen(), BookingsScreen(), AlertsScreen(), ProfileScreen()];

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
          selectedItemColor: const Color(0xFF00C853),
          unselectedItemColor: Colors.white38,
          type: BottomNavigationBarType.fixed,
          elevation: 0,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.chat_bubble_outline_rounded), activeIcon: Icon(Icons.chat_bubble_rounded), label: "Chat"),
            BottomNavigationBarItem(icon: Icon(Icons.list_alt_outlined), activeIcon: Icon(Icons.list_alt_rounded), label: "Bookings"),
            BottomNavigationBarItem(icon: Icon(Icons.notifications_none_rounded), activeIcon: Icon(Icons.notifications_rounded), label: "Alerts"),
            BottomNavigationBarItem(icon: Icon(Icons.person_outline_rounded), activeIcon: Icon(Icons.person_rounded), label: "Profile"),
          ],
        ),
      ),
    );
  }
}
