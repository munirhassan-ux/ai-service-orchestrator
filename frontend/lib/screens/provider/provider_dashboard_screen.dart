import 'package:flutter/material.dart';

class ProviderDashboardScreen extends StatefulWidget {
  const ProviderDashboardScreen({super.key});
  @override
  State<ProviderDashboardScreen> createState() => _ProviderDashboardScreenState();
}

class _ProviderDashboardScreenState extends State<ProviderDashboardScreen> {
  bool _available = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(backgroundColor: const Color(0xFF1E293B), elevation: 0, title: const Text("Dashboard", style: TextStyle(fontWeight: FontWeight.bold))),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        // Availability toggle
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _available ? const Color(0xFF00C853).withOpacity(0.08) : Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _available ? const Color(0xFF00C853).withOpacity(0.3) : Colors.white12),
          ),
          child: Row(children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_available ? "🟢 Available" : "🔴 Offline", style: TextStyle(color: _available ? const Color(0xFF00C853) : Colors.redAccent, fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(_available ? "Aap job receive kar rahe hain" : "Aap ko jobs nahi aayen gi", style: const TextStyle(color: Colors.white38, fontSize: 12)),
            ]),
            const Spacer(),
            Switch(value: _available, onChanged: (v) => setState(() => _available = v), activeColor: const Color(0xFF00C853)),
          ]),
        ),
        const SizedBox(height: 24),
        const Text("EARNINGS", style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _statCard("Today", "Rs. 1,400", Colors.amber)),
          const SizedBox(width: 12),
          Expanded(child: _statCard("This Week", "Rs. 6,200", const Color(0xFF00C853))),
        ]),
        const SizedBox(height: 24),
        const Text("PERFORMANCE", style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withOpacity(0.07))),
          child: Column(children: [
            _perfRow("On-time Score", "88%", const Color(0xFF00C853)),
            const Divider(color: Colors.white10, height: 20),
            _perfRow("Cancellation Rate", "6%", Colors.amber),
            const Divider(color: Colors.white10, height: 20),
            _perfRow("Risk Score", "0.12", Colors.blue),
            const Divider(color: Colors.white10, height: 20),
            _perfRow("Jobs Completed", "47", Colors.white),
            const Divider(color: Colors.white10, height: 20),
            _perfRow("Current Rating", "4.5 ★", Colors.amber),
          ]),
        ),
        const SizedBox(height: 24),
        const Text("UTILISATION", style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
        const SizedBox(height: 12),
        _statCard("This Week", "3 / 5 slots filled", Colors.blue),
      ]),
    );
  }

  Widget _statCard(String label, String value, Color color) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(color: color.withOpacity(0.07), borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withOpacity(0.2))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      Text(value, style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.bold)),
    ]),
  );

  Widget _perfRow(String label, String value, Color color) => Row(children: [
    Expanded(child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13))),
    Text(value, style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.bold)),
  ]);
}
