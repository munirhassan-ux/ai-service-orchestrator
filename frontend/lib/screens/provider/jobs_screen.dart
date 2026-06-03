import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../services/api_service.dart';
import '../../services/booking_events.dart';
import 'chat_screen.dart';

class JobsScreen extends StatefulWidget {
  const JobsScreen({super.key});

  @override
  State<JobsScreen> createState() => _JobsScreenState();
}

class _JobsScreenState extends State<JobsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  StreamSubscription<void>? _refreshSub;
  List<dynamic> _jobs = [];
  bool _isLoading = true;

  static const _activeStatuses = {
    'PENDING_PROVIDER',
    'ACCEPTED',
    'ARRIVING',
    'ARRIVED',
    'IN_PROGRESS'
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

  // Intermediate bookings in a reassignment chain (reassigned_to is set)
  // are never shown — the provider already declined them.
  static bool _isChainTip(dynamic j) => j['reassigned_to'] == null;

  List<dynamic> get _activeJobs {
    final list = _jobs
        .where((j) =>
            _isChainTip(j) &&
            _activeStatuses.contains(j['status'] as String? ?? ''))
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

  List<dynamic> get _doneJobs {
    final list = _jobs
        .where((j) =>
            _isChainTip(j) &&
            !_activeStatuses.contains(j['status'] as String? ?? ''))
        .toList();
    list.sort((a, b) => ((b['created_at'] as String?) ?? '')
        .compareTo((a['created_at'] as String?) ?? ''));
    return list;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchJobs();
    _refreshSub = BookingEvents.onRefresh.listen((_) => _fetchJobs());
  }

  @override
  void dispose() {
    _refreshSub?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchJobs() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final res = await ApiService.get('bookings');
      if (mounted) {
        final jobs = res is List ? List<dynamic>.from(res) : <dynamic>[];
        setState(() {
          _jobs = jobs;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeJobs = _activeJobs;
    final doneJobs = _doneJobs;

    return Scaffold(
      backgroundColor: const Color(0xFFF7FAF5),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: const Color(0xFF163300),
        elevation: 0,
        title: Text("My Jobs",
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.white)),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh_rounded, color: Colors.white),
              onPressed: _fetchJobs),
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
                if (activeJobs.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                        color: const Color(0xFF3A9010).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10)),
                    child: Text("${activeJobs.length}",
                        style: const TextStyle(fontSize: 11)),
                  ),
                ],
              ]),
            ),
            Tab(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Text("History"),
                if (doneJobs.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10)),
                    child: Text("${doneJobs.length}",
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
                _buildJobList(activeJobs,
                    emptyLabel: "No active jobs", heroFirst: true),
                _buildJobList(doneJobs, emptyLabel: "No completed jobs yet"),
              ],
            ),
    );
  }

  Widget _buildJobList(List<dynamic> jobs,
      {required String emptyLabel, bool heroFirst = false}) {
    if (jobs.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.work_off_rounded,
              color: const Color(0xFFE8EDE6), size: 48),
          const SizedBox(height: 12),
          Text(emptyLabel,
              style: const TextStyle(
                  color: const Color(0xFF767773), fontSize: 14)),
        ]),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: jobs.length,
      itemBuilder: (_, i) {
        final j = jobs[i] as Map<String, dynamic>;
        if (heroFirst && i == 0) return _buildHeroJobCard(j);
        if (heroFirst && i > 0) return _buildMutedJobCard(j);
        return _buildJobCard(j);
      },
    );
  }

  // Hero card — topmost active job, prominent
  Widget _buildHeroJobCard(Map<String, dynamic> j) {
    final status = j['status'] as String? ?? '';
    final color = _jobColor(status);
    final icon = _jobIcon(status);
    final scheduledRaw = j['scheduled_time'] as String?;
    final scheduled = scheduledRaw != null && scheduledRaw.length >= 16
        ? scheduledRaw.substring(0, 16).replaceAll('T', ' ')
        : scheduledRaw ?? '';

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => ProviderChatScreen(bookingId: j['booking_id'])),
      ).then((_) => _fetchJobs()),
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
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.13), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 19),
            ),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(
                    "${j['service_type']} — ${j['location']}",
                    style: const TextStyle(
                        color: const Color(0xFF21231D),
                        fontSize: 16,
                        fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    scheduled,
                    style:
                        const TextStyle(color: Color(0xFF767773), fontSize: 12),
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
              if (j['final_price'] != null) ...[
                const SizedBox(height: 4),
                Text("Rs. ${j['final_price']}",
                    style: const TextStyle(
                        color: const Color(0xFF3A9010),
                        fontWeight: FontWeight.bold,
                        fontSize: 13)),
              ],
            ]),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            const Icon(Icons.person_rounded,
                size: 13, color: Color(0xFFB0B5AE)),
            const SizedBox(width: 5),
            Text(
              j['customer_id'] as String? ?? '',
              style: const TextStyle(color: Color(0xFF767773), fontSize: 12),
            ),
            const Spacer(),
            Text("Tap to open →",
                style: TextStyle(
                    color: color.withValues(alpha: 0.7),
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ]),
        ]),
      ),
    );
  }

  // Muted card — secondary active jobs
  Widget _buildMutedJobCard(Map<String, dynamic> j) {
    final status = j['status'] as String? ?? '';
    final color = _jobColor(status);
    final icon = _jobIcon(status);
    final scheduledRaw = j['scheduled_time'] as String?;
    final scheduled = scheduledRaw != null && scheduledRaw.length >= 16
        ? scheduledRaw.substring(0, 16).replaceAll('T', ' ')
        : scheduledRaw ?? '';

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => ProviderChatScreen(bookingId: j['booking_id'])),
      ).then((_) => _fetchJobs()),
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
              child: Icon(icon, color: color, size: 17),
            ),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(
                    "${j['service_type']} — ${j['location']}",
                    style: const TextStyle(
                        color: const Color(0xFF21231D),
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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

  // Standard card — history tab
  Widget _buildJobCard(Map<String, dynamic> j) {
    final status = j['status'] as String? ?? 'UNKNOWN';
    final color = _jobColor(status);
    final icon = _jobIcon(status);
    final scheduledRaw = j['scheduled_time'] as String?;
    final scheduled = scheduledRaw != null && scheduledRaw.length >= 16
        ? scheduledRaw.substring(0, 16).replaceAll('T', ' ')
        : scheduledRaw ?? '';

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => ProviderChatScreen(bookingId: j['booking_id'])),
      ).then((_) => _fetchJobs()),
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
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(
                  "${j['service_type']} — ${j['location']}",
                  style: const TextStyle(
                      color: Color(0xFF21231D),
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(scheduled,
                    style: const TextStyle(
                        color: const Color(0xFF767773), fontSize: 11)),
              ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            if (j['final_price'] != null)
              Text("Rs. ${j['final_price']}",
                  style: const TextStyle(
                      color: Color(0xFF3A9010),
                      fontWeight: FontWeight.bold,
                      fontSize: 12)),
            const SizedBox(height: 3),
            Text(_statusLabel(status),
                style: TextStyle(
                    color: color.withValues(alpha: 0.7),
                    fontSize: 10,
                    fontWeight: FontWeight.bold)),
          ]),
        ]),
      ),
    );
  }

  Color _jobColor(String status) {
    if (status == 'PENDING_PROVIDER') return const Color(0xFF3A9010);
    if (status == 'COMPLETED') return Colors.blueAccent;
    if (status.contains('CANCELLED')) return Colors.redAccent;
    return const Color(0xFF3A9010);
  }

  IconData _jobIcon(String status) {
    switch (status) {
      case 'PENDING_PROVIDER':
        return Icons.notification_important_rounded;
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
        return Icons.cancel_rounded;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'PENDING_PROVIDER':
        return 'NEW JOB';
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
