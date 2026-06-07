import 'package:flutter/material.dart';

/// Displays provider search as animated steps — consumer-friendly, no technical jargon.
/// Shows all bid evaluations: winner highlighted, runners-up greyed with rejection reason,
/// declined providers shown compactly. Ends with a deal recap card.
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

class _NegotiationWidgetState extends State<NegotiationWidget>
    with AutomaticKeepAliveClientMixin {
  final List<_Step> _visibleSteps = [];
  int _stepIndex = 0;
  List<_Step> _allSteps = [];
  bool _showRecap = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _buildSteps();
    _revealNext();
  }

  void _buildSteps() {
    final trace       = widget.negotiationTrace;
    final evaluations = (trace['bid_evaluations'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final proposals   = (trace['proposals'] as List?) ?? [];
    final counterRound = (trace['counter_round'] as List?) ?? [];
    final outcome     = trace['outcome'] as String? ?? 'no_deal';
    final rounds      = trace['rounds'] as int? ?? 1;

    // Use bid_evaluations if available (richer data), fall back to proposals
    final hasEvals = evaluations.isNotEmpty;

    _allSteps = [
      _Step(
        icon: Icons.search_rounded,
        color: const Color(0xFF6938ef),
        label: 'Searching nearby',
        detail: 'Checking ${hasEvals ? evaluations.length : proposals.length} providers in your area...',
        type: _StepType.normal,
      ),

      if (hasEvals) ...[
        // Winner first
        for (final e in evaluations.where((e) => e['status'] == 'selected'))
          _Step(
            icon: Icons.verified_rounded,
            color: const Color(0xFF079455),
            label: 'Best match: ${e['provider_name'] ?? 'Provider'}',
            detail: 'Rs. ${e['price']} · ${e['eta_min']} min away · ${e['reliability']}% reliable · Score ${((e['utility_score'] as num? ?? 0) * 100).round()}/100',
            type: _StepType.winner,
          ),
        // Runners-up
        for (final e in evaluations.where((e) => e['status'] == 'not_selected'))
          _Step(
            icon: Icons.close_rounded,
            color: const Color(0xFF888E86),
            label: e['provider_name'] ?? 'Provider',
            detail: e['rejection_reason'] ?? 'Not selected',
            type: _StepType.rejected,
          ),
        // Declined
        for (final e in evaluations.where((e) => e['status'] == 'declined'))
          _Step(
            icon: Icons.do_not_disturb_rounded,
            color: const Color(0xFFCCCECA),
            label: e['provider_name'] ?? 'Provider',
            detail: e['rejection_reason'] ?? 'Unavailable',
            type: _StepType.declined,
          ),
      ] else ...[
        // Fallback: proposals without evaluations
        for (final p in proposals)
          _Step(
            icon: Icons.local_offer_outlined,
            color: const Color(0xFF0070f3),
            label: 'Quote from ${p['provider_name'] ?? 'Provider'}',
            detail: 'Rs. ${p['price']} · arrives in ${p['eta_min']} min · ${((p['confidence'] as num) * 100).round()}% reliable',
            type: _StepType.normal,
          ),
      ],

      if (counterRound.isNotEmpty) ...[
        _Step(
          icon: Icons.trending_down_rounded,
          color: const Color(0xFFf59e0b),
          label: 'Negotiating a better deal',
          detail: 'Pushing for lower price...',
          type: _StepType.normal,
        ),
        for (final c in counterRound)
          _Step(
            icon: c['accepted'] == true ? Icons.check_circle_outline : Icons.info_outline,
            color: c['accepted'] == true ? const Color(0xFF079455) : const Color(0xFF888E86),
            label: c['accepted'] == true ? 'Price reduced' : 'Best available',
            detail: c['accepted'] == true
                ? '${c['provider_name'] ?? 'Provider'} agreed · Rs. ${c['response_price']}'
                : '${c['provider_name'] ?? 'Provider'}\'s lowest: Rs. ${c['response_price']}',
            type: _StepType.normal,
          ),
      ],

      _Step(
        icon: outcome == 'deal_locked' ? Icons.lock_rounded : Icons.refresh_rounded,
        color: outcome == 'deal_locked' ? const Color(0xFF079455) : const Color(0xFFda2721),
        label: outcome == 'deal_locked' ? 'Deal locked!' : 'Trying next option...',
        detail: outcome == 'deal_locked'
            ? 'Secured in $rounds round${rounds == 1 ? '' : 's'} · best value, speed & reliability'
            : 'Switching to direct booking',
        type: _StepType.highlight,
      ),
    ];
  }

  Future<void> _revealNext() async {
    while (_stepIndex < _allSteps.length) {
      await Future.delayed(const Duration(milliseconds: 380));
      if (!mounted) return;
      setState(() => _visibleSteps.add(_allSteps[_stepIndex++]));
    }
    // Show recap after all steps revealed
    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted) setState(() => _showRecap = true);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final trace = widget.negotiationTrace;
    final evals = (trace['bid_evaluations'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final winner = evals.where((e) => e['status'] == 'selected').firstOrNull;
    final rounds = trace['rounds'] as int? ?? 1;
    final proposals = (trace['proposals'] as List?) ?? [];
    final totalEvaluated = evals.isNotEmpty ? evals.length : proposals.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 10),
          child: Row(children: [
            Icon(Icons.auto_awesome_rounded, size: 14, color: Color(0xFF6938ef)),
            SizedBox(width: 5),
            Text('Finding Your Provider',
                style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600,
                  color: Color(0xFF6938ef), letterSpacing: 0.4)),
          ]),
        ),

        ..._visibleSteps.map((s) => _StepBubble(step: s)),

        // Deal recap card
        if (_showRecap && winner != null)
          _DealRecapCard(
            providerName: winner['provider_name'] ?? 'Provider',
            price: winner['price'] as int? ?? 0,
            evaluated: totalEvaluated,
            rounds: rounds,
            negotiated: rounds > 1,
          ),
      ],
    );
  }
}

// ── Deal recap card ───────────────────────────────────────────────────────────
class _DealRecapCard extends StatefulWidget {
  final String providerName;
  final int price, evaluated, rounds;
  final bool negotiated;
  const _DealRecapCard({
    required this.providerName, required this.price,
    required this.evaluated, required this.rounds, required this.negotiated,
  });
  @override
  State<_DealRecapCard> createState() => _DealRecapCardState();
}

class _DealRecapCardState extends State<_DealRecapCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [const Color(0xFF6938ef).withValues(alpha: 0.08),
                     const Color(0xFF079455).withValues(alpha: 0.06)],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF6938ef).withValues(alpha: 0.2)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.bolt, size: 13, color: Color(0xFF6938ef)),
            SizedBox(width: 4),
            Text('How your deal was won',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                    color: Color(0xFF6938ef), letterSpacing: 0.4)),
          ]),
          const SizedBox(height: 8),
          _recapRow('Haazir evaluated', '${widget.evaluated} providers'),
          _recapRow('Selected', widget.providerName),
          _recapRow('Final price', 'Rs. ${widget.price}'),
          if (widget.negotiated)
            _recapRow('Rounds', '${widget.rounds} (price negotiated down)'),
          _recapRow('Optimised for', 'reliability · speed · value'),
        ]),
      ),
    );
  }

  Widget _recapRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(children: [
      Text('$label  ', style: const TextStyle(fontSize: 11, color: Color(0xFF767773))),
      Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
          color: Color(0xFF21231D))),
    ]),
  );
}

// ── Step types & bubble widget ────────────────────────────────────────────────
enum _StepType { normal, winner, rejected, declined, highlight }

class _Step {
  final IconData icon;
  final Color color;
  final String label;
  final String detail;
  final _StepType type;
  const _Step({required this.icon, required this.color,
      required this.label, required this.detail, required this.type});
}

class _StepBubble extends StatelessWidget {
  final _Step step;
  const _StepBubble({required this.step});

  @override
  Widget build(BuildContext context) {
    final isRejected = step.type == _StepType.rejected;
    final isDeclined = step.type == _StepType.declined;
    final isWinner   = step.type == _StepType.winner;
    final isHighlight = step.type == _StepType.highlight;
    final isDimmed   = isRejected || isDeclined;

    return Padding(
      padding: EdgeInsets.only(bottom: isDeclined ? 3 : 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: isDeclined ? 18 : 24,
          height: isDeclined ? 18 : 24,
          margin: EdgeInsets.only(top: 1, right: isDeclined ? 6 : 8),
          decoration: BoxDecoration(
            color: step.color.withValues(alpha: isDimmed ? 0.07 : 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(step.icon, size: isDeclined ? 10 : 13,
              color: step.color.withValues(alpha: isDimmed ? 0.5 : 1.0)),
        ),
        Expanded(
          child: Container(
            padding: EdgeInsets.symmetric(
                horizontal: isDeclined ? 8 : 11,
                vertical: isDeclined ? 5 : 8),
            decoration: BoxDecoration(
              color: isWinner
                  ? const Color(0xFF079455).withValues(alpha: 0.07)
                  : isHighlight
                      ? step.color.withValues(alpha: 0.08)
                      : isDimmed
                          ? const Color(0xFFF8F9F7)
                          : const Color(0xFFf8fafc),
              borderRadius: BorderRadius.circular(isDeclined ? 7 : 10),
              border: Border.all(color: step.color.withValues(
                  alpha: isDimmed ? 0.08 : (isWinner || isHighlight ? 0.3 : 0.15))),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(step.label,
                  style: TextStyle(
                    fontSize: isDeclined ? 10 : 12,
                    fontWeight: isWinner || isHighlight ? FontWeight.w700 : FontWeight.w600,
                    color: isDimmed
                        ? const Color(0xFFAAAAAA)
                        : isWinner
                            ? const Color(0xFF079455)
                            : isHighlight
                                ? step.color
                                : const Color(0xFF3E3F3B),
                    decoration: isRejected ? TextDecoration.lineThrough : null,
                    decorationColor: const Color(0xFFAAAAAA),
                  )),
              if (!isDeclined) ...[
                const SizedBox(height: 2),
                Text(step.detail,
                    style: TextStyle(
                      fontSize: 11, height: 1.4,
                      color: isDimmed
                          ? const Color(0xFFBBBBBB)
                          : const Color(0xFF767773),
                      fontStyle: isRejected ? FontStyle.italic : FontStyle.normal,
                    )),
              ],
            ]),
          ),
        ),
      ]),
    );
  }
}
