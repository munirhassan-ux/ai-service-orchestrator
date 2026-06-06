import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import 'dispute_detail_screen.dart';

class DisputeCenterScreen extends StatefulWidget {
  const DisputeCenterScreen({super.key});

  @override
  State<DisputeCenterScreen> createState() => _DisputeCenterScreenState();
}

class _DisputeCenterScreenState extends State<DisputeCenterScreen> {
  List<dynamic> _disputes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await ApiService.get('/disputes');
      setState(() {
        _disputes = (data as List?) ?? [];
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  static const _statusColor = {
    'proposed':  Color(0xFF6938ef),
    'accepted':  Color(0xFF079455),
    'rejected':  Color(0xFFda2721),
    'escalated': Color(0xFFf59e0b),
    'resolved':  Color(0xFF079455),
  };

  static const _statusLabel = {
    'proposed':  'Proposed',
    'accepted':  'Accepted',
    'rejected':  'Rejected',
    'escalated': 'Escalated',
    'resolved':  'Resolved',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFf8fafc),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Dispute Center',
          style: TextStyle(
            fontFamily: 'Satoshi Variable',
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Color(0xFF121926),
          ),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF121926)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFFcdd5df)),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF6938ef)))
          : _disputes.isEmpty
              ? _buildEmpty()
              : RefreshIndicator(
                  onRefresh: _load,
                  color: const Color(0xFF6938ef),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _disputes.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _buildCard(_disputes[i]),
                  ),
                ),
    );
  }

  Widget _buildCard(dynamic dispute) {
    final status = dispute['status'] as String? ?? 'proposed';
    final type   = dispute['type'] as String? ?? '';
    final action = dispute['proposed_action'] as String? ?? '';
    final color  = _statusColor[status] ?? const Color(0xFF697586);
    final label  = _statusLabel[status] ?? status;
    final conf   = ((dispute['confidence'] as num?) ?? 0) * 100;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => DisputeDetailScreen(disputeId: dispute['dispute_id'])),
      ).then((_) => _load()),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFcdd5df)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_formatType(type)} · ${dispute['booking_id']}',
                    style: const TextStyle(
                      fontFamily: 'Satoshi Variable',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF121926),
                    ),
                  ),
                ),
                _statusChip(label, color),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              action.isNotEmpty ? 'Proposed: $action' : 'Awaiting resolution',
              style: const TextStyle(
                fontFamily: 'Satoshi Variable',
                fontSize: 12,
                color: Color(0xFF697586),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.psychology_outlined, size: 12, color: Color(0xFF697586)),
                const SizedBox(width: 4),
                Text(
                  'AI confidence: ${conf.toStringAsFixed(0)}%',
                  style: const TextStyle(
                    fontFamily: 'Satoshi Variable',
                    fontSize: 11,
                    color: Color(0xFF697586),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Satoshi Variable',
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.balance_outlined, size: 48, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          const Text(
            'No disputes raised.',
            style: TextStyle(
              fontFamily: 'Satoshi Variable',
              fontSize: 14,
              color: Color(0xFF697586),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatType(String t) =>
      t.split('_').map((w) => w[0].toUpperCase() + w.substring(1)).join(' ');
}
