import 'package:flutter/material.dart';
import '../../services/api_service.dart';

class DisputeDetailScreen extends StatefulWidget {
  final String disputeId;
  const DisputeDetailScreen({super.key, required this.disputeId});

  @override
  State<DisputeDetailScreen> createState() => _DisputeDetailScreenState();
}

class _DisputeDetailScreenState extends State<DisputeDetailScreen> {
  Map<String, dynamic>? _dispute;
  bool _loading = true;
  bool _responding = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await ApiService.get('/dispute/${widget.disputeId}');
      setState(() {
        _dispute = Map<String, dynamic>.from(data as Map);
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _respond(String decision) async {
    setState(() => _responding = true);
    try {
      await ApiService.post('/dispute/${widget.disputeId}/respond', {
        'party': 'customer',
        'decision': decision,
      });
      await _load();
    } catch (_) {
    } finally {
      if (mounted) setState(() => _responding = false);
    }
  }

  static const _typeColor = {
    'overcharge':    Color(0xFFda2721),
    'no_show':       Color(0xFFf59e0b),
    'late_arrival':  Color(0xFF0070f3),
    'poor_quality':  Color(0xFF697586),
    'cancellation':  Color(0xFF6938ef),
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFf8fafc),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          _dispute != null ? _formatType(_dispute!['type'] as String? ?? '') : 'Dispute Detail',
          style: const TextStyle(
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
          : _dispute == null
              ? const Center(child: Text('Dispute not found'))
              : _buildBody(),
    );
  }

  Widget _buildBody() {
    final d = _dispute!;
    final status  = d['status'] as String? ?? 'proposed';
    final type    = d['type'] as String? ?? '';
    final color   = _typeColor[type] ?? const Color(0xFF6938ef);
    final conf    = ((d['confidence'] as num?) ?? 0) * 100;
    final canAct  = status == 'proposed';
    final evidence = d['evidence'] as Map? ?? {};

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader('Agent Reasoning', Icons.psychology_outlined, const Color(0xFF6938ef)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF6938ef).withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF6938ef).withValues(alpha: 0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  d['agent_reasoning'] as String? ?? '',
                  style: const TextStyle(
                    fontFamily: 'Satoshi Variable',
                    fontSize: 13,
                    color: Color(0xFF121926),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.bar_chart, size: 12, color: Color(0xFF697586)),
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

          const SizedBox(height: 20),
          _sectionHeader('Proposed Resolution', Icons.balance_outlined, color),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                Icon(Icons.handshake_outlined, color: color, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    d['proposed_action'] as String? ?? 'Pending',
                    style: TextStyle(
                      fontFamily: 'Satoshi Variable',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),
          _sectionHeader('Evidence Bundle', Icons.folder_outlined, const Color(0xFF697586)),
          const SizedBox(height: 8),
          _evidenceTable(evidence),

          if (canAct) ...[
            const SizedBox(height: 24),
            _actionButtons(),
          ] else ...[
            const SizedBox(height: 16),
            _statusBanner(status),
          ],
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 6),
        Text(
          title,
          style: TextStyle(
            fontFamily: 'Satoshi Variable',
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _evidenceTable(Map evidence) {
    final rows = <MapEntry<String, dynamic>>[];
    for (final key in evidence.keys) {
      final v = evidence[key];
      if (v == null || v is List || v is Map) continue;
      rows.add(MapEntry(key.toString(), v));
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFcdd5df)),
      ),
      child: Column(
        children: rows.asMap().entries.map((e) {
          final isLast = e.key == rows.length - 1;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              border: isLast
                  ? null
                  : const Border(bottom: BorderSide(color: Color(0xFFf1f5f9))),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 4,
                  child: Text(
                    e.value.key.replaceAll('_', ' '),
                    style: const TextStyle(
                      fontFamily: 'Satoshi Variable',
                      fontSize: 12,
                      color: Color(0xFF697586),
                    ),
                  ),
                ),
                Expanded(
                  flex: 5,
                  child: Text(
                    '${e.value.value}',
                    style: const TextStyle(
                      fontFamily: 'Satoshi Variable',
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF121926),
                    ),
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _actionButtons() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _responding ? null : () => _respond('reject'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFda2721),
              side: const BorderSide(color: Color(0xFFda2721)),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text(
              'Reject — Escalate',
              style: TextStyle(fontFamily: 'Satoshi Variable', fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton(
            onPressed: _responding ? null : () => _respond('accept'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF079455),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: _responding
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text(
                    'Accept Resolution',
                    style: TextStyle(fontFamily: 'Satoshi Variable', fontWeight: FontWeight.w600),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _statusBanner(String status) {
    final color = status == 'resolved' || status == 'accepted'
        ? const Color(0xFF079455)
        : status == 'escalated'
            ? const Color(0xFFf59e0b)
            : const Color(0xFF697586);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: color, size: 16),
          const SizedBox(width: 8),
          Text(
            _statusMessage(status),
            style: TextStyle(
              fontFamily: 'Satoshi Variable',
              fontSize: 13,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  static String _statusMessage(String status) {
    switch (status) {
      case 'resolved': return 'This dispute has been resolved.';
      case 'accepted': return 'Resolution accepted by both parties.';
      case 'escalated': return 'Escalated for human review.';
      case 'rejected': return 'Resolution rejected — escalating to human review.';
      default: return 'Status: $status';
    }
  }

  static String _formatType(String t) =>
      t.split('_').map((w) => w.isNotEmpty ? w[0].toUpperCase() + w.substring(1) : '').join(' ');
}
