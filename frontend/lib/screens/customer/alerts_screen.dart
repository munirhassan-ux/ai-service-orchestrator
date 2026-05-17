import 'package:flutter/material.dart';

class AlertsScreen extends StatelessWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final alerts = [
      {'icon': Icons.check_circle_outline, 'color': Color(0xFF00C853), 'title': 'Provider Accepted!', 'body': 'Hassan Plumbing Works ne aap ki booking accept kar li!', 'time': '2 min ago'},
      {'icon': Icons.timer_outlined, 'color': Colors.amber, 'title': '1 Ghante Ki Reminder', 'body': 'Aaj 4:00 PM par Plumber aane wala hai. Tayaar rahein!', 'time': '30 min ago'},
      {'icon': Icons.star_outline_rounded, 'color': Colors.blue, 'title': 'Rate Now', 'body': 'Cool Air Solutions ne kaam complete kar diya. Rate karein!', 'time': 'Yesterday'},
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(backgroundColor: const Color(0xFF1E293B), elevation: 0, title: const Text("Alerts", style: TextStyle(fontWeight: FontWeight.bold))),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: alerts.length,
        itemBuilder: (_, i) {
          final a = alerts[i];
          final color = a['color'] as Color;
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withOpacity(0.2)),
            ),
            child: Row(children: [
              Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: color.withOpacity(0.12), shape: BoxShape.circle), child: Icon(a['icon'] as IconData, color: color, size: 20)),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(a['title'] as String, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                const SizedBox(height: 3),
                Text(a['body'] as String, style: const TextStyle(color: Colors.white54, fontSize: 12, height: 1.4)),
              ])),
              const SizedBox(width: 8),
              Text(a['time'] as String, style: const TextStyle(color: Colors.white38, fontSize: 10)),
            ]),
          );
        },
      ),
    );
  }
}
