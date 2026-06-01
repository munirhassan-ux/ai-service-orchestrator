import 'dart:async';
import 'package:flutter/material.dart';

// ── CHIP ROW ────────────────────────────────────────────────────────────
class ChipRow extends StatelessWidget {
  final List<String> chips;
  final Function(String) onTap;
  final bool disabled;
  const ChipRow({super.key, required this.chips, required this.onTap, this.disabled = false});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: chips
            .map((chip) => GestureDetector(
                  onTap: disabled ? null : () => onTap(chip),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      color: disabled ? const Color(0xFFF5F5F5) : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: disabled
                              ? const Color(0xFFCCCCCC)
                              : const Color(0xFF3A9010).withValues(alpha: 0.5)),
                    ),
                    child: Text(chip,
                        style: TextStyle(
                            color: disabled
                                ? const Color(0xFFAAAAAA)
                                : const Color(0xFF3A9010),
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                  ),
                ))
            .toList(),
      ),
    );
  }
}

// ── TYPING INDICATOR ────────────────────────────────────────────────────
class ThinkingBubble extends StatefulWidget {
  final List<String>? steps;
  const ThinkingBubble({super.key, this.steps});
  @override
  State<ThinkingBubble> createState() => _ThinkingBubbleState();
}

class _ThinkingBubbleState extends State<ThinkingBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late List<Animation<double>> _dots;
  int _visibleSteps = 0;
  Timer? _stepTimer;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat();
    _dots = List.generate(
        3,
        (i) => Tween<double>(begin: 0.2, end: 1.0).animate(
              CurvedAnimation(
                  parent: _ctrl,
                  curve: Interval(i * 0.2, i * 0.2 + 0.6,
                      curve: Curves.easeInOut)),
            ));
    if (widget.steps != null && widget.steps!.isNotEmpty) {
      _stepTimer = Timer.periodic(const Duration(milliseconds: 600), (t) {
        if (!mounted) {
          t.cancel();
          return;
        }
        setState(() {
          if (_visibleSteps < widget.steps!.length)
            _visibleSteps++;
          else
            t.cancel();
        });
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _stepTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final steps = widget.steps;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
        decoration: BoxDecoration(
          color: const Color(0xFFE8EDE6),
          borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
              bottomRight: Radius.circular(20)),
          border: Border.all(color: const Color(0xFFE8EDE6)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (steps != null && steps.isNotEmpty)
              ...steps.take(_visibleSteps).map((s) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(s,
                        style: const TextStyle(
                            color: Color(0xFF3E3F3B),
                            fontSize: 13,
                            height: 1.5)),
                  ))
            else
              const Text("Haazir soch raha hai...",
                  style:
                      TextStyle(color: const Color(0xFF565955), fontSize: 12)),
            const SizedBox(height: 8),
            Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(
                    3,
                    (i) => AnimatedBuilder(
                        animation: _ctrl,
                        builder: (_, __) => Container(
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                  color: const Color(0xFF3A9010)
                                      .withValues(alpha: _dots[i].value),
                                  shape: BoxShape.circle),
                            )))),
          ],
        ),
      ),
    );
  }
}

// ── COUNTDOWN TIMER ─────────────────────────────────────────────────────
class CountdownTimer extends StatefulWidget {
  final int seconds;
  final VoidCallback onFinished;
  const CountdownTimer(
      {super.key, required this.seconds, required this.onFinished});
  @override
  State<CountdownTimer> createState() => _CountdownTimerState();
}

class _CountdownTimerState extends State<CountdownTimer> {
  late int _remaining;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _remaining = widget.seconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_remaining <= 1) {
        t.cancel();
        widget.onFinished();
      } else
        setState(() => _remaining--);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _formatted {
    final m = _remaining ~/ 60, s = _remaining % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF7A5400).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border:
            Border.all(color: const Color(0xFF7A5400).withValues(alpha: 0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.timer_outlined, size: 14, color: Color(0xFF7A5400)),
        const SizedBox(width: 6),
        Text("⏱ $_formatted baqi hain provider ke jawab ke liye...",
            style: const TextStyle(
                color: Color(0xFF7A5400),
                fontSize: 12,
                fontWeight: FontWeight.bold)),
      ]),
    );
  }
}

// ── QUOTE BUBBLE ─────────────────────────────────────────────────────────
class QuoteBubble extends StatelessWidget {
  final String providerName;
  final String rating;
  final double distanceKm;
  final int onTimeScore;
  final String expertise;
  final int visitFee;
  final int minRate, maxRate;
  final double hoursMin, hoursMax;
  final int distanceFee;
  final int urgencySurcharge;
  final int minTotal, maxTotal;
  final int industryMin, industryMax;
  final bool budgetFloorTriggered;
  final Map<String, dynamic>? budgetAlt;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final Function(double) onCounter;
  final List<String> chips;

  const QuoteBubble({
    super.key,
    required this.providerName,
    required this.rating,
    this.distanceKm = 0,
    this.onTimeScore = 85,
    this.expertise = "",
    this.visitFee = 150,
    required this.minRate,
    required this.maxRate,
    this.hoursMin = 1.5,
    this.hoursMax = 2.0,
    this.distanceFee = 0,
    this.urgencySurcharge = 0,
    required this.minTotal,
    required this.maxTotal,
    required this.industryMin,
    required this.industryMax,
    this.budgetFloorTriggered = false,
    this.budgetAlt,
    required this.onAccept,
    required this.onDecline,
    required this.onCounter,
    this.chips = const ["Accept", "Thora kam karo", "Cancel"],
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
            bottomRight: Radius.circular(24)),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Provider header
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("👷 $providerName",
                style: const TextStyle(
                    color: const Color(0xFF21231D),
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Row(children: [
              const Icon(Icons.star_rounded, size: 14, color: Colors.amber),
              Text(" $rating★",
                  style: const TextStyle(
                      color: const Color(0xFF3E3F3B), fontSize: 12)),
              const SizedBox(width: 8),
              const Icon(Icons.location_on,
                  size: 14, color: const Color(0xFF767773)),
              Text(" ${distanceKm}km",
                  style: const TextStyle(
                      color: const Color(0xFF565955), fontSize: 12)),
              const SizedBox(width: 8),
              const Icon(Icons.access_time,
                  size: 14, color: const Color(0xFF767773)),
              Text(" $onTimeScore% on-time",
                  style: const TextStyle(
                      color: const Color(0xFF565955), fontSize: 12)),
            ]),
            if (expertise.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text("🔧 $expertise",
                  style: const TextStyle(
                      color: const Color(0xFF767773), fontSize: 11))
            ],
          ]),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
                color: const Color(0xFF3A9010).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: const Color(0xFF3A9010).withValues(alpha: 0.3))),
            child: Text("Rs. $minTotal – $maxTotal",
                style: const TextStyle(
                    color: const Color(0xFF3A9010),
                    fontSize: 13,
                    fontWeight: FontWeight.w800)),
          ),
        ]),
        const SizedBox(height: 16),
        // Breakdown table
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: const Color(0xFFF7FAF5),
              borderRadius: BorderRadius.circular(12)),
          child: Column(children: [
            _row("Visit fee:", "Rs. $visitFee (non-refundable)"),
            _row("Labour:",
                "Rs. $minRate–$maxRate/hr × ${hoursMin}–${hoursMax} hrs"),
            if (distanceFee > 0)
              _row("Distance (${distanceKm}km):", "Rs. $distanceFee"),
            if (urgencySurcharge > 0)
              _row("Urgency surcharge:", "Rs. $urgencySurcharge"),
            const Divider(color: const Color(0xFFE8EDE6), height: 16),
            _row("Estimated total:", "Rs. $minTotal – Rs. $maxTotal",
                bold: true, color: const Color(0xFF3A9010)),
          ]),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
              color: const Color(0xFFF7FAF5),
              borderRadius: BorderRadius.circular(10)),
          child: const Row(children: [
            Icon(Icons.info_outline, size: 13, color: const Color(0xFF767773)),
            SizedBox(width: 6),
            Expanded(
                child: Text(
                    "⚠️ Labour only. Parts/equipment cost alag hoga — provider on-site batayega.",
                    style: TextStyle(
                        color: const Color(0xFF565955), fontSize: 11))),
          ]),
        ),
        const SizedBox(height: 8),
        Row(children: [
          const Icon(Icons.compare_arrows,
              size: 13, color: const Color(0xFF767773)),
          const SizedBox(width: 6),
          Text("Industry standard: Rs. $industryMin – Rs. $industryMax",
              style: const TextStyle(
                  color: const Color(0xFF767773), fontSize: 11)),
        ]),
        if (budgetFloorTriggered && budgetAlt != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: const Color(0xFF7A5400).withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: const Color(0xFF7A5400).withValues(alpha: 0.25))),
            child: Row(children: [
              const Icon(Icons.warning_amber_rounded,
                  size: 15, color: Color(0xFF7A5400)),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(
                      "Budget option: ${budgetAlt!['provider_name']} (Rs. ${budgetAlt!['min_total']}–${budgetAlt!['max_total']})",
                      style: const TextStyle(
                          color: Color(0xFF7A5400), fontSize: 11))),
            ]),
          ),
        ],
        const SizedBox(height: 16),
        Wrap(
            spacing: 8,
            runSpacing: 8,
            children: chips.map((chip) {
              final isAccept = chip.contains("Accept");
              final isDecline =
                  chip.contains("Cancel") || chip.contains("Nahi");
              return GestureDetector(
                onTap: isAccept
                    ? onAccept
                    : isDecline
                        ? onDecline
                        : () => onCounter((minTotal + maxTotal) / 2 * 0.9),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: isAccept
                        ? const Color(0xFF3A9010)
                        : isDecline
                            ? Colors.redAccent.withValues(alpha: 0.12)
                            : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: isAccept
                            ? const Color(0xFF3A9010)
                            : isDecline
                                ? Colors.redAccent.withValues(alpha: 0.5)
                                : const Color(0xFF7A5400)),
                  ),
                  child: Text(chip,
                      style: TextStyle(
                          color: isAccept
                              ? Colors.black
                              : isDecline
                                  ? Colors.redAccent
                                  : const Color(0xFF7A5400),
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                ),
              );
            }).toList()),
      ]),
    );
  }

  Widget _row(String label, String value, {bool bold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label,
            style:
                const TextStyle(color: const Color(0xFF565955), fontSize: 12)),
        Text(value,
            style: TextStyle(
                color: color ?? const Color(0xFF3E3F3B),
                fontSize: 12,
                fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
      ]),
    );
  }
}

// ── EQUIPMENT ACK BUBBLE ─────────────────────────────────────────────────
class EquipmentAckBubble extends StatelessWidget {
  final VoidCallback onConfirm;
  final bool disabled;
  const EquipmentAckBubble({super.key, required this.onConfirm, this.disabled = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF7A5400).withValues(alpha: 0.06),
        borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
            bottomRight: Radius.circular(20)),
        border:
            Border.all(color: const Color(0xFF7A5400).withValues(alpha: 0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.info_outline, color: Color(0xFF7A5400), size: 18),
          SizedBox(width: 8),
          Text("Zaroori Baat",
              style: TextStyle(
                  color: Color(0xFF7A5400),
                  fontSize: 13,
                  fontWeight: FontWeight.bold))
        ]),
        const SizedBox(height: 10),
        const Text(
            "Yeh booking sirf LABOUR charges ke liye hai.\n\nAgar koi part, pipe, fitting ya material lagta hai toh uska cost is quote mein shamil NAHI hai. Provider aap ko on-site pehle batayega.",
            style:
                TextStyle(color: Color(0xFF3E3F3B), fontSize: 13, height: 1.5)),
        const SizedBox(height: 14),
        GestureDetector(
          onTap: disabled ? null : onConfirm,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
                color: disabled ? const Color(0xFFCCCCCC) : const Color(0xFF3A9010),
                borderRadius: BorderRadius.circular(20)),
            child: Text("Haan, samajh gaya — Aage barhao",
                style: TextStyle(
                    color: disabled ? const Color(0xFF888888) : Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold)),
          ),
        ),
      ]),
    );
  }
}

// ── SUCCESS BUBBLE ────────────────────────────────────────────────────────
class SuccessBubble extends StatelessWidget {
  final String providerName, scheduledTime, bookingId;
  final int price;
  final List<dynamic> checklist;
  const SuccessBubble(
      {super.key,
      required this.providerName,
      required this.scheduledTime,
      required this.price,
      required this.bookingId,
      required this.checklist});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF3A9010).withValues(alpha: 0.08),
        borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
            bottomRight: Radius.circular(24)),
        border:
            Border.all(color: const Color(0xFF3A9010).withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: const Color(0xFF3A9010).withValues(alpha: 0.2),
                  shape: BoxShape.circle),
              child: const Icon(Icons.check_rounded,
                  color: const Color(0xFF3A9010), size: 22)),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text("BOOKING CONFIRMED!",
                style: TextStyle(
                    color: const Color(0xFF3A9010),
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1)),
            Text("ID: $bookingId",
                style: const TextStyle(
                    color: const Color(0xFF565955), fontSize: 11)),
          ]),
        ]),
        const Divider(height: 28, color: const Color(0xFFE8EDE6)),
        _row("Provider:", providerName),
        _row("Arrival:", scheduledTime),
        _row("Agreed Rate:", "Rs. $price", color: const Color(0xFF3A9010)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: const Color(0xFFF7FAF5),
              borderRadius: BorderRadius.circular(10)),
          child: const Text(
              "⚠️ Labour only. Parts extra — provider will discuss on-site.\n🔔 1 ghante pehle reminder milega.",
              style: TextStyle(
                  color: const Color(0xFF565955), fontSize: 11, height: 1.5)),
        ),
        if (checklist.isNotEmpty) ...[
          const Divider(height: 24, color: const Color(0xFFE8EDE6)),
          const Text("JOB COMPLETION CHECKLIST",
              style: TextStyle(
                  color: const Color(0xFF767773),
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1)),
          const SizedBox(height: 8),
          ...checklist.take(4).map((item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  const Icon(Icons.circle_outlined,
                      size: 11, color: const Color(0xFF767773)),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(item['item'] ?? item.toString(),
                          style: const TextStyle(
                              color: const Color(0xFF3E3F3B), fontSize: 12)))
                ]),
              )),
        ],
      ]),
    );
  }

  Widget _row(String label, String value, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child:
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label,
              style: const TextStyle(
                  color: const Color(0xFF565955), fontSize: 13)),
          Text(value,
              style: TextStyle(
                  color: color ?? const Color(0xFF21231D),
                  fontSize: 13,
                  fontWeight: FontWeight.bold)),
        ]),
      );
}

// ── RATING BUBBLE ─────────────────────────────────────────────────────────
class RatingBubble extends StatefulWidget {
  final String providerName;
  final Function(int stars, String comment) onSubmit;
  const RatingBubble(
      {super.key, required this.providerName, required this.onSubmit});
  @override
  State<RatingBubble> createState() => _RatingBubbleState();
}

class _RatingBubbleState extends State<RatingBubble> {
  int _stars = 0;
  final _commentCtrl = TextEditingController();

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE8EDE6))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text("${widget.providerName} ko rate karein:",
            style: const TextStyle(
                color: const Color(0xFF21231D),
                fontSize: 14,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Row(
            children: List.generate(
                5,
                (i) => GestureDetector(
                      onTap: () => setState(() => _stars = i + 1),
                      child: Icon(
                          i < _stars
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          color: Colors.amber,
                          size: 32),
                    ))),
        if (_stars > 0) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _commentCtrl,
            style:
                const TextStyle(color: const Color(0xFF21231D), fontSize: 13),
            decoration: InputDecoration(
                hintText: "Koi comment? (optional)",
                hintStyle: const TextStyle(color: const Color(0xFF767773)),
                filled: true,
                fillColor: const Color(0xFFF7FAF5),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none)),
          ),
          const SizedBox(height: 12),
          Row(children: [
            GestureDetector(
              onTap: () => widget.onSubmit(_stars, _commentCtrl.text),
              child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                      color: const Color(0xFF3A9010),
                      borderRadius: BorderRadius.circular(20)),
                  child: const Text("Submit",
                      style: TextStyle(
                          color: Colors.black, fontWeight: FontWeight.bold))),
            ),
            const SizedBox(width: 10),
            GestureDetector(
                onTap: () => widget.onSubmit(0, ""),
                child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFB0B5AE)),
                        borderRadius: BorderRadius.circular(20)),
                    child: const Text("Skip",
                        style: TextStyle(color: const Color(0xFF565955))))),
          ]),
        ],
      ]),
    );
  }
}

class Top3ProvidersBubble extends StatelessWidget {
  final List<dynamic> providers;
  final String reasoning;
  final Function(String providerId) onSelect;
  final VoidCallback onMoreOptions;
  final bool disabled;

  const Top3ProvidersBubble({
    super.key,
    required this.providers,
    required this.reasoning,
    required this.onSelect,
    required this.onMoreOptions,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF7FAF5),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
              border: Border.all(color: const Color(0xFFE8EDE6)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.psychology_rounded,
                        color: const Color(0xFF3A9010), size: 20),
                    SizedBox(width: 8),
                    Text(
                      "Haazir AI Matcher",
                      style: TextStyle(
                        color: const Color(0xFF3A9010),
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  reasoning,
                  style: const TextStyle(
                    color: Color(0xFF3E3F3B),
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 335,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: providers.length,
              itemBuilder: (context, idx) {
                final p = providers[idx] as Map<String, dynamic>;
                final pId =
                    p['provider_id'] as String? ?? p['id'] as String? ?? '';
                final name = p['name'] as String? ?? 'Provider';
                final shopName = p['shop_name'] as String? ?? 'Workshop';
                final rating = p['rating']?.toString() ?? '4.5';
                final distanceKm = p['distance_km']?.toString() ?? '2.0';
                final onTimeScore = p['on_time_score']?.toString() ?? '0.9';
                final score = p['score']?.toString() ?? '90';

                final charges = p['charges'] as Map<String, dynamic>? ?? {};
                final baseRate = charges['base_rate']?.toString() ?? '500';

                final priceQuote =
                    p['price_quote'] as Map<String, dynamic>? ?? {};
                final total = priceQuote['total']?.toString() ?? '1500';
                final visitFee = priceQuote['visit_fee'] as int? ?? 150;
                final urgencySurcharge =
                    priceQuote['urgency_surcharge'] as int? ?? 0;

                final isWaitlisted = p['is_waitlisted'] as bool? ?? false;
                final isBudgetPick = p['is_budget_pick'] as bool? ?? false;

                final serviceExpertise =
                    (p['service_expertise'] as List<dynamic>? ?? [])
                        .cast<String>()
                        .take(2)
                        .toList();

                double otVal = double.tryParse(onTimeScore) ?? 0.9;
                if (otVal <= 1.0) otVal *= 100;
                final onTimePercent = otVal.round().toString();

                return Container(
                  width: 270,
                  margin: const EdgeInsets.only(right: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: isWaitlisted
                          ? const Color(0xFF7A5400).withValues(alpha: 0.3)
                          : isBudgetPick
                              ? Colors.lightBlueAccent.withValues(alpha: 0.4)
                              : const Color(0xFF3A9010).withValues(alpha: 0.2),
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Top badge row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF3A9010)
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.flash_on_rounded,
                                    size: 12, color: const Color(0xFF3A9010)),
                                const SizedBox(width: 4),
                                Text(
                                  "$score% Match",
                                  style: const TextStyle(
                                    color: const Color(0xFF3A9010),
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Row(
                            children: [
                              if (isBudgetPick) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.lightBlueAccent
                                        .withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Text(
                                    "💰 Best Value",
                                    style: TextStyle(
                                      color: Colors.lightBlueAccent,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                              ],
                              if (isWaitlisted)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF7A5400)
                                        .withValues(alpha: 0.10),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Text(
                                    "Waitlist",
                                    style: TextStyle(
                                      color: Color(0xFF7A5400),
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        "👷 $name",
                        style: const TextStyle(
                          color: const Color(0xFF21231D),
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        shopName,
                        style: const TextStyle(
                            color: const Color(0xFF767773), fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (serviceExpertise.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: serviceExpertise
                              .map((e) => Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF3A9010)
                                          .withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                          color: const Color(0xFF3A9010)
                                              .withValues(alpha: 0.2)),
                                    ),
                                    child: Text(
                                      e.replaceAll('_', ' '),
                                      style: const TextStyle(
                                          color: const Color(0xFF3A9010),
                                          fontSize: 9,
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ))
                              .toList(),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.star_rounded,
                              size: 14, color: Colors.amber),
                          Text(" $rating",
                              style: const TextStyle(
                                  color: const Color(0xFF3E3F3B),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(width: 8),
                          const Icon(Icons.location_on,
                              size: 13, color: const Color(0xFF767773)),
                          Text(" ${distanceKm}km",
                              style: const TextStyle(
                                  color: const Color(0xFF565955),
                                  fontSize: 11)),
                          const SizedBox(width: 8),
                          const Icon(Icons.timer_outlined,
                              size: 13, color: const Color(0xFF767773)),
                          Text(" $onTimePercent% on-time",
                              style: const TextStyle(
                                  color: const Color(0xFF565955),
                                  fontSize: 11)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Container(height: 1, color: const Color(0xFFE8EDE6)),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text("EST. TOTAL",
                                  style: TextStyle(
                                      color: const Color(0xFF767773),
                                      fontSize: 9,
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 2),
                              Text(
                                "Rs. $total",
                                style: const TextStyle(
                                  color: const Color(0xFF3A9010),
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Text("HOURLY RATE",
                                  style: TextStyle(
                                      color: const Color(0xFF767773),
                                      fontSize: 9,
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 2),
                              Text(
                                "Rs. $baseRate/hr",
                                style: const TextStyle(
                                  color: const Color(0xFF3E3F3B),
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      // Mini fee breakdown
                      Row(children: [
                        Text(
                          "Visit Rs. $visitFee${urgencySurcharge > 0 ? ' · Urgency Rs. $urgencySurcharge' : ''}",
                          style: const TextStyle(
                              color: const Color(0xFFB0B5AE), fontSize: 9),
                        ),
                      ]),
                      const Spacer(),
                      GestureDetector(
                        onTap: disabled ? null : () => onSelect(pId),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: disabled ? const Color(0xFFCCCCCC) : const Color(0xFF3A9010),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Center(
                            child: Text(
                              "Select Provider",
                              style: TextStyle(
                                color: disabled ? const Color(0xFF888888) : Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              GestureDetector(
                onTap: disabled ? null : onMoreOptions,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: disabled ? const Color(0xFFF0F0F0) : const Color(0xFFF7FAF5),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: disabled ? const Color(0xFFCCCCCC) : const Color(0xFFE8EDE6)),
                  ),
                  child: Row(
                    children: [
                      Text(
                        "More Options",
                        style: TextStyle(
                            color: disabled ? const Color(0xFFAAAAAA) : const Color(0xFF3E3F3B),
                            fontSize: 11,
                            fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.arrow_forward_rounded,
                          size: 12,
                          color: disabled ? const Color(0xFFAAAAAA) : const Color(0xFF3E3F3B)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
