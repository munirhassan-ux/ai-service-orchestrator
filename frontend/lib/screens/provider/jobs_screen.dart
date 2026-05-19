import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import 'chat_screen.dart';

class JobsScreen extends StatefulWidget {
  const JobsScreen({super.key});

  @override
  State<JobsScreen> createState() => _JobsScreenState();
}

class _JobsScreenState extends State<JobsScreen> {
  List<dynamic> _jobs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchJobs();
  }

  Future<void> _fetchJobs() async {
    try {
      final res = await ApiService.get('bookings?provider_id=p019');
      if (mounted) {
        setState(() {
          _jobs = res is List ? res : [];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        title: const Text("My Jobs", style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchJobs)
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.amber))
          : _jobs.isEmpty
              ? const Center(child: Text("No jobs found", style: TextStyle(color: Colors.white54)))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _jobs.length,
                  itemBuilder: (_, i) {
                    final j = _jobs[i];
                    final status = j['status'] as String? ?? 'UNKNOWN';
                    final isConfirmed = status != 'PENDING_PROVIDER' && !status.contains('CANCELLED');
                    
                    return GestureDetector(
                      onTap: () {
                        // Navigate to job details / chat screen
                        Navigator.push(context, MaterialPageRoute(
                          builder: (context) => ProviderChatScreen(bookingId: j['booking_id'])
                        )).then((_) => _fetchJobs());
                      },
                      child: Container(
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
                            Text("${j['service_type']} — ${j['location']}", style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                            Text("${j['customer_id']} · ${(j['scheduled_time'] as String?)?.substring(0, 16) ?? ''}", style: const TextStyle(color: Colors.white38, fontSize: 12)),
                          ])),
                          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                            if (j['final_price'] != null) Text("Rs. ${j['final_price']}", style: const TextStyle(color: Color(0xFF00C853), fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: isConfirmed ? Colors.amber.withOpacity(0.15) : Colors.green.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
                              child: Text(status, style: TextStyle(color: isConfirmed ? Colors.amber : Colors.green, fontSize: 10, fontWeight: FontWeight.bold))),
                          ]),
                        ]),
                      ),
                    );
                  },
                ),
    );
  }
}
