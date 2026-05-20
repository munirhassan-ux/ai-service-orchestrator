import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class ProviderAlertsScreen extends StatelessWidget {
  const ProviderAlertsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final alerts = [
      {'icon': Icons.notifications_active, 'color': const Color(0xFF3A9010), 'title': 'Naya Kaam!', 'body': 'Plumber job in G-11. 7 minute mein respond karein.', 'time': '5 min ago'},
      {'icon': Icons.star_rounded, 'color': Colors.blue, 'title': 'Rating Mili!', 'body': 'Munir ne aap ko 5★ diye. Bohat shukriya!', 'time': '2 hours ago'},
      {'icon': Icons.timer_outlined, 'color': const Color(0xFF3A9010), 'title': 'Reminder', 'body': '1 ghante mein job hai: Plumber, G-11. Rawan ho jayen!', 'time': 'Yesterday'},
    ];
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAF5),
      appBar: AppBar(backgroundColor: const Color(0xFF163300), elevation: 0, title: SvgPicture.asset('assets/haazir_logo.svg', height: 26)),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: alerts.length,
        itemBuilder: (_, i) {
          final a = alerts[i];
          final color = a['color'] as Color;
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withOpacity(0.2))),
            child: Row(children: [
              Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: color.withOpacity(0.12), shape: BoxShape.circle), child: Icon(a['icon'] as IconData, color: color, size: 18)),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(a['title'] as String, style: const TextStyle(color: const Color(0xFF21231D), fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 3),
                Text(a['body'] as String, style: const TextStyle(color: const Color(0xFF565955), fontSize: 12, height: 1.4)),
              ])),
              Text(a['time'] as String, style: const TextStyle(color: const Color(0xFF767773), fontSize: 10)),
            ]),
          );
        },
      ),
    );
  }
}
