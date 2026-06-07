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
    'CANCELLED_TIMEOUT',
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

  // Intermediate bookings in a reassignment chain (those with reassigned_to set)
  // are never displayed — only the chain tip (latest booking) is shown.
  static bool _isChainTip(dynamic b) => b['reassigned_to'] == null;

  List<dynamic> get _activeBookings {
    final list = _bookings
        .where((b) =>
            _isChainTip(b) &&
            _activeStatuses.contains(b['status'] as String? ?? ''))
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

  List<dynamic> get _scheduledBookings {
    final list = _bookings
        .where((b) => _isChainTip(b) && b['status'] == 'SCHEDULED')
        .toList();
    list.sort((a, b) => ((a['scheduled_time'] as String?) ?? '')
        .compareTo((b['scheduled_time'] as String?) ?? ''));
    return list;
  }

  List<dynamic> get _historyBookings {
    final list = _bookings
        .where((b) =>
            _isChainTip(b) &&
            b['status'] != 'SCHEDULED' &&
            !_activeStatuses.contains(b['status'] as String? ?? ''))
        .toList();
    list.sort((a, b) => ((b['created_at'] as String?) ?? '')
        .compareTo((a['created_at'] as String?) ?? ''));
    return list;
  }

  String _formatScheduledTime(String? raw) {
    if (raw == null || raw.isEmpty) return 'TBD';
    try {
      final dt = DateTime.parse(raw).toLocal();
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      final ampm = dt.hour >= 12 ? 'PM' : 'AM';
      final min = dt.minute.toString().padLeft(2, '0');
      return '${days[dt.weekday - 1]}, ${dt.day} ${months[dt.month - 1]} · $h:$min $ampm';
    } catch (_) {
      return raw;
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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
    final scheduled = _scheduledBookings;
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
                Builder(builder: (ctx) {
                  final hasSession = ActiveSessionService.hasActive &&
                      ActiveSessionService.bookingId == null;
                  final count = active.length + (hasSession ? 1 : 0);
                  if (count == 0) return const SizedBox.shrink();
                  return Row(children: [
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3A9010).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text("$count",
                          style: const TextStyle(fontSize: 11)),
                    ),
                  ]);
                }),
              ]),
            ),
            Tab(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Text("Upcoming"),
                if (scheduled.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1565C0).withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text("${scheduled.length}",
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
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                _buildUpcomingTab(scheduled),
                _buildHistoryTab(history),
              ],
            ),
    );
  }

  Widget _buildActiveTab(List<dynamic> bookings) {
    // Show session card only when no API booking exists yet.
    // Once a provider is selected, the backend creates a PENDING_PROVIDER
    // booking immediately — that card takes over; session card hides.
    final hasSession = ActiveSessionService.hasActive &&
        ActiveSessionService.bookingId == null &&
        ActiveSessionService.sessionId != null &&
        bookings.isEmpty;

    if (bookings.isEmpty && !hasSession) {
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

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        if (hasSession) _buildSessionCard(),
        ...bookings.asMap().entries.map((e) {
          final b = e.value as Map<String, dynamic>;
          return e.key == 0 && !hasSession
              ? _buildHeroCard(b)
              : _buildMutedCard(b);
        }),
      ],
    );
  }

  Widget _buildSessionCard() {
    final msgs = ActiveSessionService.messages;
    final firstPrompt = msgs
        .where((m) => m.isUser && m.text.isNotEmpty)
        .map((m) => m.text)
        .firstOrNull;
    final hasProviders = msgs.any((m) => m.type == 'quote');

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatScreen(
                sessionId: ActiveSessionService.sessionId),
          ),
        ).then((_) => _fetchBookings());
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: const Color(0xFF3A9010).withValues(alpha: 0.35),
              width: 1.5),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF3A9010).withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF3A9010).withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.chat_bubble_rounded,
                color: Color(0xFF3A9010), size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(
                      hasProviders ? 'Providers Found' : 'Finding Providers...',
                      style: const TextStyle(
                          color: Color(0xFF21231D),
                          fontSize: 14,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    if (!hasProviders)
                      const SizedBox(
                          width: 11,
                          height: 11,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF3A9010))),
                  ]),
                  const SizedBox(height: 3),
                  Text(
                    firstPrompt ?? 'Chat in progress...',
                    style: const TextStyle(
                        color: Color(0xFF767773),
                        fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ]),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF3A9010),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text('Resume',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold)),
          ),
        ]),
      ),
    );
  }

  Widget _buildUpcomingTab(List<dynamic> bookings) {
    if (bookings.isEmpty) {
      return const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.calendar_today_rounded,
              color: Color(0xFFE8EDE6), size: 48),
          SizedBox(height: 12),
          Text("No upcoming bookings",
              style: TextStyle(color: Color(0xFF767773), fontSize: 14)),
          SizedBox(height: 6),
          Text("Scheduled bookings will appear here",
              style: TextStyle(color: Color(0xFFB0B5AE), fontSize: 12)),
        ]),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: bookings.length,
      itemBuilder: (_, i) =>
          _buildScheduledCard(bookings[i] as Map<String, dynamic>),
    );
  }

  Widget _buildScheduledCard(Map<String, dynamic> b) {
    const blue = Color(0xFF1565C0);
    const blueBg = Color(0xFFE8F0FE);

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => ChatScreen(bookingId: b['booking_id'])),
      ).then((_) => _fetchBookings()),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: blue.withValues(alpha: 0.35), width: 1.5),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration:
                  const BoxDecoration(color: blueBg, shape: BoxShape.circle),
              child: const Icon(Icons.calendar_today_rounded,
                  color: blue, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child:
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  b['service_type'] as String? ?? 'Service',
                  style: const TextStyle(
                      color: Color(0xFF21231D),
                      fontSize: 15,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 3),
                Text(
                  _formatScheduledTime(b['scheduled_time'] as String?),
                  style: const TextStyle(
                      color: blue,
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                ),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: blueBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: blue.withValues(alpha: 0.3)),
                ),
                child: const Text("SCHEDULED",
                    style: TextStyle(
                        color: blue,
                        fontSize: 11,
                        fontWeight: FontWeight.bold)),
              ),
              if (b['final_price'] != null &&
                  (b['final_price'] as num) > 0) ...[
                const SizedBox(height: 4),
                Text("Rs. ${b['final_price']}",
                    style: const TextStyle(
                        color: Color(0xFF3A9010),
                        fontWeight: FontWeight.bold,
                        fontSize: 13)),
              ],
            ]),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            const Icon(Icons.location_on_rounded,
                size: 13, color: Color(0xFFB0B5AE)),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                b['location'] as String? ?? '',
                style: const TextStyle(
                    color: Color(0xFF767773), fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text("Tap to view →",
                style: TextStyle(
                    color: blue.withValues(alpha: 0.7),
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ]),
          if ((b['time_note'] as String?) != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFFCC02).withValues(alpha: 0.6)),
              ),
              child: Row(children: [
                const Icon(Icons.schedule_rounded, size: 12, color: Color(0xFFE65100)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    b['time_note'] as String,
                    style: const TextStyle(
                        color: Color(0xFFE65100), fontSize: 11),
                  ),
                ),
              ]),
            ),
          ],
        ]),
      ),
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
