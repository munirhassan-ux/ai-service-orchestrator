import 'package:flutter/material.dart';

/// Displays provider search as animated steps — consumer-friendly, no technical jargon.
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
  final List<_Step> _visibleSteps = [];
  int _stepIndex = 0;
  List<_Step> _allSteps = [];

  @override
  void initState() {
    super.initState();
    _buildSteps();
    _revealNext();
  }

  void _buildSteps() {
    final trace = widget.negotiationTrace;
    final sent = (trace['cfp_sent_to'] as List?)?.cast<String>() ?? [];
    final proposals = (trace['proposals'] as List?) ?? [];
    final counterRound = (trace['counter_round'] as List?) ?? [];
    final outcome = trace['outcome'] as String? ?? 'no_deal';
    final rounds = trace['rounds'] as int? ?? 1;

    _allSteps = [
      _Step(
        icon: Icons.search_rounded,
        color: const Color(0xFF6938ef),
        label: 'Searching nearby',
        detail: 'Checking ${sent.length} providers in your area...',
        isHighlight: false,
      ),
      for (final p in proposals)
        _Step(
          icon: Icons.local_offer_outlined,
          color: const Color(0xFF0070f3),
          label: 'Quote from ${p['provider_name'] ?? 'Provider'}',
          detail:
              'Rs. ${p['price']} · arrives in ${p['eta_min']} min · ${((p['confidence'] as num) * 100).round()}% reliable',
          isHighlight: false,
        ),
      if (counterRound.isNotEmpty) ...[
        _Step(
          icon: Icons.trending_down_rounded,
          color: const Color(0xFFf59e0b),
          label: 'Getting you a better deal',
          detail: 'Negotiating price with top options...',
          isHighlight: false,
        ),
        for (final c in counterRound)
          _Step(
            icon: c['accepted'] == true
                ? Icons.check_circle_outline
                : Icons.info_outline,
            color: c['accepted'] == true
                ? const Color(0xFF079455)
                : const Color(0xFF888E86),
            label: c['accepted'] == true ? 'Price reduced' : 'Best available',
            detail: c['accepted'] == true
                ? '${c['provider_name'] ?? 'Provider'} agreed · Rs. ${c['response_price']}'
                : '${c['provider_name'] ?? 'Provider'}\'s lowest: Rs. ${c['response_price']}',
            isHighlight: false,
          ),
      ],
      _Step(
        icon: outcome == 'deal_locked'
            ? Icons.verified_rounded
            : Icons.refresh_rounded,
        color: outcome == 'deal_locked'
            ? const Color(0xFF079455)
            : const Color(0xFFda2721),
        label: outcome == 'deal_locked'
            ? 'Best match found!'
            : 'Trying another option...',
        detail: outcome == 'deal_locked'
            ? 'Selected in $rounds round${rounds == 1 ? '' : 's'} based on price, speed & reliability'
            : 'Switching to direct booking',
        isHighlight: true,
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
          padding: EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Icon(Icons.auto_awesome_rounded, size: 14, color: Color(0xFF6938ef)),
              SizedBox(width: 5),
              Text(
                'Finding Your Provider',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6938ef),
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        ),
        ..._visibleSteps.map((s) => _StepBubble(step: s)),
      ],
    );
  }
}

class _Step {
  final IconData icon;
  final Color color;
  final String label;
  final String detail;
  final bool isHighlight;
  const _Step({
    required this.icon,
    required this.color,
    required this.label,
    required this.detail,
    required this.isHighlight,
  });
}

class _StepBubble extends StatelessWidget {
  final _Step step;
  const _StepBubble({required this.step});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            margin: const EdgeInsets.only(top: 1, right: 8),
            decoration: BoxDecoration(
              color: step.color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(step.icon, size: 13, color: step.color),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
              decoration: BoxDecoration(
                color: step.isHighlight
                    ? step.color.withValues(alpha: 0.08)
                    : const Color(0xFFf8fafc),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: step.color.withValues(alpha: step.isHighlight ? 0.3 : 0.15),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    step.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: step.isHighlight ? step.color : const Color(0xFF3E3F3B),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    step.detail,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF767773),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
