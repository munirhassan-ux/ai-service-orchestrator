import 'package:flutter/material.dart';
import '../../main_provider.dart' show kProviderDisplayName, kProviderId;
import '../../services/api_service.dart';

class ProviderDashboardScreen extends StatefulWidget {
  const ProviderDashboardScreen({super.key});
  @override
  State<ProviderDashboardScreen> createState() => _ProviderDashboardScreenState();
}

class _ProviderDashboardScreenState extends State<ProviderDashboardScreen> {
  bool _available = true;
  Map<String, dynamic>? _stats;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      // Prefer exact ID lookup (always correct); fall back to name if ID not in URL
      final endpoint = kProviderId.isNotEmpty
          ? 'provider/${Uri.encodeComponent(kProviderId)}/reliability-full'
          : 'provider/by-name/${Uri.encodeComponent(kProviderDisplayName)}/stats';
      final res = await ApiService.get(endpoint);
      if (mounted) setState(() => _stats = res as Map<String, dynamic>?);
    } catch (_) {}
  }

  String _pct(dynamic v) {
    if (v == null) return '—';
    final d = (v as num).toDouble();
    return '${(d * 100).round()}%';
  }

  @override
  Widget build(BuildContext context) {
    final onTime   = _stats != null ? _pct(_stats!['on_time_score'])     : '—';
    final cancelPct = _stats != null ? _pct(_stats!['cancellation_risk']) : '—';
    final risk     = _stats != null
        ? (_stats!['cancellation_risk'] as num).toStringAsFixed(2)
        : '—';
    final jobs     = _stats != null ? '${_stats!['total_jobs'] ?? '—'}'  : '—';
    final rating   = _stats != null
        ? '${(_stats!['rating'] as num).toStringAsFixed(1)} ★'
        : '—';

    final onTimeColor   = _stats == null ? const Color(0xFF767773)
        : (_stats!['on_time_score'] as num) >= 0.8
            ? const Color(0xFF3A9010)
            : const Color(0xFFf59e0b);
    final cancelColor   = _stats == null ? const Color(0xFF767773)
        : (_stats!['cancellation_risk'] as num) <= 0.10
            ? const Color(0xFF3A9010)
            : const Color(0xFFda2721);

    return Scaffold(
      backgroundColor: const Color(0xFFF7FAF5),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: const Color(0xFF163300),
        elevation: 0,
        title: const Text('Dashboard',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70, size: 20),
            onPressed: _loadStats,
            tooltip: 'Refresh stats',
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        // Availability toggle
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _available
                ? const Color(0xFF3A9010).withValues(alpha: 0.08)
                : Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: _available
                    ? const Color(0xFF3A9010).withValues(alpha: 0.3)
                    : const Color(0xFFE8EDE6)),
          ),
          child: Row(children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_available ? '🟢 Available' : '🔴 Offline',
                  style: TextStyle(
                      color: _available ? const Color(0xFF3A9010) : Colors.redAccent,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                  _available ? 'Aap job receive kar rahe hain' : 'Aap ko jobs nahi aayen gi',
                  style: const TextStyle(color: Color(0xFF767773), fontSize: 12)),
            ]),
            const Spacer(),
            Switch(
                value: _available,
                onChanged: (v) => setState(() => _available = v),
                activeThumbColor: const Color(0xFF3A9010)),
          ]),
        ),
        const SizedBox(height: 24),
        const Text('PERFORMANCE',
            style: TextStyle(
                color: Color(0xFF767773), fontSize: 11,
                fontWeight: FontWeight.w700, letterSpacing: 1.2)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE8EDE6))),
          child: _stats == null
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Color(0xFF3A9010)),
                  ))
              : Column(children: [
                  _perfRow('On-time Score',     onTime,     onTimeColor),
                  const Divider(color: Color(0xFFE8EDE6), height: 20),
                  _perfRow('Cancellation Rate', cancelPct,  cancelColor),
                  const Divider(color: Color(0xFFE8EDE6), height: 20),
                  _perfRow('Risk Score',        risk,       Colors.blue),
                  const Divider(color: Color(0xFFE8EDE6), height: 20),
                  _perfRow('Jobs Completed',    jobs,       const Color(0xFF21231D)),
                  const Divider(color: Color(0xFFE8EDE6), height: 20),
                  _perfRow('Current Rating',    rating,     const Color(0xFF3A9010)),
                ]),
        ),
      ]),
    );
  }

  Widget _perfRow(String label, String value, Color color) => Row(children: [
    Expanded(
        child: Text(label,
            style: const TextStyle(color: Color(0xFF565955), fontSize: 13))),
    Text(value,
        style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.bold)),
  ]);
}
