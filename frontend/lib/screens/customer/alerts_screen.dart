import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../services/api_service.dart';
import '../../services/booking_events.dart';

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});
  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  List<Map<String, dynamic>> _alerts = [];
  bool _isLoading = true;
  StreamSubscription<void>? _refreshSub;

  @override
  void initState() {
    super.initState();
    _fetchAlerts();
    _refreshSub = BookingEvents.onRefresh.listen((_) => _fetchAlerts());
  }

  @override
  void dispose() {
    _refreshSub?.cancel();
    super.dispose();
  }

  Future<void> _fetchAlerts() async {
    if (!mounted) return;
    try {
      final res = await ApiService.get('bookings');
      if (!mounted) return;
      final bookings = res is List ? List<dynamic>.from(res) : <dynamic>[];
      final alerts = _generateAlerts(bookings);
      setState(() {
        _alerts = alerts;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> _generateAlerts(List<dynamic> bookings) {
    final alerts = <Map<String, dynamic>>[];
    final now = DateTime.now();

    for (final booking in bookings.take(20)) {
      final b = booking as Map<String, dynamic>;
      final status = b['status'] as String? ?? '';
      final providerName = b['provider_name'] as String? ?? 'Provider';
      final serviceType = b['service_type'] as String? ?? 'Service';
      final scheduledRaw = b['scheduled_time'] as String?;
      final updatedRaw = b['updated_at'] as String? ?? b['created_at'] as String?;
      final updatedTime = updatedRaw != null ? DateTime.tryParse(updatedRaw) : null;
      final timeAgo = _timeAgo(updatedTime, now);

      switch (status) {
        case 'PENDING_PROVIDER':
          alerts.add({
            'icon': Icons.hourglass_top_rounded,
            'color': const Color(0xFFFFB300),
            'title': 'Awaiting Provider',
            'body': '$serviceType request sent — waiting for $providerName to confirm.',
            'time': timeAgo,
          });
          break;

        case 'ACCEPTED':
          alerts.add({
            'icon': Icons.check_circle_outline_rounded,
            'color': const Color(0xFF3A9010),
            'title': 'Booking Confirmed!',
            'body': '$providerName ne aap ki $serviceType booking accept kar li!',
            'time': timeAgo,
          });
          if (scheduledRaw != null) {
            final scheduledTime = DateTime.tryParse(scheduledRaw);
            if (scheduledTime != null) {
              final diff = scheduledTime.difference(now);
              if (diff.inMinutes > 0 && diff.inMinutes <= 120) {
                alerts.add({
                  'icon': Icons.timer_rounded,
                  'color': const Color(0xFF7A5400),
                  'title': 'Upcoming Reminder',
                  'body': '$providerName ${diff.inMinutes} minutes mein aa raha hai. Tayaar rahein!',
                  'time': timeAgo,
                });
              }
            }
          }
          break;

        case 'ARRIVING':
          alerts.add({
            'icon': Icons.directions_bike_rounded,
            'color': Colors.blueAccent,
            'title': 'Provider En Route',
            'body': '$providerName aap ke paas aa raha hai!',
            'time': timeAgo,
          });
          break;

        case 'ARRIVED':
          alerts.add({
            'icon': Icons.location_on_rounded,
            'color': Colors.purpleAccent,
            'title': 'Provider Arrived',
            'body': '$providerName aap ke darwaze par aa gaya hai!',
            'time': timeAgo,
          });
          break;

        case 'IN_PROGRESS':
          alerts.add({
            'icon': Icons.build_rounded,
            'color': const Color(0xFF7A5400),
            'title': 'Work in Progress',
            'body': '$providerName aap ka $serviceType kaam kar raha hai.',
            'time': timeAgo,
          });
          break;

        case 'COMPLETED':
          alerts.add({
            'icon': Icons.star_outline_rounded,
            'color': Colors.blueAccent,
            'title': 'Rate Your Provider',
            'body': '$providerName ne kaam mukammal kar diya. Apna tajurba share karein!',
            'time': timeAgo,
          });
          break;

        case 'CANCELLED_TIMEOUT':
          alerts.add({
            'icon': Icons.timer_off_rounded,
            'color': Colors.redAccent,
            'title': 'Request Expired',
            'body': 'Koi provider waqt par available nahi tha. Dobara try karein.',
            'time': timeAgo,
          });
          break;

        case 'CANCELLED_CUSTOMER':
        case 'CANCELLED_PROVIDER':
          alerts.add({
            'icon': Icons.cancel_outlined,
            'color': Colors.redAccent,
            'title': 'Booking Cancelled',
            'body': '$serviceType booking cancel ho gayi. Naya request chat se bhejein.',
            'time': timeAgo,
          });
          break;
      }
    }

    return alerts;
  }

  String _timeAgo(DateTime? dt, DateTime now) {
    if (dt == null) return '';
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAF5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF163300),
        elevation: 0,
        title: SvgPicture.asset('assets/haazir_logo.svg', height: 26),
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _fetchAlerts),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: const Color(0xFF3A9010)))
          : _alerts.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.notifications_off_outlined, color: const Color(0xFFE8EDE6), size: 48),
                      SizedBox(height: 12),
                      Text("Koi alert nahi", style: TextStyle(color: const Color(0xFF767773), fontSize: 14)),
                      SizedBox(height: 4),
                      Text("Booking karne par yahan updates milenge", style: TextStyle(color: Color(0xFF767773), fontSize: 12)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _alerts.length,
                  itemBuilder: (_, i) {
                    final a = _alerts[i];
                    final color = a['color'] as Color;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: color.withValues(alpha: 0.2)),
                      ),
                      child: Row(children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(a['icon'] as IconData, color: color, size: 20),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(
                              a['title'] as String,
                              style: const TextStyle(color: const Color(0xFF21231D), fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              a['body'] as String,
                              style: const TextStyle(color: const Color(0xFF565955), fontSize: 12, height: 1.4),
                            ),
                          ]),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          a['time'] as String,
                          style: const TextStyle(color: const Color(0xFF767773), fontSize: 10),
                        ),
                      ]),
                    );
                  },
                ),
    );
  }
}
