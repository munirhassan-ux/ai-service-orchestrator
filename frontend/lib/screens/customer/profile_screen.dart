import 'package:flutter/material.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(backgroundColor: const Color(0xFF1E293B), elevation: 0, title: const Text("Profile", style: TextStyle(fontWeight: FontWeight.bold))),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Center(child: Column(children: [
          Container(width: 72, height: 72, decoration: BoxDecoration(color: const Color(0xFF00C853).withOpacity(0.15), shape: BoxShape.circle, border: Border.all(color: const Color(0xFF00C853).withOpacity(0.4), width: 2)),
            child: const Icon(Icons.person_rounded, size: 40, color: Color(0xFF00C853))),
          const SizedBox(height: 12),
          const Text("Customer", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const Text("customer_001", style: TextStyle(color: Colors.white38, fontSize: 13)),
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

  Widget _section(String title, List<Widget> children) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(title, style: const TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1))),
    Container(decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white.withOpacity(0.07))),
      child: Column(children: children)),
  ]);

  Widget _tile(IconData icon, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    child: Row(children: [
      Icon(icon, size: 18, color: Colors.white38),
      const SizedBox(width: 14),
      Expanded(child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 14))),
      Text(value, style: const TextStyle(color: Colors.white38, fontSize: 13)),
    ]),
  );

  Widget _switchTile(String label) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    child: Row(children: [
      Expanded(child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 14))),
      Switch(value: true, onChanged: (_) {}, activeColor: const Color(0xFF00C853)),
    ]),
  );
}
