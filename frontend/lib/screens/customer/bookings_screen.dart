import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../services/api_service.dart';
import '../../services/booking_events.dart';
import 'chat_screen.dart';

class BookingsScreen extends StatefulWidget {
  const BookingsScreen({super.key});

  @override
  State<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends State<BookingsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  StreamSubscription<void>? _refreshSub;
  List<dynamic> _bookings = [];
  bool _isLoading = true;

  static const _activeStatuses = {
    'PENDING_PROVIDER',
    'ACCEPTED',
    'ARRIVING',
    'ARRIVED',
    'IN_PROGRESS',
    'CANCELLED_PROVIDER',
  };

  int _statusPriority(String s) {
    switch (s) {
      case 'IN_PROGRESS':
        return 5;
      case 'ARRIVED':
        return 4;
      case 'ARRIVING':
        return 3;
      case 'ACCEPTED':
        return 2;
      case 'PENDING_PROVIDER':
        return 1;
      default:
        return 0;
    }
  }

  List<dynamic> get _activeBookings {
    final list = _bookings
        .where((b) => _activeStatuses.contains(b['status'] as String? ?? ''))
        .toList();
    list.sort((a, b) {
      final pa = _statusPriority(a['status'] as String? ?? '');
      final pb = _statusPriority(b['status'] as String? ?? '');
      if (pa != pb) return pb.compareTo(pa);
      return ((b['created_at'] as String?) ?? '')
          .compareTo((a['created_at'] as String?) ?? '');
    });
    return list;
  }

  List<dynamic> get _historyBookings {
    final list = _bookings
        .where((b) => !_activeStatuses.contains(b['status'] as String? ?? ''))
        .toList();
    list.sort((a, b) => ((b['created_at'] as String?) ?? '')
        .compareTo((a['created_at'] as String?) ?? ''));
    return list;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchBookings();
    _refreshSub = BookingEvents.onRefresh.listen((_) => _fetchBookings());
  }

  @override
  void dispose() {
    _refreshSub?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchBookings() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
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
    final active = _activeBookings;
    final history = _historyBookings;

    return Scaffold(
      backgroundColor: const Color(0xFFF7FAF5),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: const Color(0xFF163300),
        elevation: 0,
        title: Text("My Bookings",
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.white)),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _fetchBookings),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 2,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          labelStyle:
              const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          tabs: [
            Tab(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Text("Active"),
                if (active.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3A9010).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text("${active.length}",
                        style: const TextStyle(fontSize: 11)),
                  ),
                ],
              ]),
            ),
            Tab(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Text("History"),
                if (history.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text("${history.length}",
                        style: const TextStyle(
                            fontSize: 11, color: const Color(0xFF767773))),
                  ),
                ],
              ]),
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: const Color(0xFF3A9010)))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildActiveTab(active),
                _buildHistoryTab(history),
              ],
            ),
    );
  }

  Widget _buildActiveTab(List<dynamic> bookings) {
    if (bookings.isEmpty) {
      return const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.event_busy_rounded,
              color: const Color(0xFFE8EDE6), size: 48),
          SizedBox(height: 12),
          Text("No active bookings",
              style: TextStyle(color: const Color(0xFF767773), fontSize: 14)),
          SizedBox(height: 6),
          Text("Start a new booking from the home screen",
              style: TextStyle(color: const Color(0xFFB0B5AE), fontSize: 12)),
        ]),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: bookings.length,
      itemBuilder: (_, i) {
        if (i == 0) return _buildHeroCard(bookings[i] as Map<String, dynamic>);
        return _buildMutedCard(bookings[i] as Map<String, dynamic>);
      },
    );
  }

  Widget _buildHistoryTab(List<dynamic> bookings) {
    if (bookings.isEmpty) {
      return const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.history_rounded, color: const Color(0xFFE8EDE6), size: 48),
          SizedBox(height: 12),
          Text("No past bookings",
              style: TextStyle(color: const Color(0xFF767773), fontSize: 14)),
        ]),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: bookings.length,
      itemBuilder: (_, i) =>
          _buildHistoryCard(bookings[i] as Map<String, dynamic>),
    );
  }

  // ── Hero card for the topmost active booking ──────────────────────────────
  Widget _buildHeroCard(Map<String, dynamic> b) {
    final status = b['status'] as String? ?? '';
    final color = _statusColor(status);
    final scheduledRaw = b['scheduled_time'] as String?;
    final scheduled = scheduledRaw != null && scheduledRaw.length >= 16
        ? scheduledRaw.substring(0, 16).replaceAll('T', ' ')
        : scheduledRaw ?? 'TBD';

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => ChatScreen(bookingId: b['booking_id'])),
      ).then((_) => _fetchBookings()),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.5), width: 1.5),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: Icon(_statusIcon(status), color: color, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(
                    b['service_type'] as String? ?? 'Service',
                    style: const TextStyle(
                        color: const Color(0xFF21231D),
                        fontSize: 17,
                        fontWeight: FontWeight.bold),
                  ),
                  Text(
                    b['provider_name'] as String? ?? 'Finding provider...',
                    style:
                        const TextStyle(color: Color(0xFF767773), fontSize: 13),
                  ),
                ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withValues(alpha: 0.3)),
                ),
                child: Text(_statusLabel(status),
                    style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.bold)),
              ),
              if (b['final_price'] != null &&
                  (b['final_price'] as num) > 0) ...[
                const SizedBox(height: 4),
                Text("Rs. ${b['final_price']}",
                    style: const TextStyle(
                        color: const Color(0xFF3A9010),
                        fontWeight: FontWeight.bold,
                        fontSize: 13)),
              ],
            ]),
          ]),
          const SizedBox(height: 16),
          _buildProgressBar(status, color),
          const SizedBox(height: 12),
          Row(children: [
            const Icon(Icons.schedule_rounded,
                size: 13, color: Color(0xFFB0B5AE)),
            const SizedBox(width: 5),
            Text(scheduled,
                style: const TextStyle(color: Color(0xFF767773), fontSize: 12)),
            const Spacer(),
            Text(
              "Tap to open →",
              style: TextStyle(
                  color: color.withValues(alpha: 0.7),
                  fontSize: 11,
                  fontWeight: FontWeight.w600),
            ),
          ]),
        ]),
      ),
    );
  }

  // ── Muted card for secondary active bookings ──────────────────────────────
  Widget _buildMutedCard(Map<String, dynamic> b) {
    final status = b['status'] as String? ?? '';
    final color = _statusColor(status);
    final scheduledRaw = b['scheduled_time'] as String?;
    final scheduled = scheduledRaw != null && scheduledRaw.length >= 16
        ? scheduledRaw.substring(0, 16).replaceAll('T', ' ')
        : scheduledRaw ?? 'TBD';

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => ChatScreen(bookingId: b['booking_id'])),
      ).then((_) => _fetchBookings()),
      child: Opacity(
        opacity: 0.65,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE8EDE6)),
          ),
          child: Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: Icon(_statusIcon(status), color: color, size: 16),
            ),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(
                    b['service_type'] as String? ?? 'Service',
                    style: const TextStyle(
                        color: const Color(0xFF21231D),
                        fontSize: 14,
                        fontWeight: FontWeight.w600),
                  ),
                  Text(scheduled,
                      style: const TextStyle(
                          color: const Color(0xFF767773), fontSize: 11)),
                ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: Text(_statusLabel(status),
                  style: TextStyle(
                      color: color, fontSize: 10, fontWeight: FontWeight.bold)),
            ),
          ]),
        ),
      ),
    );
  }

  // ── History card ──────────────────────────────────────────────────────────
  Widget _buildHistoryCard(Map<String, dynamic> b) {
    final status = b['status'] as String? ?? '';
    final isCancelled = status.contains('CANCELLED');
    final color = isCancelled ? Colors.redAccent : Colors.blueAccent;
    final scheduledRaw = b['scheduled_time'] as String?;
    final scheduled = scheduledRaw != null && scheduledRaw.length >= 16
        ? scheduledRaw.substring(0, 16).replaceAll('T', ' ')
        : scheduledRaw ?? 'TBD';

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => ChatScreen(bookingId: b['booking_id'])),
      ).then((_) => _fetchBookings()),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE8EDE6)),
        ),
        child: Row(children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: Icon(
              isCancelled ? Icons.cancel_outlined : Icons.check_circle_rounded,
              color: color,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(
                  b['service_type'] as String? ?? 'Service',
                  style: const TextStyle(
                      color: Color(0xFF21231D),
                      fontSize: 14,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  "${b['provider_name'] ?? 'Unknown'} · $scheduled",
                  style: const TextStyle(
                      color: const Color(0xFF767773), fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            if (!isCancelled && b['final_price'] != null)
              Text("Rs. ${b['final_price']}",
                  style: const TextStyle(
                      color: Color(0xFF3A9010),
                      fontWeight: FontWeight.bold,
                      fontSize: 13)),
            const SizedBox(height: 3),
            Text(
              isCancelled ? "Cancelled" : "Completed",
              style: TextStyle(
                  color: color.withValues(alpha: 0.7),
                  fontSize: 11,
                  fontWeight: FontWeight.bold),
            ),
          ]),
        ]),
      ),
    );
  }

  // ── Progress bar (used in hero card only) ─────────────────────────────────
  Widget _buildProgressBar(String status, Color color) {
    const stages = ['Pending', 'Accepted', 'En Route', 'On Site', 'Done'];
    int active = 0;
    if (status == 'PENDING_PROVIDER') active = 1;
    if (status == 'ACCEPTED') active = 2;
    if (status == 'ARRIVING') active = 2;
    if (status == 'ARRIVED') active = 3;
    if (status == 'IN_PROGRESS') active = 4;
    if (status == 'COMPLETED') active = 5;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(
          children: List.generate(stages.length * 2 - 1, (i) {
        if (i.isOdd) {
          final segIndex = i ~/ 2;
          return Expanded(
            child: Container(
              height: 2,
              color: segIndex < active - 1 ? color : const Color(0xFFE8EDE6),
            ),
          );
        }
        final dotIndex = i ~/ 2;
        final filled = dotIndex < active;
        final current = dotIndex == active - 1;
        return Container(
          width: current ? 12 : 8,
          height: current ? 12 : 8,
          decoration: BoxDecoration(
            color: filled ? color : const Color(0xFFE8EDE6),
            shape: BoxShape.circle,
            boxShadow: current
                ? [
                    BoxShadow(
                        color: color.withValues(alpha: 0.5), blurRadius: 6)
                  ]
                : null,
          ),
        );
      })),
      const SizedBox(height: 5),
      Text(
        stages[active > 0 ? active - 1 : 0],
        style:
            TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    ]);
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'PENDING_PROVIDER':
        return const Color(0xFF3A9010);
      case 'ACCEPTED':
      case 'ARRIVING':
        return const Color(0xFF3A9010);
      case 'ARRIVED':
      case 'IN_PROGRESS':
        return Colors.blueAccent;
      case 'COMPLETED':
        return const Color(0xFF3A9010);
      default:
        return Colors.redAccent;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'PENDING_PROVIDER':
        return Icons.hourglass_top_rounded;
      case 'ACCEPTED':
        return Icons.check_rounded;
      case 'ARRIVING':
        return Icons.directions_bike_rounded;
      case 'ARRIVED':
        return Icons.location_on_rounded;
      case 'IN_PROGRESS':
        return Icons.build_rounded;
      case 'COMPLETED':
        return Icons.check_circle_rounded;
      default:
        return Icons.cancel_outlined;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'PENDING_PROVIDER':
        return 'AWAITING';
      case 'ACCEPTED':
        return 'ACCEPTED';
      case 'ARRIVING':
        return 'EN ROUTE';
      case 'ARRIVED':
        return 'ON SITE';
      case 'IN_PROGRESS':
        return 'IN PROGRESS';
      case 'COMPLETED':
        return 'COMPLETED';
      case 'CANCELLED_PROVIDER':
        return 'DECLINED';
      case 'CANCELLED_CUSTOMER':
        return 'CANCELLED';
      default:
        return status.replaceAll('_', ' ');
    }
  }
}
