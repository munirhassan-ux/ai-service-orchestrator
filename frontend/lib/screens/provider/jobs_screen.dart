import 'package:flutter/material.dart';

class JobsScreen extends StatelessWidget {
  const JobsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final jobs = [
      {'service': 'Plumber', 'customer': 'Munir', 'area': 'G-11', 'time': 'Today 4:00 PM', 'price': 1400, 'status': 'Confirmed'},
      {'service': 'Electrician', 'customer': 'Ahmed', 'area': 'F-10', 'time': 'Yesterday', 'price': 1800, 'status': 'Completed'},
      {'service': 'AC Repair', 'customer': 'Sara', 'area': 'I-8', 'time': 'May 15', 'price': 2200, 'status': 'Completed'},
    ];
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(backgroundColor: const Color(0xFF1E293B), elevation: 0, title: const Text("My Jobs", style: TextStyle(fontWeight: FontWeight.bold))),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: jobs.length,
        itemBuilder: (_, i) {
          final j = jobs[i];
          final isConfirmed = j['status'] == 'Confirmed';
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: isConfirmed ? Colors.amber.withOpacity(0.3) : Colors.white.withOpacity(0.06)),
            ),
            child: Row(children: [
              Container(width: 40, height: 40, decoration: BoxDecoration(color: isConfirmed ? Colors.amber.withOpacity(0.15) : Colors.white.withOpacity(0.06), shape: BoxShape.circle),
                child: Icon(Icons.work_rounded, size: 20, color: isConfirmed ? Colors.amber : Colors.white38)),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text("${j['service']} — ${j['area']}", style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                Text("${j['customer']} · ${j['time']}", style: const TextStyle(color: Colors.white38, fontSize: 12)),
              ])),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text("Rs. ${j['price']}", style: const TextStyle(color: Color(0xFF00C853), fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: isConfirmed ? Colors.amber.withOpacity(0.15) : Colors.green.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
                  child: Text(j['status'] as String, style: TextStyle(color: isConfirmed ? Colors.amber : Colors.green, fontSize: 10, fontWeight: FontWeight.bold))),
              ]),
            ]),
          );
        },
      ),
    );
  }
}
