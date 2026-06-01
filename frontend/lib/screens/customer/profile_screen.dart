import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAF5),
      appBar: AppBar(
          automaticallyImplyLeading: false,
          backgroundColor: const Color(0xFF163300),
          elevation: 0,
          title: Text("Profile",
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.white))),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Center(
            child: Column(children: [
          Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                  color: const Color(0xFF3A9010).withOpacity(0.15),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: const Color(0xFF3A9010).withOpacity(0.4),
                      width: 2)),
              child: const Icon(Icons.person_rounded,
                  size: 40, color: const Color(0xFF3A9010))),
          const SizedBox(height: 12),
          const Text("Customer",
              style: TextStyle(
                  color: const Color(0xFF21231D),
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
          const Text("customer_001",
              style: TextStyle(color: const Color(0xFF767773), fontSize: 13)),
        ])),
        const SizedBox(height: 28),
        _section("Settings", [
          _tile(Icons.location_on_outlined, "Default Area", "G-11, Islamabad"),
          _tile(Icons.language_outlined, "Preferred Language", "Roman Urdu"),
        ]),
        const SizedBox(height: 16),
        _section("Activity", [
          _tile(Icons.calendar_today_outlined, "Total Bookings", "3"),
          _tile(Icons.warning_amber_outlined, "Disputes Filed", "0"),
        ]),
        const SizedBox(height: 16),
        _section("Notifications", [
          _switchTile("Provider updates"),
          _switchTile("1-hour reminders"),
          _switchTile("Promotions"),
        ]),
      ]),
    );
  }

  Widget _section(String title, List<Widget> children) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(title,
                style: const TextStyle(
                    color: const Color(0xFF767773),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1))),
        Container(
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE8EDE6))),
            child: Column(children: children)),
      ]);

  Widget _tile(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          Icon(icon, size: 18, color: const Color(0xFF767773)),
          const SizedBox(width: 14),
          Expanded(
              child: Text(label,
                  style: const TextStyle(
                      color: const Color(0xFF3E3F3B), fontSize: 14))),
          Text(value,
              style: const TextStyle(
                  color: const Color(0xFF767773), fontSize: 13)),
        ]),
      );

  Widget _switchTile(String label) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          Expanded(
              child: Text(label,
                  style: const TextStyle(
                      color: const Color(0xFF3E3F3B), fontSize: 14))),
          Switch(
              value: true,
              onChanged: (_) {},
              activeColor: const Color(0xFF3A9010)),
        ]),
      );
}
