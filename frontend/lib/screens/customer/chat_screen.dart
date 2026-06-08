import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import '../../services/api_service.dart';
import '../../services/booking_events.dart';
import 'widgets/chat_widgets.dart';
import 'widgets/negotiation_widget.dart';
import 'widgets/privacy_badge_widget.dart';
import 'widgets/reliability_badge_widget.dart';
import 'widgets/recovery_widget.dart';
import 'dispute_detail_screen.dart';
class ActiveSessionService {
  static String? _sessionId;
  static String? _bookingId;
  static String? _serviceType;
  static List<Message> _messages = [];
  static Set<String> _actedIds = {};

  static void startSession(String sid) {
    _sessionId = sid;
    _bookingId = null;
    _serviceType = null;
    _messages = [];
    _actedIds = {};
  }

  static void saveMessages(List<Message> msgs, Set<String> acted) {
    _messages = List.from(msgs);
    _actedIds = Set.from(acted);
  }

  static void linkBooking(String bid, String svcType) {
    _bookingId = bid;
    _serviceType = svcType;
  }

  static void clear() {
    _sessionId = null;
    _bookingId = null;
    _serviceType = null;
    _messages = [];
    _actedIds = {};
  }

  static bool get hasActive => _sessionId != null || _bookingId != null;
  static String? get sessionId => _sessionId;
  static String? get bookingId => _bookingId;
  static String? get serviceType => _serviceType;
  static List<Message> get messages => _messages;
  static Set<String> get actedIds => _actedIds;
}

class ChatHistoryService {
  static final Map<String, List<Message>> _messages = {};
  static final Map<String, Set<String>> _actedIds = {};

  static void save(String bookingId, List<Message> msgs, Set<String> acted) {
    _messages[bookingId] = List.from(msgs);
    _actedIds[bookingId] = Set.from(acted);
  }

  static List<Message>? getMessages(String bookingId) => _messages[bookingId];
  static Set<String>? getActedIds(String bookingId) => _actedIds[bookingId];
}

class Message {
  final String id;
  final String text;
  final bool isUser;
  final String type; // text | thinking | booking_success | rating
  final Map<String, dynamic>? data;
  final List<String>? chips;

  Message(
      {required this.text,
      required this.isUser,
      this.type = 'text',
      this.data,
      this.chips})
      : id = UniqueKey().toString();
}

class ChatScreen extends StatefulWidget {
  final String? initialPrompt;
  final String? bookingId;
  final String? sessionId;
  final String? restoreHistoryFromBookingId;
  const ChatScreen({
    super.key,
    this.initialPrompt,
    this.bookingId,
    this.sessionId,
    this.restoreHistoryFromBookingId,
  });
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
  String? _bookingTitle;
  final Set<String> _actedMessages = {};
  Future<void> Function()? _cancelBookingFn;
  int _privacyRedactionCount = 0;
  final List<String> _redactedTypes = [];
  String _formatTitle(String? raw) {
    if (raw == null || raw.isEmpty) return 'New Booking';
    return raw
        .split('_')
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  @override
  void initState() {
    super.initState();
    _initSession();
  }

  @override
  void dispose() {
    if (widget.bookingId == null && _sessionId != null) {
      // Strip in-flight thinking bubble before saving so resume never gets stuck
      final toSave = _messages.where((m) => m.type != 'thinking').toList();
      ActiveSessionService.saveMessages(toSave, _actedMessages);
      BookingEvents.refresh();
    }
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _initSession() async {
    setState(() => _loading = true);
    try {
      if (widget.bookingId != null) {
        try {
          final b = await ApiService.get('booking/${widget.bookingId}');
          if (b is Map<String, dynamic> && b['booking_id'] != null) {
            final cached = ChatHistoryService.getMessages(widget.bookingId!);
            final cachedActed =
                ChatHistoryService.getActedIds(widget.bookingId!);
            setState(() {
              _bookingTitle = _formatTitle(b['service_type'] as String?);
              if (cached != null) {
                // Exclude booking_success from cache — fresh one is added below
                _messages.addAll(
                    cached.where((m) => m.type != 'booking_success'));
                if (cachedActed != null) _actedMessages.addAll(cachedActed);
              }
            });
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

      // ── Case 2: Rematch flow (Find New Provider) ──────────────────────
      if (widget.sessionId != null && widget.restoreHistoryFromBookingId != null) {
        _sessionId = widget.sessionId;
        ActiveSessionService.startSession(_sessionId!);
        final cached = ChatHistoryService.getMessages(widget.restoreHistoryFromBookingId!);
        final cachedActed = ChatHistoryService.getActedIds(widget.restoreHistoryFromBookingId!);
        if (cached != null) {
          setState(() {
            _messages.addAll(cached.where((m) => m.type != 'booking_success'));
            if (cachedActed != null) _actedMessages.addAll(cachedActed);
          });
        }
        _addMsg(Message(
            text: "Provider ne cancel kar diya. Aapke liye naya provider dhundta hun...",
            isUser: false));
        _addMsg(Message(text: '', isUser: false, type: 'thinking'));
        try {
          final res = await ApiService.orchestrate('doosra provider dhundo',
              [], sessionId: _sessionId);
          setState(() => _messages.removeWhere((m) => m.type == 'thinking'));
          _handleResponse(res);
        } catch (e) {
          setState(() => _messages.removeWhere((m) => m.type == 'thinking'));
          _addMsg(Message(text: "Error: $e", isUser: false));
        }
        setState(() => _loading = false);
        return;
      }

      // ── Case 3: Resume pre-booking session ────────────────────────────
      if (widget.sessionId != null && widget.restoreHistoryFromBookingId == null) {
        _sessionId = widget.sessionId;
        final saved = ActiveSessionService.messages;
        final savedActed = ActiveSessionService.actedIds;
        if (saved.isNotEmpty) {
          setState(() {
            _messages.addAll(saved.where((m) => m.type != 'thinking'));
            _actedMessages.addAll(savedActed);
          });
        }

        // If we have a user message but no AI response yet, the background
        // fetch may still be in-flight. Poll ActiveSessionService briefly
        // to see if _processSilent saves the result before we re-trigger.
        final lastUserMsg = _messages
            .where((m) => m.isUser && m.text.isNotEmpty)
            .lastOrNull;
        final hasAiResponse =
            _messages.any((m) => !m.isUser && m.type != 'thinking');

        if (lastUserMsg != null && !hasAiResponse) {
          _addMsg(Message(text: '', isUser: false, type: 'thinking'));

          // Wait up to 5 seconds for the background orchestrate to finish
          for (int i = 0; i < 10; i++) {
            await Future.delayed(const Duration(milliseconds: 500));
            final latest = ActiveSessionService.messages;
            final gotResult =
                latest.any((m) => !m.isUser && m.type != 'thinking');
            if (gotResult) {
              if (!mounted) return;
              setState(() {
                _messages.clear();
                _messages.addAll(
                    latest.where((m) => m.type != 'thinking'));
                _actedMessages.addAll(ActiveSessionService.actedIds);
              });
              _scrollBottom();
              setState(() => _loading = false);
              return;
            }
          }

          // Background didn't finish in time — create a FRESH session so we
          // don't re-send to the old session which may be in wrong phase.
          if (!mounted) return;
          setState(() => _messages.removeWhere((m) => m.type == 'thinking'));
          try {
            final freshSess = await ApiService.createSession("customer_001");
            _sessionId = freshSess['session_id'] as String?;
            if (_sessionId != null) ActiveSessionService.startSession(_sessionId!);

            _addMsg(Message(text: '', isUser: false, type: 'thinking'));
            final response = await ApiService.orchestrate(
                lastUserMsg.text, [], sessionId: _sessionId);
            if (!mounted) {
              _processSilent(response);
              ActiveSessionService.saveMessages(
                  _messages.where((m) => m.type != 'thinking').toList(),
                  _actedMessages);
              return;
            }
            setState(() => _messages.removeWhere((m) => m.type == 'thinking'));
            _handleResponse(response);
          } catch (e) {
            if (!mounted) return;
            setState(() => _messages.removeWhere((m) => m.type == 'thinking'));
            _addMsg(Message(
                text: "Providers dhundhne mein masla aaya. Dobara try karein.",
                isUser: false));
          }
        }

        setState(() => _loading = false);
        return;
      }

      // ── Case 4: New session ───────────────────────────────────────────
      final res = await ApiService.createSession("customer_001");
      _sessionId = res['session_id'];
      ActiveSessionService.startSession(_sessionId!);

      if (widget.initialPrompt != null && widget.initialPrompt!.isNotEmpty) {
        _addMsg(Message(text: widget.initialPrompt!, isUser: true));
        _addMsg(Message(text: '', isUser: false, type: 'thinking'));
        final response = await ApiService.orchestrate(widget.initialPrompt!, [],
            sessionId: _sessionId);
        _messages.removeWhere((m) => m.type == 'thinking');
        if (!mounted) {
          // Widget disposed while loading — save result so resume works
          _processSilent(response);
          ActiveSessionService.saveMessages(_messages, _actedMessages);
          return;
        }
        setState(() {});
        _handleResponse(response);
      } else {
        final greeting =
            await ApiService.orchestrate("", [], sessionId: _sessionId);
        if (!mounted) return;
        _handleResponse(greeting);
      }
    } catch (e) {
      if (!mounted) return; // widget disposed during async work — no setState
      _addMsg(Message(
          text: "Connection error: $e. Please refresh.", isUser: false));
      setState(() => _loading = false);
    }
  }

  void _scrollBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients)
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    });
  }

  void _addMsg(Message msg) {
    if (!mounted) {
      _messages.add(msg); // safe: just mutate list, no setState
      return;
    }
    setState(() => _messages.add(msg));
    _scrollBottom();
  }

  List<Map<String, String>> _buildHistory() {
    return _messages
        .where((m) => m.type == 'text' && m.text.isNotEmpty)
        .map((m) => {
              'role': m.isUser ? 'user' : 'model',
              'content': m.isUser ? _redactForHistory(m.text) : m.text,
            })
        .toList();
  }

  // Strips Pakistani phone numbers and emails from history before sending to backend.
  static String _privacyNoticeText(List<String> types) {
    const labels = {
      'phone': 'phone number',
      'email': 'email address',
      'cnic': 'CNIC',
      'address': 'address',
    };
    final named = types.map((t) => labels[t] ?? t).toList();
    final joined = named.length == 1
        ? named[0]
        : '${named.sublist(0, named.length - 1).join(', ')} and ${named.last}';
    return 'Your $joined is safe. We never share your personal information with AI.';
  }

  // The user still sees the original text in their own chat bubble.
  static String _redactForHistory(String text) {
    var out = text;
    out = out.replaceAllMapped(
      RegExp(r'(\+92|0092|0)([-\s]?)(3\d{2})([-\s]?)\d{7}'),
      (_) => '[PHONE]',
    );
    out = out.replaceAllMapped(
      RegExp(r'\b[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}\b'),
      (_) => '[EMAIL]',
    );
    return out;
  }

  Future<void> _send([String? override]) async {
    final input = override ?? _ctrl.text.trim();
    final isSystemAction = override != null;
    if (input.isEmpty || (_inputDisabled && !isSystemAction)) return;
    _ctrl.clear();
    final history = _buildHistory();
    _addMsg(Message(text: input, isUser: true));
    setState(() {
      _loading = true;
      _inputDisabled = true;
    });

    // Remove thinking bubble if present
    setState(() => _messages.removeWhere((m) => m.type == 'thinking'));

    // Add typing indicator
    _addMsg(Message(text: '', isUser: false, type: 'thinking'));

    await Future.delayed(const Duration(milliseconds: 1000));

    try {
      final res =
          await ApiService.orchestrate(input, history, sessionId: _sessionId);
      setState(() => _messages.removeWhere((m) => m.type == 'thinking'));
      _handleResponse(res);
    } catch (e) {
      setState(() {
        _messages.removeWhere((m) => m.type == 'thinking');
        _loading = false;
        _inputDisabled = false;
      });
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

    // Always track guardrail redactions regardless of phase
    final guardrailStep = (res['trace'] as List?)?.firstWhere(
      (s) => s is Map && s['agent'] == 'Guardrail', orElse: () => null);
    final redactionList = (guardrailStep?['output']?['redactions'] as List?) ?? [];
    if (redactionList.isNotEmpty) {
      final types = <String>[];
      for (final r in redactionList) {
        final t = (r as Map?)?['type'] as String?;
        if (t != null) {
          if (!_redactedTypes.contains(t)) _redactedTypes.add(t);
          if (!types.contains(t)) types.add(t);
        }
      }
      setState(() => _privacyRedactionCount += redactionList.length);
      // Show inline privacy notice in the chat
      _addMsg(Message(
        text: _privacyNoticeText(types),
        isUser: false,
        type: 'privacy_notice',
      ));
    }

    if (phase == 'booking_confirmed') {
      final bookingId = res['booking']?['booking_id'] as String?;
      final steps = (res['thinking_steps'] as List?)?.cast<String>();
      setState(() {
        _inputDisabled = false;
        _bookingTitle =
            _formatTitle(res['booking']?['service_type'] as String?);
      });

      final negotiationTrace = res['negotiation_trace'] as Map<String, dynamic>?;
      final contractId = res['contract_id'] as String?;

      // Provider reliability score from match result
      final topProvider = (res['match_result']?['top_providers'] as List?)?.firstOrNull;
      final reliabilityScore = (topProvider?['reliability_score'] as num?)?.toDouble();

      void showSuccess() {
        // Show A2A negotiation trace as animated bubbles
        if (negotiationTrace != null) {
          _addMsg(Message(
            text: '',
            isUser: false,
            type: 'negotiation',
            data: {'trace': negotiationTrace, 'contract_id': contractId},
          ));
        }
        _addMsg(Message(
            text: msg,
            isUser: false,
            type: 'booking_success',
            data: {
              ...?res['booking'] as Map<String, dynamic>?,
              if (reliabilityScore != null) '_reliability_score': reliabilityScore,
            }));
        if (bookingId != null) {
          ChatHistoryService.save(bookingId, _messages, _actedMessages);
          ActiveSessionService.linkBooking(
              bookingId, res['booking']?['service_type'] as String? ?? '');
          BookingEvents.refresh();
        }
      }

      if (steps != null && steps.isNotEmpty) {
        _addMsg(Message(
            text: '', isUser: false, type: 'thinking', data: {'steps': steps}));
        Future.delayed(Duration(milliseconds: 400 * steps.length + 300), () {
          if (!mounted) return;
          setState(() => _messages.removeWhere((m) => m.type == 'thinking'));
          showSuccess();
        });
      } else {
        showSuccess();
      }
    } else if (phase == 'safety_warning' || phase == 'session_blocked' || phase == 'account_suspended') {
      _addMsg(Message(text: msg, isUser: false, type: 'safety_warning',
          data: {'severity': phase}, chips: chips));
    } else {
      _addMsg(Message(text: msg, isUser: false, chips: chips));
    }
    if (_sessionId != null && widget.bookingId == null) {
      ActiveSessionService.saveMessages(_messages, _actedMessages);
    }
  }

  // Processes an AI response into _messages without calling setState.
  // Used when the widget is already disposed (user went back mid-flight).
  void _processSilent(Map<String, dynamic> res) {
    final phase = res['phase'] as String? ?? '';
    final msg = res['message'] as String? ?? '';
    final chips = (res['chips'] as List?)?.cast<String>();

    if (phase == 'booking_confirmed') {
      final bookingId = res['booking']?['booking_id'] as String?;
      _messages.add(Message(
          text: msg, isUser: false, type: 'booking_success', data: res['booking']));
      if (bookingId != null) {
        final svcType = res['booking']?['service_type'] as String? ?? '';
        ChatHistoryService.save(bookingId, _messages, _actedMessages);
        ActiveSessionService.linkBooking(bookingId, svcType);
        BookingEvents.refresh();
      }
    } else {
      _messages.add(Message(text: msg, isUser: false, chips: chips));
    }
  }

  Widget _buildBubble(Message msg, int index) {
    if (msg.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 5),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.72),
          decoration: const BoxDecoration(
            color: const Color(0xFF163300),
            borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
                bottomLeft: Radius.circular(20)),
          ),
          child: Text(msg.text,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600)),
        ),
      );
    }

    switch (msg.type) {
      case 'privacy_notice':
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_outline, size: 12, color: Color(0xFF079455)),
              const SizedBox(width: 5),
              Text(
                msg.text,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: Color(0xFF079455),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );

      case 'thinking':
        final steps = (msg.data?['steps'] as List?)?.cast<String>();
        return ThinkingBubble(steps: steps);

      case 'negotiation':
        final trace = msg.data?['trace'] as Map<String, dynamic>?;
        if (trace == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: NegotiationWidget(
            negotiationTrace: trace,
            contractId: msg.data?['contract_id'] as String?,
          ),
        );

      case 'safety_warning':
        final severity = msg.data?['severity'] as String? ?? 'safety_warning';
        final isBlocked = severity == 'session_blocked' || severity == 'account_suspended';
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _SafetyWarningBubble(message: msg.text, isBlocked: isBlocked),
          if (msg.chips != null && msg.chips!.isNotEmpty && !isBlocked) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.82),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4),
                    topRight: Radius.circular(18),
                    bottomLeft: Radius.circular(18),
                    bottomRight: Radius.circular(18),
                  ),
                  border: Border.all(color: const Color(0xFFE8EDE6)),
                ),
                child: const Text(
                  'Agar aapko koi home service chahiye ho toh inn mein se select karein:',
                  style: TextStyle(
                      fontSize: 13, color: Color(0xFF3E3F3B), height: 1.45)),
              ),
            ),
            Wrap(
              spacing: 8, runSpacing: 6,
              children: msg.chips!.map((c) => GestureDetector(
                onTap: () => _send(c),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF3A9010).withValues(alpha: 0.4)),
                  ),
                  child: Text(c, style: const TextStyle(
                      color: Color(0xFF3A9010), fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              )).toList(),
            ),
          ],
        ]);

      case 'booking_success':
        final bk = msg.data ?? {};
        final reliability = (bk['_reliability_score'] as num?)?.toDouble();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (reliability != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: ReliabilityBadgeWidget(score: reliability),
              ),
            SuccessBubble(
              providerName: bk['provider_name'] ?? 'Provider',
              scheduledTime: bk['scheduled_time'] != null
                  ? bk['scheduled_time'].toString().substring(0, 16)
                  : 'Tomorrow',
              price: (bk['final_price'] as num?)?.toInt() ?? 1000,
              bookingId: bk['booking_id'] ?? 'BK-XXXX',
              checklist: bk['checklist'] ?? [],
            ),
            LiveTrackingWidget(
              booking: bk,
              onRated: (stars) {
                _addMsg(Message(
                    text:
                        "Your rating has been submitted. Thank you for using Haazir!",
                    isUser: false));
              },
              onReassigned: (newBooking, attempt, recovery) {
                if (recovery != null) {
                  _addMsg(Message(
                    text: '',
                    isUser: false,
                    type: 'recovery',
                    data: {'newBooking': newBooking, 'recovery': recovery},
                  ));
                } else {
                  final name = newBooking['provider_name'] ?? 'Naya Provider';
                  _addMsg(Message(
                    text: "Attempt $attempt: $name assigned.",
                    isUser: false,
                    type: 'booking_reassigned',
                    data: newBooking,
                  ));
                }
              },
              onCancelReady: (fn) {
                if (mounted) setState(() => _cancelBookingFn = fn);
              },
            ),
          ],
        );

      case 'recovery':
        final rec = msg.data?['recovery'] as Map<String, dynamic>?;
        final nb  = msg.data?['newBooking'] as Map<String, dynamic>?;
        if (rec == null) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: RecoveryWidget(
                apologyMessage: rec['apology_message'] as String? ?? '',
                compensation: (rec['compensation'] as Map?)?.cast<String, dynamic>() ?? {},
                newBooking: nb,
                cause: rec['cause'] as String? ?? 'provider_emergency',
              ),
            ),
            if (nb != null) ...[
              SuccessBubble(
                providerName: nb['provider_name'] ?? 'Naya Provider',
                scheduledTime: nb['scheduled_time'] != null
                    ? nb['scheduled_time'].toString().substring(0, 16)
                    : 'Tomorrow',
                price: (nb['final_price'] as num?)?.toInt() ?? 0,
                bookingId: nb['booking_id'] ?? '',
                checklist: nb['checklist'] ?? [],
              ),
              LiveTrackingWidget(
                booking: nb,
                onRated: (stars) {
                  _addMsg(Message(
                      text: "Your rating has been submitted. Thank you for using Haazir!",
                      isUser: false));
                },
                onReassigned: (newBooking2, attempt2, recovery2) {
                  if (recovery2 != null) {
                    _addMsg(Message(
                      text: '',
                      isUser: false,
                      type: 'recovery',
                      data: {'newBooking': newBooking2, 'recovery': recovery2},
                    ));
                  } else {
                    _addMsg(Message(
                      text: "Attempt $attempt2: ${newBooking2['provider_name'] ?? 'Naya Provider'} assigned.",
                      isUser: false,
                      type: 'booking_reassigned',
                      data: newBooking2,
                    ));
                  }
                },
                onCancelReady: (fn) {
                  if (mounted) setState(() => _cancelBookingFn = fn);
                },
              ),
            ],
          ],
        );

      case 'booking_reassigned':
        final bk = msg.data ?? {};
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _textBubble(msg.text),
            SuccessBubble(
              providerName: bk['provider_name'] ?? 'Provider',
              scheduledTime: bk['scheduled_time'] != null
                  ? bk['scheduled_time'].toString().substring(0, 16)
                  : 'Tomorrow',
              price: (bk['final_price'] as num?)?.toInt() ?? 1000,
              bookingId: bk['booking_id'] ?? 'BK-XXXX',
              checklist: bk['checklist'] ?? [],
            ),
          ],
        );

      default:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _textBubble(msg.text),
          if (msg.chips != null && msg.chips!.isNotEmpty)
            ChipRow(
              chips: msg.chips!,
              disabled: _actedMessages.contains(msg.id),
              onTap: (chip) {
                setState(() => _actedMessages.add(msg.id));
                _send(chip);
              },
            ),
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
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
              bottomRight: Radius.circular(20)),
          border: Border.all(color: const Color(0xFFE8EDE6)),
        ),
        child: Text(text,
            style: const TextStyle(
                color: Color(0xFF3E3F3B), fontSize: 14, height: 1.5)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAF5),
      appBar: _buildAppBar(),
      body: Column(children: [
        Expanded(
            child: ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          itemCount: _messages.length,
          itemBuilder: (ctx, i) => KeyedSubtree(
            key: ObjectKey(_messages[i]),
            child: _buildBubble(_messages[i], i),
          ),
        )),
        if (_loading)
          const Padding(
              padding: EdgeInsets.all(8),
              child: Center(
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: const Color(0xFF3A9010))))),
        if (_cancelBookingFn != null) _buildCancelBookingBar(),
        if (!_messages.any((m) => m.type == 'booking_success') &&
            widget.bookingId == null)
          _buildInput(),
      ]),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF163300),
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_rounded,
            color: Colors.white, size: 18),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: Text(_bookingTitle ?? 'New Booking',
          style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white)),
      actions: [
        if (_sessionId != null)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: const PrivacyBadgeWidget(),
          ),
        Container(
          margin: const EdgeInsets.only(right: 12),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
          ),
          child: const Row(children: [
            Icon(Icons.person_rounded, size: 16, color: Colors.white),
            SizedBox(width: 4),
            Text('Customer',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white)),
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
      decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: const Color(0xFFE8EDE6)))),
      child: Row(children: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded,
              color: const Color(0xFF767773), size: 20),
          onPressed: () {
            setState(() {
              _messages.clear();
              _inputDisabled = false;
            });
            _initSession();
          },
        ),
        Expanded(
            child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
              color: const Color(0xFFF7FAF5),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE8EDE6))),
          child: TextField(
            controller: _ctrl,
            enabled: !_inputDisabled,
            style: const TextStyle(color: const Color(0xFF21231D)),
            decoration: InputDecoration(
              hintText: _inputDisabled
                  ? "Please wait..."
                  : "What do you need help with?",
              hintStyle:
                  const TextStyle(color: const Color(0xFF767773), fontSize: 13),
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
            decoration: BoxDecoration(
                color: _inputDisabled
                    ? const Color(0xFFE8EDE6)
                    : const Color(0xFF3A9010),
                shape: BoxShape.circle),
            child: Icon(Icons.send_rounded,
                color: _inputDisabled ? const Color(0xFF767773) : Colors.white,
                size: 18),
          ),
        ),
      ]),
    );
  }

  Widget _buildCancelBookingBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE8EDE6))),
      ),
      child: GestureDetector(
        onTap: () async {
          final fn = _cancelBookingFn;
          setState(() => _cancelBookingFn = null);
          await fn?.call();
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.redAccent.withValues(alpha: 0.45)),
          ),
          child: const Center(
            child: Text(
              "Cancel Booking",
              style: TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Safety warning bubble ─────────────────────────────────────────────────────
class _SafetyWarningBubble extends StatelessWidget {
  final String message;
  final bool isBlocked; // true = session/account blocked, false = single warning

  const _SafetyWarningBubble({required this.message, this.isBlocked = false});

  @override
  Widget build(BuildContext context) {
    final color = isBlocked ? const Color(0xFFda2721) : const Color(0xFFe67e00);
    final icon  = isBlocked ? Icons.block_rounded : Icons.warning_amber_rounded;
    final label = isBlocked ? 'Access Blocked' : 'Content Warning';

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.82),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: const BorderRadius.only(
            topLeft:     Radius.circular(4),
            topRight:    Radius.circular(18),
            bottomLeft:  Radius.circular(18),
            bottomRight: Radius.circular(18),
          ),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            margin: const EdgeInsets.only(top: 1, right: 10),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700,
                    color: color, letterSpacing: 0.3)),
            const SizedBox(height: 3),
            Text(message,
                style: TextStyle(
                    fontSize: 13, height: 1.45,
                    color: color.withValues(alpha: 0.85))),
          ])),
        ]),
      ),
    );
  }
}

// ── MAP VIEW: provider approaching customer ──────────────────────────────
class _ProviderMapView extends StatefulWidget {
  final String customerLocation;
  final double distanceMeters;

  const _ProviderMapView({
    required this.customerLocation,
    required this.distanceMeters,
  });

  @override
  State<_ProviderMapView> createState() => _ProviderMapViewState();
}

class _ProviderMapViewState extends State<_ProviderMapView> {
  static final _cache = <String, ll.LatLng>{};
  ll.LatLng? _customerCoords;

  @override
  void initState() {
    super.initState();
    _resolveCoords(widget.customerLocation);
  }

  @override
  void didUpdateWidget(_ProviderMapView old) {
    super.didUpdateWidget(old);
    if (old.customerLocation != widget.customerLocation) {
      _resolveCoords(widget.customerLocation);
    }
  }

  Future<void> _resolveCoords(String location) async {
    final key = location.toLowerCase().trim();
    if (_cache.containsKey(key)) {
      if (mounted) setState(() => _customerCoords = _cache[key]);
      return;
    }
    final coords = await _nominatim(location);
    _cache[key] = coords;
    if (mounted) setState(() => _customerCoords = coords);
  }

  Future<ll.LatLng> _nominatim(String location) async {
    try {
      final query = location.toLowerCase().contains('pakistan')
          ? location
          : '$location, Pakistan';
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': query,
        'format': 'json',
        'limit': '1',
      });
      final res = await http.get(uri,
          headers: {'User-Agent': 'HaazirApp/1.0'});
      final data = jsonDecode(res.body) as List<dynamic>;
      if (data.isNotEmpty) {
        return ll.LatLng(
          double.parse(data[0]['lat'] as String),
          double.parse(data[0]['lon'] as String),
        );
      }
    } catch (_) {}
    return const ll.LatLng(33.6938, 73.0551); // fallback: Islamabad
  }

  ll.LatLng _providerPos(ll.LatLng customer) {
    const bearing = 315.0 * math.pi / 180.0;
    final dKm = widget.distanceMeters.clamp(50, 2000) / 1000.0;
    const R = 6371.0;
    final lat1 = customer.latitude * math.pi / 180;
    final lon1 = customer.longitude * math.pi / 180;
    final lat2 = math.asin(math.sin(lat1) * math.cos(dKm / R) +
        math.cos(lat1) * math.sin(dKm / R) * math.cos(bearing));
    final lon2 = lon1 +
        math.atan2(math.sin(bearing) * math.sin(dKm / R) * math.cos(lat1),
            math.cos(dKm / R) - math.sin(lat1) * math.sin(lat2));
    return ll.LatLng(lat2 * 180 / math.pi, lon2 * 180 / math.pi);
  }

  @override
  Widget build(BuildContext context) {
    if (_customerCoords == null) {
      return Container(
        height: 230,
        decoration: BoxDecoration(
          color: const Color(0xFFE8EDE6),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(
          child: CircularProgressIndicator(
              strokeWidth: 2, color: Color(0xFF3A9010)),
        ),
      );
    }
    final customer = _customerCoords!;
    final provider = _providerPos(customer);
    final midLat = (customer.latitude + provider.latitude) / 2;
    final midLng = (customer.longitude + provider.longitude) / 2;
    final zoom = widget.distanceMeters > 900
        ? 13.8
        : widget.distanceMeters > 400
            ? 14.8
            : 15.8;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 230,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: ll.LatLng(midLat, midLng),
            initialZoom: zoom,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.pinchZoom | InteractiveFlag.doubleTapZoom,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.haazir.app',
            ),
            PolylineLayer(polylines: [
              Polyline(
                  points: [provider, customer],
                  color: const Color(0xFF3A9010),
                  strokeWidth: 4),
            ]),
            MarkerLayer(markers: [
              Marker(
                point: customer,
                width: 40,
                height: 48,
                child: Column(children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: const BoxDecoration(
                        color: Color(0xFF163300), shape: BoxShape.circle),
                    child: const Icon(Icons.home_rounded,
                        color: Colors.white, size: 18),
                  ),
                  CustomPaint(
                      size: const Size(12, 7),
                      painter: _PinTip(const Color(0xFF163300))),
                ]),
              ),
              Marker(
                point: provider,
                width: 44,
                height: 44,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF3A9010),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF3A9010).withValues(alpha: 0.45),
                        blurRadius: 10,
                        spreadRadius: 2,
                      )
                    ],
                  ),
                  child: const Icon(Icons.directions_bike_rounded,
                      color: Colors.white, size: 22),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _PinTip extends CustomPainter {
  final Color color;
  const _PinTip(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..lineTo(size.width / 2, size.height)
        ..lineTo(size.width, 0)
        ..close(),
      Paint()..color = color,
    );
  }
  @override
  bool shouldRepaint(_PinTip old) => old.color != color;
}

// ── STATEFUL LIVE TRACKING & SIMULATION WIDGET ────────────────────────────
class LiveTrackingWidget extends StatefulWidget {
  final Map<String, dynamic> booking;
  final Function(int stars) onRated;
  final void Function(Map<String, dynamic> newBooking, int attempt, Map<String, dynamic>? recovery)? onReassigned;
  final void Function(Future<void> Function()?)? onCancelReady;

  const LiveTrackingWidget({
    super.key,
    required this.booking,
    required this.onRated,
    this.onReassigned,
    this.onCancelReady,
  });

  @override
  State<LiveTrackingWidget> createState() => _LiveTrackingWidgetState();
}

class _LiveTrackingWidgetState extends State<LiveTrackingWidget>
    with AutomaticKeepAliveClientMixin {
  // Session-scoped guard: once a booking triggers auto-reassign, never repeat it
  // even if the widget scrolls off-screen and is recreated.
  static final _handledReassignments = <String>{};

  @override
  bool get wantKeepAlive => true;

  late Map<String, dynamic> _booking;
  Timer? _gpsTimer;
  Timer? _pollTimer;
  bool _simulating = false;
  int _starsSubmitted = 0;
  String? _activeDisputeId;
  Map<String, dynamic>? _summary;
  bool _summaryLoading = false;
  bool _autoRetrying = false;
  bool _noProviderFound = false;
  int _retryAttempt = 0;

  void _syncDisputeId() {
    final id = _booking['dispute_id'] as String?;
    if (id != null && _activeDisputeId == null && mounted) {
      _activeDisputeId = id;
    }
  }

  @override
  void initState() {
    super.initState();
    _booking = widget.booking;
    _syncDisputeId();
    // Defer so we don't call setState on the parent during its own build phase
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final s = _booking['status'] as String? ?? '';
      // Show cancel only while still pending or during reassignment
      if (s == 'PENDING_PROVIDER' || s == 'CANCELLED_PROVIDER' || s == 'CANCELLED_TIMEOUT') {
        widget.onCancelReady?.call(_cancelAndEnd);
      } else {
        widget.onCancelReady?.call(null);
      }
    });
    final status = _booking['status'] as String? ?? '';
    final reassignedTo = _booking['reassigned_to'] as String?;
    if (status == 'SCHEDULED') {
      _startPolling(); // keep polling in case provider starts early
    } else if (status == 'ACCEPTED' || status == 'ARRIVING') {
      _startPolling();
      Future.delayed(const Duration(milliseconds: 600), _startSimulation);
    } else if ((status == 'CANCELLED_PROVIDER' || status == 'CANCELLED_TIMEOUT') &&
        reassignedTo != null) {
      Future.microtask(_resumeFromChain);
    } else if (status == 'CANCELLED_PROVIDER' || status == 'CANCELLED_TIMEOUT') {
      final bookingId = _booking['booking_id'] as String? ?? '';
      if (bookingId.isNotEmpty && !_handledReassignments.contains(bookingId)) {
        _handledReassignments.add(bookingId);
        Future.microtask(_autoReassign);
      }
    } else {
      _startPolling();
    }
  }

  Future<void> _resumeFromChain() async {
    String nextId = (_booking['reassigned_to'] as String?) ?? '';
    while (nextId.isNotEmpty) {
      try {
        final res = await ApiService.get('booking/$nextId');
        if (!mounted) return;
        if (res is! Map<String, dynamic> || res['booking_id'] == null) break;
        final chainNext = res['reassigned_to'] as String?;
        if (chainNext != null && chainNext.isNotEmpty) {
          nextId = chainNext;
        } else {
          setState(() { _booking = res; _syncDisputeId(); });
          final latestStatus = res['status'] as String? ?? '';
          if (latestStatus == 'CANCELLED_PROVIDER' || latestStatus == 'CANCELLED_TIMEOUT') {
            _autoReassign();
          } else if (latestStatus == 'SCHEDULED') {
            _startPolling();
          } else if (latestStatus == 'ACCEPTED' || latestStatus == 'ARRIVING') {
            _startPolling();
            Future.delayed(const Duration(milliseconds: 600), _startSimulation);
          } else {
            _startPolling();
          }
          return;
        }
      } catch (_) { break; }
    }
    _startPolling();
  }

  @override
  void dispose() {
    _gpsTimer?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer =
        Timer.periodic(const Duration(seconds: 2), (_) => _refreshStatus());
  }

  Future<void> _refreshStatus() async {
    final bId = _booking['booking_id'];
    if (bId == null) return;
    try {
      final res = await ApiService.get('booking/$bId');
      if (!mounted) return;
      // Discard stale response if _booking was updated to a new booking while in-flight
      if (_booking['booking_id'] != bId) return;
      if (res is Map<String, dynamic> && res['booking_id'] != null) {
        final prevStatus = _booking['status'] as String? ?? '';
        final newStatus = res['status'] as String? ?? '';
        setState(() { _booking = res; _syncDisputeId(); });
        // Manage cancel button visibility based on new status
        if (newStatus == 'ACCEPTED' || newStatus == 'ARRIVING' ||
            newStatus == 'ARRIVED' || newStatus == 'IN_PROGRESS') {
          widget.onCancelReady?.call(null); // hide once provider is engaged
        } else if (newStatus == 'CANCELLED_PROVIDER' || newStatus == 'CANCELLED_TIMEOUT') {
          widget.onCancelReady?.call(_cancelAndEnd); // show during reassignment
        }
        // Start GPS simulation when provider goes active (from any pre-transit status)
        if ((newStatus == 'ACCEPTED' || newStatus == 'ARRIVING') &&
            (prevStatus == 'PENDING_PROVIDER' || prevStatus == 'SCHEDULED') &&
            !_simulating) {
          _startSimulation();
        }
        // Stop polling when fully resolved
        if (newStatus == 'COMPLETED' || newStatus.startsWith('CANCELLED')) {
          _pollTimer?.cancel();
          _pollTimer = null;
          if (newStatus == 'COMPLETED') {
            ActiveSessionService.clear();
            BookingEvents.refresh();
            if (_summary == null && !_summaryLoading) _loadSummary(bId as String);
            widget.onCancelReady?.call(null); // hide Cancel Booking bar
          }
          // Auto-search next provider on provider/timeout cancel
          if ((newStatus == 'CANCELLED_PROVIDER' || newStatus == 'CANCELLED_TIMEOUT') &&
              !_noProviderFound &&
              !_autoRetrying) {
            final cancelledId = bId as String? ?? '';
            if (cancelledId.isNotEmpty && !_handledReassignments.contains(cancelledId)) {
              _handledReassignments.add(cancelledId);
              _autoReassign();
            }
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _autoReassign() async {
    if (!mounted) return;
    _pollTimer?.cancel();
    _pollTimer = null;
    setState(() => _autoRetrying = true);
    final bId = _booking['booking_id'];
    if (bId == null) {
      setState(() { _autoRetrying = false; _noProviderFound = true; });
      return;
    }
    try {
      final res = await ApiService.post('/booking/auto-reassign', {'booking_id': bId});
      if (!mounted) return;
      if (res['status'] == 'no_provider') {
        // Auto-cancel so the chain tip moves to History immediately
        final bId2 = _booking['booking_id'];
        if (bId2 != null) {
          try {
            await ApiService.post('/booking/status',
                {'booking_id': bId2, 'status': 'CANCELLED_CUSTOMER', 'caller_id': 'customer_001'});
          } catch (_) {}
        }
        BookingEvents.refresh();
        widget.onCancelReady?.call(null);
        setState(() { _autoRetrying = false; _noProviderFound = true; });
        return;
      }
      if (res['status'] == 'reassigned' && res['booking'] != null) {
        final newBooking = res['booking'] as Map<String, dynamic>;
        final attempt = res['attempt'] as int? ?? _retryAttempt + 1;
        final recovery = res['recovery'] as Map<String, dynamic>?;
        setState(() {
          _booking = newBooking;
          _retryAttempt = attempt;
          _autoRetrying = false;
        });
        // Fire the callback — chat screen will add a NEW LiveTrackingWidget for newBooking.
        // That new widget owns polling from here. This widget must NOT also poll the same
        // booking, or both will call _autoReassign on the next cancellation (exponential loop).
        widget.onReassigned?.call(newBooking, attempt, recovery);
        // Do NOT call _startPolling() here — new widget takes over.
      }
    } catch (_) {
      if (mounted) setState(() { _autoRetrying = false; _noProviderFound = true; });
    }
  }

  Future<void> _cancelAndEnd() async {
    setState(() => _autoRetrying = false);
    final bId = _booking['booking_id'];
    if (bId != null) {
      try {
        await ApiService.post('/booking/status', {'booking_id': bId, 'status': 'CANCELLED_CUSTOMER', 'caller_id': 'customer_001'});
      } catch (_) {}
    }
    ActiveSessionService.clear();
    BookingEvents.refresh();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _loadSummary(String bookingId) async {
    if (!mounted) return;
    setState(() => _summaryLoading = true);
    try {
      final res = await ApiService.generateSummary(bookingId);
      if (mounted && res['summary'] != null) {
        setState(() {
          _summary = res['summary'] as Map<String, dynamic>;
          _summaryLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _summaryLoading = false);
    }
  }

  String _formatScheduledTime(String? raw) {
    if (raw == null || raw.isEmpty) return 'Date TBD';
    try {
      final dt = DateTime.parse(raw.length < 20 ? '${raw}:00' : raw).toLocal();
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      final ampm = dt.hour >= 12 ? 'PM' : 'AM';
      final min = dt.minute.toString().padLeft(2, '0');
      return '${days[dt.weekday - 1]}, ${dt.day} ${months[dt.month - 1]} at $h:$min $ampm';
    } catch (_) {
      return raw;
    }
  }

  void _startSimulation() {
    if (_simulating) return;
    setState(() => _simulating = true);
    _gpsTimer =
        Timer.periodic(const Duration(seconds: 1), (_) => _simulateStep());
  }

  Future<void> _simulateStep() async {
    final bId = _booking['booking_id'];
    if (bId == null) return;
    try {
      final res =
          await ApiService.post('/booking/simulate-step', {'booking_id': bId});
      if (!mounted) return;
      final bookingData = res['booking'] as Map<String, dynamic>?;
      if (bookingData != null) {
        setState(() { _booking = bookingData; _syncDisputeId(); });
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
      final res = await ApiService.post(
          '/booking/submit-rating', {'booking_id': bId, 'stars': stars});
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

  // Returns the dispute_id on success, null on failure.
  Future<String?> _doRaiseDispute(String bookingId, String type, String comment) async {
    try {
      final res = await ApiService.post('/dispute/raise', {
        'booking_id': bookingId,
        'type': type,
        'comment': comment,
      });
      if (res['error'] != null) {
        debugPrint('Dispute API error: ${res['error']}');
        return null;
      }
      final id = res['dispute_id'] as String?;
      if (id != null && mounted) setState(() => _activeDisputeId = id);
      return id;
    } catch (e) {
      debugPrint('Dispute error: $e');
      return null;
    }
  }

  Future<void> _showDisputeModal() async {
    // Build provider chain (fetch previous booking if this was reassigned)
    final chain = <Map<String, dynamic>>[
      {
        'booking_id': _booking['booking_id'],
        'provider_name': _booking['provider_name'] ?? 'Provider',
        'status': _booking['status'] as String? ?? '',
      }
    ];

    final reassignedFrom = _booking['reassigned_from'] as String?;
    if (reassignedFrom != null) {
      try {
        final prev = await ApiService.get('booking/$reassignedFrom') as Map<String, dynamic>?;
        if (prev != null) {
          chain.insert(0, {
            'booking_id': prev['booking_id'],
            'provider_name': prev['provider_name'] ?? 'Provider',
            'status': prev['status'] as String? ?? '',
          });
        }
      } catch (_) {}
    }

    if (!mounted) return;

    String providerStatusLabel(String s) {
      switch (s) {
        case 'CANCELLED_PROVIDER': return 'Cancelled after accepting';
        case 'CANCELLED_TIMEOUT':  return 'No-show (auto cancelled)';
        case 'COMPLETED':          return 'Completed job';
        case 'IN_PROGRESS':        return 'In progress';
        case 'ARRIVED':            return 'Arrived on site';
        case 'ARRIVING':           return 'En route';
        default: return s.replaceAll('_', ' ').toLowerCase();
      }
    }

    var selectedIdx = chain.length - 1;
    String? selectedType;
    final commentCtrl = TextEditingController();
    bool submitting = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) {
          final selStatus = chain[selectedIdx]['status'] as String;
          final isCompleted = selStatus == 'COMPLETED';

          final types = [
            ('overcharge',    'Overcharge',   Icons.money_off_outlined,   isCompleted),
            ('no_show',       'No-Show',      Icons.person_off_outlined,  true),
            ('late_arrival',  'Late Arrival', Icons.timer_off_outlined,   true),
            ('poor_quality',  'Poor Quality', Icons.thumb_down_outlined,  isCompleted),
          ];

          return Padding(
            padding: EdgeInsets.fromLTRB(
                20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 28),
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Center(
                  child: Container(
                    width: 36, height: 4,
                    decoration: BoxDecoration(
                        color: const Color(0xFFCDD5DF),
                        borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Raise a Dispute',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold,
                        color: Color(0xFF21231D))),
                const SizedBox(height: 4),
                const Text('Select the provider and issue — AI will investigate.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF697586))),

                // Provider selector (only when chain has multiple)
                if (chain.length > 1) ...[
                  const SizedBox(height: 20),
                  const Text('Which provider?',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                          color: Color(0xFF3E3F3B))),
                  const SizedBox(height: 8),
                  ...List.generate(chain.length, (i) {
                    final c = chain[i];
                    final isSel = i == selectedIdx;
                    return GestureDetector(
                      onTap: () => setModal(() { selectedIdx = i; selectedType = null; }),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: isSel
                              ? const Color(0xFF6938ef).withValues(alpha: 0.07)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSel ? const Color(0xFF6938ef) : const Color(0xFFCDD5DF),
                            width: isSel ? 1.5 : 1,
                          ),
                        ),
                        child: Row(children: [
                          Icon(Icons.person_rounded, size: 16,
                              color: isSel ? const Color(0xFF6938ef) : const Color(0xFF697586)),
                          const SizedBox(width: 10),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(c['provider_name'] as String,
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                                    color: isSel ? const Color(0xFF6938ef) : const Color(0xFF21231D))),
                            Text(providerStatusLabel(c['status'] as String),
                                style: const TextStyle(fontSize: 11, color: Color(0xFF697586))),
                          ])),
                          if (isSel)
                            const Icon(Icons.check_circle_rounded, size: 18,
                                color: Color(0xFF6938ef)),
                        ]),
                      ),
                    );
                  }),
                ],

                // Dispute type grid
                const SizedBox(height: 20),
                const Text('What happened?',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                        color: Color(0xFF3E3F3B))),
                const SizedBox(height: 8),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 2.6,
                  children: types.map((t) {
                    final (typeKey, typeLabel, icon, enabled) = t;
                    final isSel = selectedType == typeKey;
                    return GestureDetector(
                      onTap: enabled ? () => setModal(() => selectedType = typeKey) : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: !enabled
                              ? const Color(0xFFF8FAFC)
                              : isSel
                                  ? Colors.redAccent.withValues(alpha: 0.1)
                                  : Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: !enabled
                                ? const Color(0xFFE8EDE6)
                                : isSel
                                    ? Colors.redAccent
                                    : const Color(0xFFCDD5DF),
                          ),
                        ),
                        child: Row(children: [
                          Icon(icon, size: 14,
                              color: !enabled
                                  ? const Color(0xFFB0B5AE)
                                  : isSel ? Colors.redAccent : const Color(0xFF565955)),
                          const SizedBox(width: 6),
                          Expanded(child: Text(typeLabel,
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                                  color: !enabled
                                      ? const Color(0xFFB0B5AE)
                                      : isSel ? Colors.redAccent : const Color(0xFF21231D)))),
                        ]),
                      ),
                    );
                  }).toList(),
                ),

                // Comment field
                const SizedBox(height: 20),
                const Text('Additional details (optional)',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                        color: Color(0xFF3E3F3B))),
                const SizedBox(height: 8),
                TextField(
                  controller: commentCtrl,
                  maxLines: 3,
                  style: const TextStyle(fontSize: 13, color: Color(0xFF21231D)),
                  decoration: InputDecoration(
                    hintText: 'Describe what went wrong...',
                    hintStyle: const TextStyle(fontSize: 12, color: Color(0xFFB0B5AE)),
                    contentPadding: const EdgeInsets.all(12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFCDD5DF))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFCDD5DF))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFF6938ef))),
                  ),
                ),

                // Submit
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: (selectedType == null || submitting)
                        ? null
                        : () async {
                            setModal(() => submitting = true);
                            final bId = chain[selectedIdx]['booking_id'] as String;
                            final id = await _doRaiseDispute(bId, selectedType!, commentCtrl.text.trim());
                            if (!ctx.mounted) return;
                            if (id != null) {
                              Navigator.pop(ctx);
                            } else {
                              setModal(() => submitting = false);
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(
                                  content: Text('Dispute submission failed. Please try again.'),
                                  backgroundColor: Colors.redAccent,
                                ),
                              );
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      disabledBackgroundColor: const Color(0xFFE8EDE6),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: submitting
                        ? const SizedBox(width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Submit Dispute',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                ),
              ]),
            ),
          );
        },
      ),
    );
    commentCtrl.dispose();
  }

  Widget _buildSummaryCard(Map<String, dynamic> summary) {
    final svc = summary['service_summary'] as Map<String, dynamic>? ?? {};
    final cost = summary['cost_breakdown'] as Map<String, dynamic>? ?? {};
    final done = (svc['checklist_completed'] as List?)?.cast<String>() ?? [];
    final durationMin = svc['duration_minutes'] as int? ?? 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF3A9010).withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF3A9010).withValues(alpha: 0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.receipt_long_rounded, color: Color(0xFF3A9010), size: 15),
          const SizedBox(width: 6),
          const Text("Service Summary",
              style: TextStyle(
                  color: Color(0xFF163300),
                  fontSize: 13,
                  fontWeight: FontWeight.bold)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
                color: const Color(0xFF3A9010).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8)),
            child: Text("Auto-Generated",
                style: const TextStyle(
                    color: Color(0xFF3A9010),
                    fontSize: 9,
                    fontWeight: FontWeight.bold)),
          ),
        ]),
        const SizedBox(height: 10),
        _summaryRow("Provider", svc['provider'] as String? ?? ''),
        _summaryRow("Duration", "$durationMin min"),
        _summaryRow("Total", "Rs. ${cost['total'] ?? 0}"),
        _summaryRow("Payment", cost['payment_method'] as String? ?? 'Cash'),
        if (done.isNotEmpty) ...[
          const SizedBox(height: 8),
          const Text("Completed",
              style: TextStyle(
                  color: Color(0xFF565955),
                  fontSize: 10,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          ...done.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(children: [
                  const Icon(Icons.check_circle_rounded,
                      color: Color(0xFF3A9010), size: 11),
                  const SizedBox(width: 5),
                  Expanded(
                      child: Text(item,
                          style: const TextStyle(
                              color: Color(0xFF565955), fontSize: 11))),
                ]),
              )),
        ],
        const SizedBox(height: 8),
        Text(summary['agent_note'] as String? ?? '',
            style: const TextStyle(
                color: Color(0xFFB0B5AE),
                fontSize: 9,
                fontStyle: FontStyle.italic)),
      ]),
    );
  }

  Widget _summaryRow(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(children: [
          Text(label,
              style: const TextStyle(color: Color(0xFF767773), fontSize: 11)),
          const Spacer(),
          Text(value,
              style: const TextStyle(
                  color: Color(0xFF21231D),
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    super.build(context); // required by AutomaticKeepAliveClientMixin
    final status = _booking['status'] as String? ?? 'PENDING_PROVIDER';
    final dist = _booking['distance_meters'] as num? ?? 2000;
    final checklist = _booking['checklist'] as List? ?? [];

    final scheduledStr = _booking['scheduled_time'] as String?;
    final isFutureScheduled = status == 'SCHEDULED' &&
        scheduledStr != null &&
        (DateTime.tryParse(scheduledStr)?.isAfter(DateTime.now()) ?? false);

    final displayStatus = _noProviderFound
        ? 'NO PROVIDER'
        : _autoRetrying
            ? 'SEARCHING...'
            : status;

    Color statusColor = const Color(0xFF3A9010);
    if (status == 'ARRIVED' || status == 'IN_PROGRESS')
      statusColor = Colors.blueAccent;
    if (status == 'COMPLETED') statusColor = const Color(0xFF3A9010);
    if (_autoRetrying) statusColor = Colors.orange;
    if (_noProviderFound || status.startsWith('CANCELLED'))
      statusColor = Colors.redAccent;

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
                style: TextStyle(
                    color: const Color(0xFF21231D),
                    fontSize: 13,
                    fontWeight: FontWeight.bold),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  displayStatus,
                  style: TextStyle(
                      color: statusColor,
                      fontSize: 9,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_noProviderFound) ...[
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
                  Icon(Icons.search_off_rounded, color: Colors.redAccent, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Koi provider available nahi hai. Baad mein dobara koshish karein.",
                      style: TextStyle(color: Colors.redAccent, fontSize: 12),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: _cancelAndEnd,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
                    ),
                    child: const Center(
                      child: Text("Close",
                          style: TextStyle(
                              color: Colors.redAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 13)),
                    ),
                  ),
                ),
              ]),
            ),
          ] else if (_autoRetrying) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.25)),
              ),
              child: Row(children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "Agle best provider ko dhundha ja raha hai...${ _retryAttempt > 0 ? ' (attempt $_retryAttempt)' : ''}",
                    style: const TextStyle(color: Colors.orange, fontSize: 12),
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
                border:
                    Border.all(color: Colors.redAccent.withValues(alpha: 0.25)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.cancel_outlined,
                      color: Colors.redAccent, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                      child: Text(
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
                border: Border.all(
                    color: const Color(0xFF3A9010).withValues(alpha: 0.25)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Color(0xFF3A9010))),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      "Awaiting provider confirmation...",
                      style: TextStyle(color: Color(0xFF3A9010), fontSize: 12),
                    ),
                  ),
                  GestureDetector(
                    onTap: _refreshStatus,
                    child: const Icon(Icons.refresh_rounded,
                        color: Color(0xFF3A9010), size: 18),
                  ),
                ],
              ),
            ),
          ] else if (status == 'SCHEDULED') ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF1565C0).withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF1565C0).withValues(alpha: 0.22)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.calendar_today_rounded, color: Color(0xFF1565C0), size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Booking Scheduled',
                          style: TextStyle(
                              color: Color(0xFF1565C0),
                              fontSize: 13,
                              fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _formatScheduledTime(_booking['scheduled_time'] as String?),
                          style: const TextStyle(color: Color(0xFF3E3F3B), fontSize: 12),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${_booking['provider_name'] ?? 'Provider'} will arrive at the scheduled time.',
                          style: const TextStyle(color: Color(0xFF767773), fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ] else if (status == 'ACCEPTED' || status == 'ARRIVING') ...[
            Row(children: [
              const Icon(Icons.directions_bike_rounded,
                  size: 14, color: const Color(0xFF3A9010)),
              const SizedBox(width: 6),
              Text(
                "Provider is on the way — ${dist.toInt()} m away",
                style: const TextStyle(
                    color: const Color(0xFF3E3F3B), fontSize: 12),
              ),
              const Spacer(),
              const SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Color(0xFF3A9010))),
            ]),
            const SizedBox(height: 10),
            _ProviderMapView(
              customerLocation: _booking['location'] as String? ?? '',
              distanceMeters: dist.toDouble(),
            ),
          ],
          if (status == 'ARRIVED' ||
              status == 'IN_PROGRESS' ||
              status == 'COMPLETED') ...[
            const Text(
              "Service Checklist",
              style: TextStyle(
                  color: const Color(0xFF3E3F3B),
                  fontSize: 12,
                  fontWeight: FontWeight.bold),
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
                      done
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      size: 15,
                      color: done
                          ? const Color(0xFF3A9010)
                          : const Color(0xFF767773),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      item['item'] ?? '',
                      style: TextStyle(
                        color: done
                            ? const Color(0xFF565955)
                            : const Color(0xFF21231D),
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
            const Divider(color: Color(0xFFE8EDE6)),
            const SizedBox(height: 10),
            if (_summaryLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Color(0xFF3A9010)),
                ),
              )
            else if (_summary != null) ...[
              _buildSummaryCard(_summary!),
              const SizedBox(height: 14),
              const Divider(color: Color(0xFFE8EDE6)),
              const SizedBox(height: 10),
            ],
            AgentMessagesWidget(bookingId: _booking['booking_id'] as String? ?? ''),
            const SizedBox(height: 10),
            if (_starsSubmitted == 0) ...[
              const Text(
                "How was your experience?",
                style: TextStyle(
                    color: const Color(0xFF21231D),
                    fontSize: 12,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                    5,
                    (i) => GestureDetector(
                          onTap: () => _submitRating(i + 1),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 4),
                            child: Icon(Icons.star_outline_rounded,
                                color: Colors.amber, size: 28),
                          ),
                        )),
              ),
            ] else ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.stars_rounded,
                      color: Color(0xFF3A9010), size: 16),
                  const SizedBox(width: 6),
                  Text(
                    "You gave $_starsSubmitted / 5 stars. Thank you!",
                    style: const TextStyle(
                        color: Color(0xFF163300),
                        fontSize: 12,
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],
          ],

          // ── Dispute section — available from ACCEPTED onwards ────────────
          if (!_autoRetrying && !_noProviderFound &&
              status != 'PENDING_PROVIDER' && !status.startsWith('CANCELLED') &&
              !isFutureScheduled) ...[
            const SizedBox(height: 10),
            const Divider(color: Color(0xFFE8EDE6)),
            const SizedBox(height: 4),
            if (_activeDisputeId == null)
              GestureDetector(
                onTap: _showDisputeModal,
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.balance_outlined, size: 13,
                      color: Colors.redAccent.withValues(alpha: 0.75)),
                  const SizedBox(width: 6),
                  Text('Raise a Dispute',
                      style: TextStyle(
                          color: Colors.redAccent.withValues(alpha: 0.85),
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ]),
              )
            else
              GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => DisputeDetailScreen(disputeId: _activeDisputeId!))),
                child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.balance_outlined, size: 13, color: Color(0xFF6938ef)),
                  SizedBox(width: 6),
                  Text('View My Dispute →',
                      style: TextStyle(
                          color: Color(0xFF6938ef),
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ]),
              ),
          ],
        ],
      ),
    );
  }
}

// ── Live Updates Widget (customer-facing) ────────────────────────────────────
// Polls every 5 s. Renders provider messages as chat bubbles, payment as receipt.
class AgentMessagesWidget extends StatefulWidget {
  final String bookingId;
  const AgentMessagesWidget({super.key, required this.bookingId});
  @override
  State<AgentMessagesWidget> createState() => _AgentMessagesWidgetState();
}

class _AgentMessagesWidgetState extends State<AgentMessagesWidget> {
  List<dynamic> _messages = [];
  String _providerName = 'Provider';
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _fetch();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _fetch());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fetch() async {
    try {
      final res = await ApiService.get('booking/${widget.bookingId}');
      if (!mounted) return;
      final booking = res as Map<String, dynamic>?;
      final msgs = booking?['agent_messages'] as List<dynamic>?;
      final name = booking?['provider_name'] as String? ?? 'Provider';
      if (msgs != null && (msgs.length != _messages.length || name != _providerName)) {
        setState(() { _messages = msgs; _providerName = name; });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    const disputeStatuses = {'DISPUTE_RESOLVED', 'DISPUTE_ESCALATED'};
    final updates = _messages.where((m) {
      final s = (m as Map)['status'] as String? ?? '';
      return s != 'PAYMENT_CONFIRMED' && !disputeStatuses.contains(s);
    }).toList();
    final payment = _messages.cast<Map<String, dynamic>>()
        .where((m) => m['status'] == 'PAYMENT_CONFIRMED').lastOrNull;
    final disputeMsg = _messages.cast<Map<String, dynamic>>()
        .where((m) => disputeStatuses.contains(m['status'])).lastOrNull;
    if (_messages.isEmpty) return const SizedBox.shrink();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Section header
      Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Row(children: [
          Container(
            width: 7, height: 7,
            decoration: const BoxDecoration(
              color: Color(0xFF3A9010), shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text('Updates from $_providerName',
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF565955),
                  letterSpacing: 0.2)),
        ]),
      ),

      // Provider chat bubbles
      ...updates.map((m) {
        final msg = m as Map<String, dynamic>;
        final ts = msg['timestamp'] as String? ?? '';
        final time = ts.length >= 16 ? ts.substring(11, 16) : '';
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            // Avatar
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFF3A9010).withValues(alpha: 0.12),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF3A9010).withValues(alpha: 0.25)),
              ),
              child: const Icon(Icons.handyman_rounded, size: 15, color: Color(0xFF3A9010)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_providerName,
                    style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF767773))),
                const SizedBox(height: 3),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(4),
                      topRight: Radius.circular(16),
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                    ),
                    border: Border.all(color: const Color(0xFFE8EDE6)),
                    boxShadow: [BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 4, offset: const Offset(0, 1))],
                  ),
                  child: Text(msg['message'] as String? ?? '',
                      style: const TextStyle(
                          fontSize: 13, color: Color(0xFF21231D), height: 1.45)),
                ),
              ]),
            ),
            const SizedBox(width: 6),
            Text(time, style: const TextStyle(fontSize: 10, color: Color(0xFFB0B5AE))),
          ]),
        );
      }),

      // Payment receipt card
      if (payment != null)
        Container(
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF3A9010).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF3A9010).withValues(alpha: 0.3)),
          ),
          child: Row(children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                  color: const Color(0xFF3A9010),
                  borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.check_rounded, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Payment Confirmed',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF163300))),
              const SizedBox(height: 2),
              Text('${payment['message']} released to $_providerName',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF565955))),
            ])),
          ]),
        ),

      // Dispute resolution card
      if (disputeMsg != null) ...[
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF6938ef).withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF6938ef).withValues(alpha: 0.25)),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: disputeMsg['status'] == 'DISPUTE_RESOLVED'
                    ? const Color(0xFF6938ef)
                    : const Color(0xFFf59e0b),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                disputeMsg['status'] == 'DISPUTE_RESOLVED'
                    ? Icons.balance_rounded
                    : Icons.escalator_warning_rounded,
                color: Colors.white, size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                disputeMsg['status'] == 'DISPUTE_RESOLVED'
                    ? 'Dispute Resolved'
                    : 'Dispute Escalated',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: disputeMsg['status'] == 'DISPUTE_RESOLVED'
                        ? const Color(0xFF3b1fa8)
                        : const Color(0xFF92400e)),
              ),
              const SizedBox(height: 4),
              Text(
                disputeMsg['message'] as String? ?? '',
                style: const TextStyle(fontSize: 12, color: Color(0xFF565955), height: 1.4),
              ),
            ])),
          ]),
        ),
      ],
    ]);
  }
}

