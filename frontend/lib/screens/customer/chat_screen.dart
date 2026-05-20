import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:async';
import 'dart:math' as math;
import '../../services/api_service.dart';
import 'widgets/chat_widgets.dart';
import '../provider/provider_home.dart';

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
  final String? initialPrompt;
  final String? bookingId;
  const ChatScreen({super.key, this.initialPrompt, this.bookingId});
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
      if (widget.bookingId != null) {
        try {
          final b = await ApiService.get('booking/${widget.bookingId}');
          if (b is Map<String, dynamic> && b['booking_id'] != null) {
            _addMsg(Message(
              text: "Booking ${b['booking_id']}",
              isUser: false,
              type: 'booking_success',
              data: b,
            ));
          } else {
            _addMsg(Message(text: "Booking not found.", isUser: false));
          }
        } catch (e) {
          _addMsg(Message(text: "Error loading booking: $e", isUser: false));
        }
        setState(() => _loading = false);
        return;
      }

      final res = await ApiService.createSession("customer_001");
      _sessionId = res['session_id'];
      
      if (widget.initialPrompt != null && widget.initialPrompt!.isNotEmpty) {
        // Send initial prompt directly
        _addMsg(Message(text: widget.initialPrompt!, isUser: true));
        _addMsg(Message(text: '', isUser: false, type: 'thinking'));
        final response = await ApiService.orchestrate(widget.initialPrompt!, [], sessionId: _sessionId);
        setState(() => _messages.removeWhere((m) => m.type == 'thinking'));
        _handleResponse(response);
      } else {
        // Send empty string to get greeting + chips
        final greeting = await ApiService.orchestrate("", [], sessionId: _sessionId);
        _handleResponse(greeting);
      }
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

  List<Map<String, String>> _buildHistory() {
    return _messages
        .where((m) => m.type == 'text' && m.text.isNotEmpty)
        .map((m) => {'role': m.isUser ? 'user' : 'model', 'content': m.text})
        .toList();
  }

  Future<void> _send([String? override]) async {
    final input = override ?? _ctrl.text.trim();
    final isSystemAction = override != null;
    if (input.isEmpty || (_inputDisabled && !isSystemAction)) return;
    _ctrl.clear();
    final history = _buildHistory();
    _addMsg(Message(text: input, isUser: true));
    setState(() { _loading = true; _inputDisabled = true; });

    // Remove thinking bubble if present
    setState(() => _messages.removeWhere((m) => m.type == 'thinking'));

    // Add typing indicator
    _addMsg(Message(text: '', isUser: false, type: 'thinking'));

    await Future.delayed(const Duration(milliseconds: 1000));

    try {
      final res = await ApiService.orchestrate(input, history, sessionId: _sessionId);
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
      final steps = (res['thinking_steps'] as List?)?.cast<String>();
      if (steps != null && steps.isNotEmpty) {
        _addMsg(Message(text: '', isUser: false, type: 'thinking', data: {'steps': steps}));
        Future.delayed(Duration(milliseconds: 400 * steps.length + 300), () {
          if (!mounted) return;
          setState(() => _messages.removeWhere((m) => m.type == 'thinking'));
          _addMsg(Message(text: msg, isUser: false, type: 'quote', data: res, chips: chips));
          _startCountdown((res['countdown_seconds'] as num?)?.toInt() ?? 180);
        });
      } else {
        _addMsg(Message(text: msg, isUser: false, type: 'quote', data: res, chips: chips));
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
    _addMsg(Message(text: "⏱ Provider didn't respond in time. Finding the next available provider...", isUser: false));
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
            color: const Color(0xFF163300),
            borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20), bottomLeft: Radius.circular(20)),
          ),
          child: Text(msg.text, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
        ),
      );
    }

    switch (msg.type) {
      case 'thinking':
        final steps = (msg.data?['steps'] as List?)?.cast<String>();
        return ThinkingBubble(steps: steps);

      case 'quote':
        final d = msg.data ?? {};
        final providers = d['match_result']?['top_providers'] as List? ?? [];
        final reasoning = d['match_result']?['reasoning'] as String? ?? 'Best matching option selected.';
        return Top3ProvidersBubble(
          providers: providers,
          reasoning: reasoning,
          onSelect: (pId) {
            _send("✓ Select $pId");
          },
          onMoreOptions: () {
            _send("More Options");
          },
        );

      case 'equipment_ack':
        return EquipmentAckBubble(onConfirm: () {
          setState(() => _inputDisabled = false);
          _send("✓ Haan, samajh gaya — Aage barhao");
        });

      case 'booking_success':
        final bk = msg.data ?? {};
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _textBubble(msg.text),
            SuccessBubble(
              providerName: bk['provider_name'] ?? 'Provider',
              scheduledTime: bk['scheduled_time'] != null ? bk['scheduled_time'].toString().substring(0, 16) : 'Tomorrow',
              price: (bk['final_price'] as num?)?.toInt() ?? 1000,
              bookingId: bk['booking_id'] ?? 'BK-XXXX',
              checklist: bk['checklist'] ?? [],
            ),
            LiveTrackingWidget(
              booking: bk,
              onRated: (stars) {
                _addMsg(Message(text: "Your rating has been submitted. Thank you for using Haazir!", isUser: false));
              },
            ),
          ],
        );

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
          color: Colors.white,
          borderRadius: const BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20), bottomRight: Radius.circular(20)),
          border: Border.all(color: const Color(0xFFE8EDE6)),
        ),
        child: Text(text, style: const TextStyle(color: Color(0xFF3E3F3B), fontSize: 14, height: 1.5)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAF5),
      appBar: _buildAppBar(),
      body: Column(children: [
        Expanded(child: ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          itemCount: _messages.length,
          itemBuilder: (ctx, i) => KeyedSubtree(
            key: ObjectKey(_messages[i]),
            child: _buildBubble(_messages[i], i),
          ),
        )),
        if (_loading) const Padding(padding: EdgeInsets.all(8), child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: const Color(0xFF3A9010))))),
        _buildInput(),
      ]),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF163300),
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white, size: 18),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: SvgPicture.asset('assets/haazir_logo.svg', height: 26),
      actions: [
        Container(
          margin: const EdgeInsets.only(right: 12),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
          ),
          child: Row(children: [
            const Icon(Icons.person_rounded, size: 16, color: Colors.white),
            const SizedBox(width: 4),
            const Text('Customer', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const ProviderHome()),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text('To Provider', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ),
          ]),
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1.0),
        child: Container(color: const Color(0xFFE8EDE6), height: 1.0),
      ),
    );
  }

  Widget _buildInput() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: const Color(0xFFE8EDE6)))),
      child: Row(children: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded, color: const Color(0xFF767773), size: 20),
          onPressed: () {
            setState(() {
              _messages.clear();
              _countdownActive = false;
              _inputDisabled = false;
            });
            _initSession();
          },
        ),
        Expanded(child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(color: const Color(0xFFF7FAF5), borderRadius: BorderRadius.circular(24), border: Border.all(color: const Color(0xFFE8EDE6))),
          child: TextField(
            controller: _ctrl,
            enabled: !_inputDisabled,
            style: const TextStyle(color: const Color(0xFF21231D)),
            decoration: InputDecoration(
              hintText: _inputDisabled ? "Please wait..." : "What do you need help with?",
              hintStyle: const TextStyle(color: const Color(0xFF767773), fontSize: 13),
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
            decoration: BoxDecoration(color: _inputDisabled ? const Color(0xFFE8EDE6) : const Color(0xFF3A9010), shape: BoxShape.circle),
            child: Icon(Icons.send_rounded, color: _inputDisabled ? const Color(0xFF767773) : Colors.black, size: 18),
          ),
        ),
      ]),
    );
  }
}

// ── STATEFUL LIVE TRACKING & SIMULATION WIDGET ────────────────────────────
class LiveTrackingWidget extends StatefulWidget {
  final Map<String, dynamic> booking;
  final Function(int stars) onRated;

  const LiveTrackingWidget({
    super.key,
    required this.booking,
    required this.onRated,
  });

  @override
  State<LiveTrackingWidget> createState() => _LiveTrackingWidgetState();
}

class _LiveTrackingWidgetState extends State<LiveTrackingWidget> {
  late Map<String, dynamic> _booking;
  Timer? _gpsTimer;
  Timer? _pollTimer;
  bool _simulating = false;
  int _starsSubmitted = 0;
  bool _disputeSubmitted = false;
  String? _disputeResolution;

  @override
  void initState() {
    super.initState();
    _booking = widget.booking;
    _startPolling();
    final status = _booking['status'] as String? ?? '';
    if (status == 'ACCEPTED' || status == 'ARRIVING') {
      Future.delayed(const Duration(milliseconds: 600), _startSimulation);
    }
  }

  @override
  void dispose() {
    _gpsTimer?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _refreshStatus());
  }

  Future<void> _refreshStatus() async {
    final bId = _booking['booking_id'];
    if (bId == null) return;
    try {
      final res = await ApiService.get('booking/$bId');
      if (!mounted) return;
      if (res is Map<String, dynamic> && res['booking_id'] != null) {
        final prevStatus = _booking['status'] as String? ?? '';
        final newStatus = res['status'] as String? ?? '';
        setState(() => _booking = res);
        // Provider just accepted — auto-start GPS simulation
        if ((newStatus == 'ACCEPTED' || newStatus == 'ARRIVING') &&
            prevStatus == 'PENDING_PROVIDER' && !_simulating) {
          _startSimulation();
        }
        // Stop polling when fully resolved
        if (newStatus == 'COMPLETED' || newStatus.startsWith('CANCELLED')) {
          _pollTimer?.cancel();
          _pollTimer = null;
        }
      }
    } catch (_) {}
  }

  void _startSimulation() {
    if (_simulating) return;
    setState(() => _simulating = true);
    _gpsTimer = Timer.periodic(const Duration(seconds: 3), (_) => _simulateStep());
  }

  Future<void> _simulateStep() async {
    final bId = _booking['booking_id'];
    if (bId == null) return;
    try {
      final res = await ApiService.post('/booking/simulate-step', {'booking_id': bId});
      if (!mounted) return;
      final bookingData = res['booking'] as Map<String, dynamic>?;
      if (bookingData != null) {
        setState(() => _booking = bookingData);
        final status = _booking['status'] as String? ?? '';
        final dist = _booking['distance_meters'] as num? ?? 1000;
        // Stop GPS if arrived, already in progress/completed, or step was skipped
        final shouldStop = dist <= 50 ||
            status == 'IN_PROGRESS' ||
            status == 'ARRIVED' ||
            status == 'COMPLETED' ||
            status.startsWith('CANCELLED') ||
            res['status'] == 'skipped';
        if (shouldStop) {
          _gpsTimer?.cancel();
          _gpsTimer = null;
          setState(() => _simulating = false);
        }
      }
    } catch (e) {
      debugPrint('GPS step error: $e');
    }
  }

  Future<void> _submitRating(int stars) async {
    final bId = _booking['booking_id'];
    if (bId == null) return;
    try {
      final res = await ApiService.post('/booking/submit-rating', {
        'booking_id': bId,
        'stars': stars
      });
      if (res['booking'] != null) {
        setState(() {
          _booking = res['booking'];
          _starsSubmitted = stars;
        });
        widget.onRated(stars);
      }
    } catch (e) {
      debugPrint('Rating submission error: $e');
    }
  }

  Future<void> _submitDispute(String issueType) async {
    final bId = _booking['booking_id'];
    final pId = _booking['provider_id'];
    if (bId == null || pId == null) return;
    try {
      final res = await ApiService.post('/dispute', {
        'booking_id': bId,
        'provider_id': pId,
        'issue_type': issueType,
        'comment': '',
      });
      if (!mounted) return;
      setState(() {
        _disputeSubmitted = true;
        _disputeResolution = res['result']?['resolution'] as String? ??
            'Dispute logged. Our team will contact you within 24 hours.';
      });
    } catch (e) {
      debugPrint('Dispute error: $e');
    }
  }

  void _showDisputeModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Report an Issue", style: TextStyle(color: const Color(0xFF21231D), fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text("What went wrong?", style: TextStyle(color: const Color(0xFF565955), fontSize: 13)),
            const SizedBox(height: 12),
            ...[
              ('quality_complaint', 'Quality Issue', Icons.thumb_down_outlined, 'Work was not done properly'),
              ('price_dispute', 'Price Dispute', Icons.money_off_outlined, 'Charged more than quoted'),
              ('no_show', 'Provider No-Show', Icons.person_off_outlined, 'Provider never arrived'),
              ('cancellation', 'Unfair Cancellation', Icons.cancel_outlined, 'Cancelled without a valid reason'),
            ].map((t) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(t.$3, color: Colors.redAccent, size: 20),
              title: Text(t.$2, style: const TextStyle(color: const Color(0xFF21231D), fontSize: 13)),
              subtitle: Text(t.$4, style: const TextStyle(color: const Color(0xFF767773), fontSize: 11)),
              onTap: () {
                Navigator.pop(ctx);
                _submitDispute(t.$1);
              },
            )),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = _booking['status'] as String? ?? 'PENDING_PROVIDER';
    final dist = _booking['distance_meters'] as num? ?? 2000;
    final checklist = _booking['checklist'] as List? ?? [];

    Color statusColor = const Color(0xFF3A9010);
    if (status == 'ARRIVED' || status == 'IN_PROGRESS') statusColor = Colors.blueAccent;
    if (status == 'COMPLETED') statusColor = const Color(0xFF3A9010);
    if (status.startsWith('CANCELLED')) statusColor = Colors.redAccent;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Live Tracking",
                style: TextStyle(color: const Color(0xFF21231D), fontSize: 13, fontWeight: FontWeight.bold),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  status,
                  style: TextStyle(color: statusColor, fontSize: 9, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (status == 'CANCELLED_PROVIDER') ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.25)),
              ),
              child: Column(children: [
                const Row(children: [
                  Icon(Icons.cancel_outlined, color: Colors.redAccent, size: 16),
                  SizedBox(width: 8),
                  Expanded(child: Text(
                    "Provider cancelled. We're sorry for the inconvenience.",
                    style: TextStyle(color: Colors.redAccent, fontSize: 12),
                  )),
                ]),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () => Navigator.of(context).popUntil((r) => r.isFirst),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3A9010),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(child: Text(
                      "Find New Provider",
                      style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 13),
                    )),
                  ),
                ),
              ]),
            ),
          ] else if (status.contains('CANCELLED')) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.25)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.cancel_outlined, color: Colors.redAccent, size: 16),
                  SizedBox(width: 8),
                  Expanded(child: Text(
                    "Booking cancelled. Start a new request from the chat.",
                    style: TextStyle(color: Colors.redAccent, fontSize: 12),
                  )),
                ],
              ),
            ),
          ] else if (status == 'PENDING_PROVIDER') ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF3A9010).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF3A9010).withValues(alpha: 0.25)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF3A9010))),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      "Awaiting provider confirmation...",
                      style: TextStyle(color: Color(0xFF3A9010), fontSize: 12),
                    ),
                  ),
                  GestureDetector(
                    onTap: _refreshStatus,
                    child: const Icon(Icons.refresh_rounded, color: Color(0xFF3A9010), size: 18),
                  ),
                ],
              ),
            ),
          ] else if (status == 'ACCEPTED' || status == 'ARRIVING') ...[
            Row(children: [
              const Icon(Icons.directions_bike_rounded, size: 14, color: const Color(0xFF3A9010)),
              const SizedBox(width: 6),
              Text(
                "Provider is on the way — ${dist.toInt()} m away",
                style: const TextStyle(color: const Color(0xFF3E3F3B), fontSize: 12),
              ),
            ]),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: math.max(0.0, math.min(1.0, 1.0 - (dist / 1200.0))),
                backgroundColor: const Color(0xFFE8EDE6),
                valueColor: const AlwaysStoppedAnimation(const Color(0xFF3A9010)),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 12),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: const Color(0xFF3A9010))),
                SizedBox(width: 8),
                Text("Live GPS tracking active", style: TextStyle(color: const Color(0xFF565955), fontSize: 11)),
              ],
            ),
          ],

          if (status == 'ARRIVED' || status == 'IN_PROGRESS' || status == 'COMPLETED') ...[
            const Text(
              "Service Checklist",
              style: TextStyle(color: const Color(0xFF3E3F3B), fontSize: 12, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...List.generate(checklist.length, (idx) {
              final item = checklist[idx];
              final done = item['completed'] as bool? ?? false;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(
                      done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                      size: 15,
                      color: done ? const Color(0xFF3A9010) : const Color(0xFF767773),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      item['item'] ?? '',
                      style: TextStyle(
                        color: done ? const Color(0xFF565955) : const Color(0xFF21231D),
                        fontSize: 12,
                        decoration: done ? TextDecoration.lineThrough : null,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],

          if (status == 'COMPLETED') ...[
            const SizedBox(height: 14),
            const Divider(color: const Color(0xFFE8EDE6)),
            const SizedBox(height: 10),
            if (_starsSubmitted == 0) ...[
              const Text(
                "How was your experience?",
                style: TextStyle(color: const Color(0xFF21231D), fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) => GestureDetector(
                  onTap: () => _submitRating(i + 1),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(Icons.star_outline_rounded, color: Colors.amber, size: 28),
                  ),
                )),
              ),
            ] else ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.stars_rounded, color: Color(0xFF3A9010), size: 16),
                  const SizedBox(width: 6),
                  Text(
                    "You gave $_starsSubmitted / 5 stars. Thank you!",
                    style: const TextStyle(color: Color(0xFF163300), fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              if (_starsSubmitted <= 2 && !_disputeSubmitted) ...[
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: _showDisputeModal,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
                    ),
                    child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.report_outlined, color: Colors.redAccent, size: 14),
                      SizedBox(width: 6),
                      Text("Report an Issue", style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                    ]),
                  ),
                ),
              ] else if (_disputeSubmitted && _disputeResolution != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blueAccent.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.25)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Row(children: [
                      Icon(Icons.shield_outlined, color: Colors.blueAccent, size: 14),
                      SizedBox(width: 6),
                      Text("Dispute Filed", style: TextStyle(color: Colors.blueAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                    ]),
                    const SizedBox(height: 6),
                    Text(_disputeResolution!, style: const TextStyle(color: const Color(0xFF3E3F3B), fontSize: 11, height: 1.4)),
                  ]),
                ),
              ],
            ],
          ],
        ],
      ),
    );
  }
}
