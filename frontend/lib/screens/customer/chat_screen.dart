import 'package:flutter/material.dart';
import 'dart:async';
import '../../services/api_service.dart';
import 'widgets/chat_widgets.dart';

class Message {
  final String id;
  final String text;
  final bool isUser;
  final String type; // text | thinking | quote | equipment_ack | booking_success | rating
  final Map<String, dynamic>? data;
  final List<String>? chips;

  Message({required this.text, required this.isUser, this.type = 'text', this.data, this.chips}) : id = UniqueKey().toString();
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final List<Message> _messages = [];
  bool _loading = false;
  bool _inputDisabled = false;
  String? _sessionId;
  bool _countdownActive = false;
  int _countdownSeconds = 180;

  @override
  void initState() {
    super.initState();
    _initSession();
  }

  @override
  void dispose() { _ctrl.dispose(); _scroll.dispose(); super.dispose(); }

  Future<void> _initSession() async {
    setState(() => _loading = true);
    try {
      final res = await ApiService.createSession("customer_001");
      _sessionId = res['session_id'];
      // Send empty string to get greeting + chips
      final greeting = await ApiService.orchestrate("", [], sessionId: _sessionId);
      _handleResponse(greeting);
    } catch (e) {
      _addMsg(Message(text: "Connection error: $e. Please refresh.", isUser: false));
      setState(() => _loading = false);
    }
  }

  void _scrollBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    });
  }

  void _addMsg(Message msg) {
    setState(() => _messages.add(msg));
    _scrollBottom();
  }

  Future<void> _send([String? override]) async {
    final input = override ?? _ctrl.text.trim();
    if (input.isEmpty || _inputDisabled) return;
    _ctrl.clear();
    _addMsg(Message(text: input, isUser: true));
    setState(() { _loading = true; _inputDisabled = true; });

    // Remove thinking bubble if present
    setState(() => _messages.removeWhere((m) => m.type == 'thinking'));

    // Add typing indicator
    _addMsg(Message(text: '', isUser: false, type: 'thinking'));

    await Future.delayed(const Duration(milliseconds: 1500));

    try {
      final res = await ApiService.orchestrate(input, [], sessionId: _sessionId);
      setState(() => _messages.removeWhere((m) => m.type == 'thinking'));
      _handleResponse(res);
    } catch (e) {
      setState(() { _messages.removeWhere((m) => m.type == 'thinking'); _loading = false; _inputDisabled = false; });
      _addMsg(Message(text: "Error: $e", isUser: false));
    }
  }

  void _handleResponse(Map<String, dynamic> res) {
    setState(() {
      _loading = false;
      _inputDisabled = false;
      if (res['session_id'] != null) _sessionId = res['session_id'];
    });

    final phase = res['phase'] as String? ?? '';
    final msg = res['message'] as String? ?? '';
    final chips = (res['chips'] as List?)?.cast<String>();

    if (phase == 'negotiating') {
      // Show agent thinking steps first, then quote
      final steps = (res['thinking_steps'] as List?)?.cast<String>();
      if (steps != null && steps.isNotEmpty) {
        _addMsg(Message(text: '', isUser: false, type: 'thinking', data: {'steps': steps}));
        Future.delayed(Duration(milliseconds: 600 * steps.length + 500), () {
          if (!mounted) return;
          setState(() => _messages.removeWhere((m) => m.type == 'thinking'));
          _addMsg(Message(text: msg, isUser: false, type: 'quote', data: res, chips: chips ?? ["✓ Accept", "🔽 Thora kam karo", "✗ Cancel"]));
          _startCountdown((res['countdown_seconds'] as num?)?.toInt() ?? 180);
        });
      } else {
        _addMsg(Message(text: msg, isUser: false, type: 'quote', data: res, chips: chips ?? ["✓ Accept", "🔽 Thora kam karo", "✗ Cancel"]));
        _startCountdown((res['countdown_seconds'] as num?)?.toInt() ?? 180);
      }
    } else if (phase == 'equipment_ack') {
      _countdownActive = false;
      _addMsg(Message(text: msg, isUser: false, type: 'equipment_ack'));
      setState(() => _inputDisabled = true); // must use chip
    } else if (phase == 'booking_confirmed') {
      _countdownActive = false;
      setState(() => _inputDisabled = false);
      _addMsg(Message(text: msg, isUser: false, type: 'booking_success', data: res['booking']));
    } else if (phase == 'budget_floor') {
      _addMsg(Message(text: msg, isUser: false, chips: chips));
    } else {
      _addMsg(Message(text: msg, isUser: false, chips: chips));
    }
  }

  void _startCountdown(int secs) {
    setState(() { _countdownActive = true; _countdownSeconds = secs; _inputDisabled = true; });
  }

  Future<void> _onProviderTimeout() async {
    if (!_countdownActive || _sessionId == null) return;
    setState(() { _countdownActive = false; _inputDisabled = true; _loading = true; });
    _addMsg(Message(text: "⏱ Provider ne jawab nahi diya. Main agle provider ko try karta hoon...", isUser: false));
    try {
      final res = await ApiService.timeoutNegotiation(_sessionId!);
      setState(() { _loading = false; _inputDisabled = false; });
      _handleResponse(res);
    } catch (e) {
      setState(() { _loading = false; _inputDisabled = false; });
      _addMsg(Message(text: "Timeout error: $e", isUser: false));
    }
  }

  Widget _buildBubble(Message msg, int index) {
    if (msg.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 5),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Color(0xFF00C853), Color(0xFF00A240)], begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20), bottomLeft: Radius.circular(20)),
          ),
          child: Text(msg.text, style: const TextStyle(color: Colors.black, fontSize: 14, fontWeight: FontWeight.w600)),
        ),
      );
    }

    switch (msg.type) {
      case 'thinking':
        final steps = (msg.data?['steps'] as List?)?.cast<String>();
        return ThinkingBubble(steps: steps);

      case 'quote':
        final d = msg.data ?? {};
        final q = d['price_quote'] as Map<String, dynamic>? ?? {};
        final providers = d['match_result']?['top_providers'] as List? ?? [];
        final provider = providers.isNotEmpty ? providers[0] as Map<String, dynamic> : <String, dynamic>{};
        final activeChips = msg.chips ?? ["✓ Accept", "🔽 Thora kam karo", "✗ Cancel"];
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _textBubble(msg.text),
          QuoteBubble(
            providerName: provider['name'] ?? 'Provider',
            rating: (provider['rating'] ?? 4.8).toString(),
            distanceKm: (provider['distance_km'] ?? 0).toDouble(),
            onTimeScore: ((provider['on_time_score'] ?? 0.85) * 100).toInt(),
            expertise: (provider['service_types'] as List?)?.take(2).join(', ') ?? '',
            visitFee: (q['visit_fee'] as num?)?.toInt() ?? 200,
            minRate: (q['base_rate'] as num?)?.toInt() ?? 600,
            maxRate: (((q['base_rate'] as num?)?.toDouble() ?? 600.0) * 1.25).toInt(),
            hoursMin: (q['hours_min'] as num?)?.toDouble() ?? 1.5,
            hoursMax: (q['hours_max'] as num?)?.toDouble() ?? 2.0,
            distanceFee: (q['distance_fee'] as num?)?.toInt() ?? 0,
            urgencySurcharge: (q['urgency_surcharge'] as num?)?.toInt() ?? 0,
            minTotal: (q['min_total'] as num?)?.toInt() ?? 1000,
            maxTotal: (q['max_total'] as num?)?.toInt() ?? 1500,
            industryMin: (q['industry_standard_min'] as num?)?.toInt() ?? 800,
            industryMax: (q['industry_standard_max'] as num?)?.toInt() ?? 2000,
            budgetFloorTriggered: q['budget_alternative'] != null,
            budgetAlt: q['budget_alternative'] as Map<String, dynamic>?,
            chips: activeChips,
            onAccept: () => _send("✓ Accept"),
            onDecline: () => _send("✗ Cancel"),
            onCounter: (v) => _send("🔽 Thora kam karo"),
          ),
          if (_countdownActive && index == _messages.length - 1)
            CountdownTimer(seconds: _countdownSeconds, onFinished: _onProviderTimeout),
        ]);

      case 'equipment_ack':
        return EquipmentAckBubble(onConfirm: () {
          setState(() => _inputDisabled = false);
          _send("✓ Haan, samajh gaya — Aage barhao");
        });

      case 'booking_success':
        final bk = msg.data ?? {};
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _textBubble(msg.text),
          SuccessBubble(
            providerName: bk['provider_name'] ?? 'Provider',
            scheduledTime: bk['scheduled_time'] != null ? bk['scheduled_time'].toString().substring(0, 16) : 'Tomorrow',
            price: (bk['final_price'] as num?)?.toInt() ?? 1000,
            bookingId: bk['booking_id'] ?? 'BK-XXXX',
            checklist: bk['checklist'] ?? [],
          ),
        ]);

      default:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _textBubble(msg.text),
          if (msg.chips != null && msg.chips!.isNotEmpty)
            ChipRow(chips: msg.chips!, onTap: _send),
        ]);
    }
  }

  Widget _textBubble(String text) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: const BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20), bottomRight: Radius.circular(20)),
          border: Border.all(color: Colors.white.withOpacity(0.07)),
        ),
        child: Text(text, style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 14, height: 1.5)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        title: Row(children: [
          Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF00C853), shape: BoxShape.circle)),
          const SizedBox(width: 8),
          const Text("Khedmatgar AI", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ]),
        actions: [IconButton(icon: const Icon(Icons.refresh_rounded, color: Colors.white54), onPressed: () { setState(() { _messages.clear(); _countdownActive = false; _inputDisabled = false; }); _initSession(); })],
      ),
      body: SafeArea(child: Column(children: [
        Expanded(child: ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          itemCount: _messages.length,
          itemBuilder: (ctx, i) => KeyedSubtree(
            key: ObjectKey(_messages[i]),
            child: _buildBubble(_messages[i], i),
          ),
        )),
        if (_loading) const Padding(padding: EdgeInsets.all(8), child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00C853))))),
        _buildInput(),
      ])),
    );
  }

  Widget _buildInput() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(color: Color(0xFF1E293B), border: Border(top: BorderSide(color: Colors.white10))),
      child: Row(children: [
        Expanded(child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white.withOpacity(0.07))),
          child: TextField(
            controller: _ctrl,
            enabled: !_inputDisabled,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: _inputDisabled ? "Intezaar karein..." : "Ya aap type bhi kar sakte hain...",
              hintStyle: const TextStyle(color: Colors.white30, fontSize: 13),
              border: InputBorder.none,
            ),
            onSubmitted: (_) => _send(),
          ),
        )),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _inputDisabled ? null : _send,
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: _inputDisabled ? Colors.white12 : const Color(0xFF00C853), shape: BoxShape.circle),
            child: Icon(Icons.send_rounded, color: _inputDisabled ? Colors.white38 : Colors.black, size: 18),
          ),
        ),
      ]),
    );
  }
}
