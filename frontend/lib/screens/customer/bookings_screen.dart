import 'package:flutter/material.dart';

class BookingsScreen extends StatelessWidget {
  const BookingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final bookings = [
      {'id': 'BK-20260517-001', 'service': 'Plumber', 'provider': 'Hassan Plumbing Works', 'status': 'Confirmed', 'price': 1400, 'date': 'Today, 4:00 PM'},
      {'id': 'BK-20260516-002', 'service': 'AC Repair', 'provider': 'Cool Air Solutions', 'status': 'Completed', 'price': 2200, 'date': 'Yesterday, 2:00 PM'},
      {'id': 'BK-20260510-003', 'service': 'Electrician', 'provider': 'Rashid Electric', 'status': 'Cancelled', 'price': 0, 'date': 'May 10, 11:00 AM'},
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(backgroundColor: const Color(0xFF1E293B), elevation: 0, title: const Text("My Bookings", style: TextStyle(fontWeight: FontWeight.bold))),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: bookings.length,
        itemBuilder: (_, i) {
          final b = bookings[i];
          final statusColor = b['status'] == 'Confirmed' ? const Color(0xFF00C853)
              : b['status'] == 'Completed' ? Colors.blue
              : Colors.redAccent;
          return Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.07)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(b['service'] as String, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: statusColor.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
                  child: Text(b['status'] as String, style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ]),
              const SizedBox(height: 6),
              Text(b['provider'] as String, style: const TextStyle(color: Colors.white54, fontSize: 13)),
              const SizedBox(height: 4),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(b['date'] as String, style: const TextStyle(color: Colors.white38, fontSize: 12)),
                if ((b['price'] as int) > 0) Text("Rs. ${b['price']}", style: const TextStyle(color: Color(0xFF00C853), fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 8),
              // 5-stage tracker
              if (b['status'] == 'Confirmed') _buildTracker(1),
              if (b['status'] == 'Completed') _buildTracker(5),
            ]),
          );
        },
      ),
    );
  }

  Widget _buildTracker(int active) {
    const stages = ['Confirmed', 'En Route', 'Arrived', 'In Progress', 'Completed'];
    return Row(children: List.generate(stages.length, (i) => Expanded(child: Row(children: [
      Expanded(child: Column(children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: i < active ? const Color(0xFF00C853) : Colors.white12, shape: BoxShape.circle)),
        if (i == active - 1) Text(stages[i], style: const TextStyle(color: Color(0xFF00C853), fontSize: 9), textAlign: TextAlign.center),
      ])),
      if (i < stages.length - 1) Expanded(child: Container(height: 1, color: i < active - 1 ? const Color(0xFF00C853) : Colors.white12)),
    ]))));
  }
}
