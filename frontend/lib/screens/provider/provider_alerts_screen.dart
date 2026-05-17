import 'package:flutter/material.dart';

class ProviderAlertsScreen extends StatelessWidget {
  const ProviderAlertsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final alerts = [
      {'icon': Icons.notifications_active, 'color': Colors.amber, 'title': 'Naya Kaam!', 'body': 'Plumber job in G-11. 7 minute mein respond karein.', 'time': '5 min ago'},
      {'icon': Icons.star_rounded, 'color': Colors.blue, 'title': 'Rating Mili!', 'body': 'Munir ne aap ko 5★ diye. Bohat shukriya!', 'time': '2 hours ago'},
      {'icon': Icons.timer_outlined, 'color': Color(0xFF00C853), 'title': 'Reminder', 'body': '1 ghante mein job hai: Plumber, G-11. Rawan ho jayen!', 'time': 'Yesterday'},
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
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withOpacity(0.2))),
            child: Row(children: [
              Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: color.withOpacity(0.12), shape: BoxShape.circle), child: Icon(a['icon'] as IconData, color: color, size: 18)),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(a['title'] as String, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 3),
                Text(a['body'] as String, style: const TextStyle(color: Colors.white54, fontSize: 12, height: 1.4)),
              ])),
              Text(a['time'] as String, style: const TextStyle(color: Colors.white38, fontSize: 10)),
            ]),
          );
        },
      ),
    );
  }
}
