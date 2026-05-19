import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math' as math;
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
        // Load booking state
        final res = await ApiService.get('bookings?customer_id=customer_001');
        if (res is List) {
          final b = res.firstWhere((x) => x['booking_id'] == widget.bookingId, orElse: () => null);
          if (b != null) {
            _addMsg(Message(text: "Booking ID: ${widget.bookingId}\nStatus: ${b['status']}\nService: ${b['service_type']}\nProvider: ${b['provider_name'] ?? 'Pending'}", isUser: false));
          } else {
            _addMsg(Message(text: "Booking not found.", isUser: false));
          }
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

  Future<void> _send([String? override]) async {
    final input = override ?? _ctrl.text.trim();
    final isSystemAction = override != null;
    if (input.isEmpty || (_inputDisabled && !isSystemAction)) return;
    _ctrl.clear();
    _addMsg(Message(text: input, isUser: true));
    setState(() { _loading = true; _inputDisabled = true; });

    // Remove thinking bubble if present
    setState(() => _messages.removeWhere((m) => m.type == 'thinking'));

    // Add typing indicator
    _addMsg(Message(text: '', isUser: false, type: 'thinking'));

    await Future.delayed(const Duration(milliseconds: 1000));

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
                _addMsg(Message(text: "Aap ka feedback submit ho gaya hai! Shukriya! 🙏", isUser: false));
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
      appBar: null, // Global AppBar is handled by CustomerHome!
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
        IconButton(
          icon: const Icon(Icons.refresh_rounded, color: Colors.white38, size: 20),
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
          decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white.withOpacity(0.07))),
          child: TextField(
            controller: _ctrl,
            enabled: !_inputDisabled,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: _inputDisabled ? "Intezaar karein..." : "Type naya request...",
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
  Timer? _timer;
  bool _simulating = false;
  bool _completed = false;
  int _starsSubmitted = 0;

  @override
  void initState() {
    super.initState();
    _booking = widget.booking;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _simulateStep() async {
    final bId = _booking['booking_id'];
    if (bId == null) return;

    try {
      final res = await ApiService.post('/booking/simulate-step', {'booking_id': bId});
      if (res['booking'] != null) {
        setState(() {
          _booking = res['booking'];
        });

        final dist = _booking['distance_meters'] as num? ?? 1000;
        if (dist <= 50) {
          _timer?.cancel();
          setState(() => _simulating = false);
          _simulateChecklist();
        }
      }
    } catch (e) {
      print("Simulation step error: $e");
    }
  }

  void _startSimulation() {
    setState(() => _simulating = true);
    _timer = Timer.periodic(const Duration(seconds: 2), (timer) {
      _simulateStep();
    });
  }

  Future<void> _simulateChecklist() async {
    final bId = _booking['booking_id'];
    if (bId == null) return;

    final checklist = _booking['checklist'] as List? ?? [];
    for (int i = 0; i < checklist.length; i++) {
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      try {
        final res = await ApiService.post('/booking/checklist', {
          'booking_id': bId,
          'item_index': i
        });
        if (res['booking'] != null) {
          setState(() {
            _booking = res['booking'];
          });
        }
      } catch (e) {
        print("Checklist progress error: $e");
      }
    }

    setState(() {
      _completed = true;
    });
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
      print("Rating submission error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _booking['status'] as String? ?? 'PENDING_PROVIDER';
    final dist = _booking['distance_meters'] as num? ?? 2000;
    final checklist = _booking['checklist'] as List? ?? [];

    Color statusColor = Colors.amber;
    if (status == 'ARRIVED' || status == 'IN_PROGRESS') statusColor = Colors.blueAccent;
    if (status == 'COMPLETED') statusColor = const Color(0xFF00C853);
    if (status.startsWith('CANCELLED')) statusColor = Colors.redAccent;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "🚚 Live Booking Status",
                style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.15),
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

          if (status == 'PENDING_PROVIDER' || status == 'ACCEPTED' || status == 'ARRIVING') ...[
            Row(
              children: [
                const Icon(Icons.location_on, size: 14, color: Colors.white38),
                const SizedBox(width: 6),
                Text(
                  "Provider Distance: ${dist} meters",
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: math.max(0.0, math.min(1.0, 1.0 - (dist / 2000.0))),
                backgroundColor: Colors.white10,
                valueColor: const AlwaysStoppedAnimation(Color(0xFF00C853)),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 16),
            if (!_simulating)
              GestureDetector(
                onTap: _startSimulation,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00C853),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Center(
                    child: Text(
                      "Start GPS Simulation",
                      style: TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              )
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00C853)),
                  ),
                  SizedBox(width: 8),
                  Text(
                    "Simulating movement (10% steps)...",
                    style: TextStyle(color: Colors.white60, fontSize: 11),
                  ),
                ],
              ),
          ],

          if (status == 'ARRIVED' || status == 'IN_PROGRESS' || status == 'COMPLETED') ...[
            const Text(
              "📋 Job Execution Checklist:",
              style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
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
                      color: done ? const Color(0xFF00C853) : Colors.white38,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      item['item'] ?? '',
                      style: TextStyle(
                        color: done ? Colors.white60 : Colors.white,
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
            const Divider(color: Colors.white10),
            const SizedBox(height: 10),
            if (_starsSubmitted == 0) ...[
              const Text(
                "⭐ Rate your experience:",
                style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
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
                  const Icon(Icons.stars_rounded, color: Colors.amber, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    "You rated this job $_starsSubmitted stars! Thank you!",
                    style: const TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}
