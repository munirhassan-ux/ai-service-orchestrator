import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'jobs_screen.dart';
import 'provider_alerts_screen.dart';
import 'provider_dashboard_screen.dart';
import '../customer/customer_home.dart';
import '../../services/booking_events.dart';

class ProviderHome extends StatefulWidget {
  const ProviderHome({super.key});
  @override
  State<ProviderHome> createState() => _ProviderHomeState();
}

class _ProviderHomeState extends State<ProviderHome> {
  int _tab = 0;
  final _screens = const [JobsScreen(), ProviderAlertsScreen(), ProviderDashboardScreen()];

  void _onTabTap(int i) {
    // Fire a refresh whenever the Jobs tab is brought into view
    if (i == 0) BookingEvents.refresh();
    setState(() => _tab = i);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            SvgPicture.asset('assets/haazir_logo.svg', height: 28),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.handyman_rounded, size: 16, color: const Color(0xFF3A9010)),
                const SizedBox(width: 4),
                const Text('Provider', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const CustomerHome()),
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3A9010).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text('To Customer', style: TextStyle(color: const Color(0xFF3A9010), fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ],
        backgroundColor: const Color(0xFF163300),
        elevation: 0,
      ),
      body: IndexedStack(index: _tab, children: _screens),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: const Color(0xFFE8EDE6))),
        ),
        child: BottomNavigationBar(
          currentIndex: _tab,
          onTap: _onTabTap,
          backgroundColor: Colors.transparent,
          selectedItemColor: const Color(0xFF3A9010),
          unselectedItemColor: const Color(0xFF767773),
          type: BottomNavigationBarType.fixed,
          elevation: 0,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.work_outline_rounded), activeIcon: Icon(Icons.work_rounded), label: "My Jobs"),
            BottomNavigationBarItem(icon: Icon(Icons.notifications_none_rounded), activeIcon: Icon(Icons.notifications_rounded), label: "Alerts"),
            BottomNavigationBarItem(icon: Icon(Icons.dashboard_outlined), activeIcon: Icon(Icons.dashboard_rounded), label: "Dashboard"),
          ],
        ),
      ),
    );
  }
}
