import 'package:flutter/material.dart';

/// Displays the A2A negotiation trace as animated chat bubbles:
/// CFP sent → bids streaming in → counter (if any) → deal locked.
class NegotiationWidget extends StatefulWidget {
  final Map<String, dynamic> negotiationTrace;
  final String? contractId;

  const NegotiationWidget({
    super.key,
    required this.negotiationTrace,
    this.contractId,
  });

  @override
  State<NegotiationWidget> createState() => _NegotiationWidgetState();
}

class _NegotiationWidgetState extends State<NegotiationWidget> {
  final List<_NegotiationStep> _visibleSteps = [];
  int _stepIndex = 0;

  @override
  void initState() {
    super.initState();
    _buildSteps();
    _revealNext();
  }

  List<_NegotiationStep> _allSteps = [];

  void _buildSteps() {
    final trace = widget.negotiationTrace;
    final sent = (trace['cfp_sent_to'] as List?)?.cast<String>() ?? [];
    final proposals = (trace['proposals'] as List?) ?? [];
    final counterRound = (trace['counter_round'] as List?) ?? [];
    final reasoning = trace['customer_agent_reasoning'] as String? ?? '';
    final outcome = trace['outcome'] as String? ?? 'no_deal';
    final rounds = trace['rounds'] as int? ?? 1;

    _allSteps = [
      _NegotiationStep(
        icon: Icons.campaign_outlined,
        color: const Color(0xFF6938ef),
        text: 'CFP broadcast to ${sent.length} provider agent${sent.length == 1 ? '' : 's'}',
        isSystem: true,
      ),
      for (final p in proposals)
        _NegotiationStep(
          icon: Icons.handshake_outlined,
          color: const Color(0xFF0070f3),
          text: 'Provider ${_shortId(p['provider'])} bid Rs.${p['price']} — ETA ${p['eta_min']}min, reliability ${((p['confidence'] as num) * 100).round()}%',
          isSystem: false,
        ),
      if (counterRound.isNotEmpty) ...[
        _NegotiationStep(
          icon: Icons.swap_horiz,
          color: const Color(0xFFf59e0b),
          text: 'Customer Agent countering top ${counterRound.length} provider${counterRound.length == 1 ? '' : 's'}...',
          isSystem: true,
        ),
        for (final c in counterRound)
          _NegotiationStep(
            icon: c['accepted'] == true ? Icons.check_circle_outline : Icons.cancel_outlined,
            color: c['accepted'] == true ? const Color(0xFF079455) : const Color(0xFFda2721),
            text: c['accepted'] == true
                ? 'Provider ${_shortId(c['provider'])} accepted counter — Rs.${c['response_price']}'
                : 'Provider ${_shortId(c['provider'])} rejected counter (Rs.${c['response_price']} floor)',
            isSystem: false,
          ),
      ],
      _NegotiationStep(
        icon: Icons.psychology_outlined,
        color: const Color(0xFF6938ef),
        text: reasoning,
        isSystem: true,
      ),
      _NegotiationStep(
        icon: outcome == 'deal_locked' ? Icons.lock_outline : Icons.error_outline,
        color: outcome == 'deal_locked' ? const Color(0xFF079455) : const Color(0xFFda2721),
        text: outcome == 'deal_locked'
            ? 'Deal locked in $rounds round${rounds == 1 ? '' : 's'}${widget.contractId != null ? " · ${widget.contractId}" : ""}'
            : 'No deal reached — falling back to direct booking',
        isSystem: true,
      ),
    ];
  }

  Future<void> _revealNext() async {
    while (_stepIndex < _allSteps.length) {
      await Future.delayed(const Duration(milliseconds: 420));
      if (!mounted) return;
      setState(() => _visibleSteps.add(_allSteps[_stepIndex++]));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Icon(Icons.bolt, size: 14, color: Color(0xFF6938ef)),
              SizedBox(width: 4),
              Text(
                'A2A Negotiation',
                style: TextStyle(
                  fontFamily: 'Satoshi Variable',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6938ef),
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
        ..._visibleSteps.map((s) => _StepBubble(step: s)),
      ],
    );
  }

  static String _shortId(dynamic id) {
    final s = id.toString();
    return s.length > 8 ? '…${s.substring(s.length - 6)}' : s;
  }
}

class _NegotiationStep {
  final IconData icon;
  final Color color;
  final String text;
  final bool isSystem;
  const _NegotiationStep({
    required this.icon,
    required this.color,
    required this.text,
    required this.isSystem,
  });
}

class _StepBubble extends StatelessWidget {
  final _NegotiationStep step;
  const _StepBubble({required this.step});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            margin: const EdgeInsets.only(top: 1, right: 8),
            decoration: BoxDecoration(
              color: step.color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(step.icon, size: 12, color: step.color),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: step.isSystem
                    ? step.color.withValues(alpha: 0.06)
                    : const Color(0xFFf8fafc),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: step.color.withValues(alpha: 0.2)),
              ),
              child: Text(
                step.text,
                style: TextStyle(
                  fontFamily: 'Satoshi Variable',
                  fontSize: 12,
                  color: step.isSystem ? step.color : const Color(0xFF121926),
                  fontWeight: step.isSystem ? FontWeight.w500 : FontWeight.w400,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
