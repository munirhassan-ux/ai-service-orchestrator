import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import 'chat_screen.dart';

class BookingsScreen extends StatefulWidget {
  const BookingsScreen({super.key});

  @override
  State<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends State<BookingsScreen> {
  List<dynamic> _bookings = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchBookings();
  }

  Future<void> _fetchBookings() async {
    try {
      final res = await ApiService.get('bookings?customer_id=customer_001');
      if (mounted) {
        setState(() {
          _bookings = res is List ? res : [];
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
        title: const Text("My Bookings", style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchBookings)
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00C853)))
          : _bookings.isEmpty
              ? const Center(child: Text("No bookings found", style: TextStyle(color: Colors.white54)))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _bookings.length,
                  itemBuilder: (_, i) {
                    final b = _bookings[i];
                    final statusColor = b['status'] == 'ACCEPTED' ? const Color(0xFF00C853)
                        : b['status'] == 'COMPLETED' ? Colors.blue
                        : b['status'] == 'IN_PROGRESS' || b['status'] == 'ARRIVED' || b['status'] == 'ARRIVING' ? Colors.amber
                        : b['status'] == 'PENDING_PROVIDER' ? Colors.orange
                        : Colors.redAccent;
                    return GestureDetector(
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => ChatScreen(bookingId: b['booking_id'])
                        ));
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withOpacity(0.07)),
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                            Text(b['service_type'] as String? ?? 'Service', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(color: statusColor.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
                              child: Text(b['status'] as String? ?? 'UNKNOWN', style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold)),
                            ),
                          ]),
                          const SizedBox(height: 6),
                          Text(b['provider_name'] as String? ?? 'Waiting...', style: const TextStyle(color: Colors.white54, fontSize: 13)),
                          const SizedBox(height: 4),
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                            Text((b['scheduled_time'] as String?)?.substring(0, 16) ?? 'TBD', style: const TextStyle(color: Colors.white38, fontSize: 12)),
                            if (b['final_price'] != null && (b['final_price'] as int) > 0) Text("Rs. ${b['final_price']}", style: const TextStyle(color: Color(0xFF00C853), fontWeight: FontWeight.bold)),
                          ]),
                          const SizedBox(height: 8),
                          _buildTracker(b['status'] as String? ?? ''),
                        ]),
                      ),
                    );
                  },
                ),
    );
  }

  Widget _buildTracker(String status) {
    const stages = ['PENDING', 'ACCEPTED', 'ARRIVED', 'IN PROGRESS', 'COMPLETED'];
    int active = 0;
    if (status == 'PENDING_PROVIDER') active = 1;
    if (status == 'ACCEPTED' || status == 'ARRIVING') active = 2;
    if (status == 'ARRIVED') active = 3;
    if (status == 'IN_PROGRESS') active = 4;
    if (status == 'COMPLETED') active = 5;
    
    if (status.contains('CANCELLED')) {
       return const Text("Booking Cancelled", style: TextStyle(color: Colors.redAccent, fontSize: 12));
    }

    return Row(children: List.generate(stages.length, (i) => Expanded(child: Row(children: [
      Expanded(child: Column(children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: i < active ? const Color(0xFF00C853) : Colors.white12, shape: BoxShape.circle)),
        if (i == active - 1) Text(stages[i], style: const TextStyle(color: Color(0xFF00C853), fontSize: 9), textAlign: TextAlign.center),
      ])),
      if (i < stages.length - 1) Expanded(child: Container(height: 1, color: i < active - 1 ? const Color(0xFF00C853) : Colors.white12)),
    ]))));
  }
}
