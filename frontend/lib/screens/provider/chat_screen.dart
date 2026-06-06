import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../customer/widgets/negotiation_widget.dart';

class ProviderChatScreen extends StatefulWidget {
  final String? bookingId;
  const ProviderChatScreen({super.key, this.bookingId});
  @override
  State<ProviderChatScreen> createState() => _ProviderChatScreenState();
}

class _ProviderChatScreenState extends State<ProviderChatScreen> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();

  // Profile setup state
  int _setupStep = 0;
  final _profile = <String, dynamic>{};

  // Job state
  bool _jobOffered = false;
  bool _jobAccepted = false;

  final _setupQuestions = [
    {'q': "Aap ka naam kya hai?", 'key': 'name', 'chips': null},
    {
      'q': "Kaunsi services dete hain aap?",
      'key': 'services',
      'chips': [
        "Plumber",
        "Electrician",
        "AC Technician",
        "Cleaner",
        "Carpenter",
        "Multiple"
      ]
    },
    {'q': "Aap kis area mein kaam karte hain?", 'key': 'areas', 'chips': null},
    {
      'q': "Aap ka normal rate kya hai per hour? (PKR mein)",
      'key': 'rate',
      'chips': null
    },
    {
      'q': "Minimum rate? (Isse kam aap kaam nahi karenge)",
      'key': 'min_rate',
      'chips': null
    },
    {
      'q': "Aap ki skill level?",
      'key': 'skill',
      'chips': ["Basic", "Intermediate", "Expert/Complex"]
    },
  ];

  final List<Map<String, dynamic>> _messages = [];
  bool _loading = false;
  Map<String, dynamic>? _bookingData;
  String? _jobTitle;
  Timer? _statusPollTimer;

  String _formatTitle(String? raw) {
    if (raw == null || raw.isEmpty) return 'New Job';
    return raw
        .split('_')
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  @override
  void initState() {
    super.initState();
    if (widget.bookingId != null) {
      _fetchBooking();
    } else {
      _messages.add({
        'text':
            "Assalam o Alaikum! Haazir mein khush aamdeed.\nShuru karne se pehle aap ka profile set karte hain. Pehle batayein — aap ka naam kya hai?",
        'isUser': false,
        'chips': null
      });
    }
  }

  Future<void> _fetchBooking() async {
    setState(() => _loading = true);
    try {
      final res = await ApiService.get('bookings');
      if (res is List) {
        final b = res.firstWhere((x) => x['booking_id'] == widget.bookingId,
            orElse: () => null);
        if (b != null) {
          setState(() {
            _bookingData = b;
            _jobTitle = _formatTitle(b['service_type'] as String?);
            // Show A2A negotiation trace at the top if present
            final negTrace = b['negotiation_trace'] as Map<String, dynamic>?;
            if (negTrace != null) {
              _messages.add({
                'text': null,
                'isUser': false,
                'type': 'negotiation_trace',
                'trace': negTrace,
                'contract_id': b['contract_id'] as String?,
              });
            }
            // Inject A2A agent messages thread if present
            final agentMsgs = b['agent_messages'] as List<dynamic>?;
            if (agentMsgs != null && agentMsgs.isNotEmpty) {
              _messages.removeWhere((m) => m['type'] == 'agent_messages');
              _messages.add({
                'text': null,
                'isUser': false,
                'type': 'agent_messages',
                'messages': agentMsgs,
              });
            }

            final status = b['status'];
            if (status == 'PENDING_PROVIDER') {
              _jobOffered = true;
              _messages.add({
                'text': null,
                'isUser': false,
                'type': 'job_offer',
                'job': {
                  'service': b['service_type'],
                  'problem': b['location'],
                  'location': b['location'],
                  'distance': b['distance_meters']?.toString() ?? '1.2',
                  'time': b['scheduled_time'],
                  'urgency': 'Medium',
                  'min': b['final_price'], 'max': b['final_price'],
                }
              });
              // Poll while pending so we detect if customer cancels the search
              Future.microtask(_startStatusPolling);
            } else if (status == 'ACCEPTED' || status == 'ARRIVING') {
              _jobAccepted = true;
              _messages.add({
                'text':
                    "Yeh job ${_statusLabel(status)} hai. Customer ke location ki taraf jayein — checklist wahan pahunchne ke baad milay gi.",
                'isUser': false
              });
              Future.microtask(_startStatusPolling);
            } else if (status == 'ARRIVED' || status == 'IN_PROGRESS') {
              _jobAccepted = true;
              _messages.add({
                'text': "Aap customer ke location par pahunch gaye hain! Kaam shuru karein.",
                'isUser': false
              });
              _messages
                  .add({'text': null, 'isUser': false, 'type': 'checklist'});
            } else if (status == 'COMPLETED') {
              _jobAccepted = true;
              _messages
                  .add({'text': null, 'isUser': false, 'type': 'job_history'});
            } else if (status == 'CANCELLED_PROVIDER') {
              _messages.add({
                'text': 'Aapne yeh job decline/cancel kar diya tha.\n\nService: ${b['service_type'] ?? ''}\nLocation: ${b['location'] ?? ''}\nPrice: Rs. ${b['final_price'] ?? ''}',
                'isUser': false,
              });
            } else if (status == 'CANCELLED_CUSTOMER') {
              _messages.add({
                'text': 'Customer ne yeh booking cancel kar di thi.\n\nService: ${b['service_type'] ?? ''}\nLocation: ${b['location'] ?? ''}\nPrice: Rs. ${b['final_price'] ?? ''}',
                'isUser': false,
              });
            } else if (status == 'CANCELLED_TIMEOUT') {
              _messages.add({
                'text': 'Yeh job timeout ho gayi thi — aapne waqt par jawab nahi diya.\n\nService: ${b['service_type'] ?? ''}\nLocation: ${b['location'] ?? ''}',
                'isUser': false,
              });
            }
          });
        }
      }
    } catch (e) {
      debugPrint(e.toString());
    }
    setState(() => _loading = false);
  }

  @override
  void dispose() {
    _statusPollTimer?.cancel();
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients)
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    });
  }

  void _startStatusPolling() {
    _statusPollTimer?.cancel();
    _statusPollTimer =
        Timer.periodic(const Duration(seconds: 2), (_) async {
      if (widget.bookingId == null || !mounted) return;
      final alreadyShown = _messages.any((m) => m['type'] == 'checklist');
      if (alreadyShown) {
        _statusPollTimer?.cancel();
        _statusPollTimer = null;
        return;
      }
      try {
        final res = await ApiService.get('bookings');
        if (!mounted) return;
        if (res is List) {
          final b = res.firstWhere(
              (x) => x['booking_id'] == widget.bookingId,
              orElse: () => null);
          if (b != null) {
            final status = b['status'] as String? ?? '';
            setState(() {
              _bookingData = b;
              // Keep agent_messages card up-to-date during polling
              final agentMsgs = b['agent_messages'] as List<dynamic>?;
              if (agentMsgs != null && agentMsgs.isNotEmpty) {
                final idx = _messages.indexWhere((m) => m['type'] == 'agent_messages');
                final card = {'text': null, 'isUser': false, 'type': 'agent_messages', 'messages': agentMsgs};
                if (idx != -1) {
                  _messages[idx] = card;
                } else {
                  _messages.add(card);
                }
              }
            });
            if (status == 'CANCELLED_CUSTOMER') {
              _statusPollTimer?.cancel();
              _statusPollTimer = null;
              setState(() {
                _jobOffered = false;
                _messages.add({
                  'text': 'Customer ne search cancel kar diya. Yeh job ab available nahi hai.',
                  'isUser': false,
                });
              });
              _scrollBottom();
            } else if (status == 'ARRIVED' || status == 'IN_PROGRESS') {
              _statusPollTimer?.cancel();
              _statusPollTimer = null;
              setState(() {
                _messages.add({
                  'text':
                      "Aap customer ke location par pahunch gaye hain! Kaam shuru karein aur checklist complete karein.",
                  'isUser': false,
                });
                _messages
                    .add({'text': null, 'isUser': false, 'type': 'checklist'});
              });
              _scrollBottom();
            }
          }
        }
      } catch (e) {
        debugPrint('Status poll error: $e');
      }
    });
  }

  Future<void> _send([String? override]) async {
    final input = override ?? _ctrl.text.trim();
    if (input.isEmpty) return;
    _ctrl.clear();
    setState(() => _messages.add({'text': input, 'isUser': true}));
    _scrollBottom();

    // Profile setup flow
    if (_setupStep < _setupQuestions.length) {
      final key = _setupQuestions[_setupStep]['key'] as String;
      _profile[key] = input;
      _setupStep++;

      await Future.delayed(const Duration(milliseconds: 800));

      if (_setupStep < _setupQuestions.length) {
        final next = _setupQuestions[_setupStep];
        setState(() => _messages
            .add({'text': next['q'], 'isUser': false, 'chips': next['chips']}));
      } else {
        // Profile complete
        setState(() => _messages.add({
              'text':
                  "Profile complete! Shukriya, ${_profile['name']}.\n\nAb aap online hain — jab bhi koi nayi job aaye gi, main aap ko yahan notify karunga. Taiyaar rahein! 💪",
              'isUser': false,
              'chips': null,
            }));
        await Future.delayed(const Duration(seconds: 2));
        _offerJob();
      }
      _scrollBottom();
    } else if (_jobOffered && !_jobAccepted) {
      final lower = input.toLowerCase();
      if (lower.contains('accept') ||
          lower.contains('haan') ||
          lower.contains('ok') ||
          lower.contains('✓')) {
        _acceptJob();
      } else {
        _declineJob();
      }
    }
  }

  void _offerJob() {
    setState(() {
      _jobOffered = true;
      _messages.add({
        'text': null,
        'isUser': false,
        'type': 'job_offer',
        'job': {
          'service': 'Plumber',
          'problem': 'Kitchen mein pipe se pani aa raha hai',
          'location': 'G-11, Islamabad',
          'distance': '2.1',
          'time': 'Aaj, 4:00 PM',
          'urgency': 'Medium',
          'min': 1200,
          'max': 1800,
          'countdown': 420,
        }
      });
    });
    _scrollBottom();
  }

  void _acceptJob() async {
    if (widget.bookingId == null) return;
    try {
      await ApiService.post('/booking/status',
          {'booking_id': widget.bookingId, 'status': 'ACCEPTED'});
      final location = _bookingData?['location'] ?? 'customer location';
      final price = _bookingData?['final_price']?.toString() ?? '';
      setState(() {
        _jobOffered = false;
        _jobAccepted = true;
        _messages.add({
          'text':
              "Job accept ho gayi!\n\n📍 Location: $location\n💰 Amount: Rs. $price\n\nCustomer ke ghar ki taraf jayen. Jab aap pahunch jayein toh checklist appear ho gi.",
          'isUser': false,
          'type': 'accepted',
        });
      });
      _scrollBottom();
      _startStatusPolling();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error accepting job: $e'),
              backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  void _declineJob() async {
    if (widget.bookingId == null) return;
    try {
      await ApiService.post('/booking/status',
          {'booking_id': widget.bookingId, 'status': 'CANCELLED_PROVIDER'});
      if (!mounted) return;
      setState(() {
        _jobOffered = false;
        _messages.add({
          'text':
              "Job decline kar di gayi. Customer ko notify kar diya gaya hai.\n\nAgle job ka intezaar karein.",
          'isUser': false
        });
      });
      _scrollBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error declining job: $e'),
              backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _tapChecklistItem(int idx) async {
    if (widget.bookingId == null) return;
    final checklist = _bookingData?['checklist'] as List? ?? [];
    if (idx >= checklist.length) return;
    if (checklist[idx]['completed'] == true) return; // already done
    try {
      final res = await ApiService.post('/booking/checklist', {
        'booking_id': widget.bookingId,
        'item_index': idx,
      });
      if (!mounted) return;
      if (res['booking'] != null) {
        setState(() {
          _bookingData = Map<String, dynamic>.from(res['booking'] as Map);
          final idx2 = _messages.indexWhere((m) => m['type'] == 'checklist');
          if (idx2 != -1) _messages[idx2] = {..._messages[idx2]};
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _cancelJob() async {
    if (widget.bookingId == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Cancel This Job?",
            style: TextStyle(color: const Color(0xFF21231D), fontSize: 16)),
        content: const Text(
          "Are you sure? The customer will be notified and matched with another provider. This will be recorded against your profile.",
          style: TextStyle(
              color: const Color(0xFF565955), fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Keep Job",
                style: TextStyle(
                    color: const Color(0xFF3A9010),
                    fontWeight: FontWeight.bold)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Yes, Cancel",
                style: TextStyle(
                    color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;
    try {
      await ApiService.post(
          '/booking/cancel-provider', {'booking_id': widget.bookingId});
      if (!mounted) return;
      setState(() {
        if (_bookingData != null) {
          _bookingData = {..._bookingData!, 'status': 'CANCELLED_PROVIDER'};
        }
        final idx = _messages.indexWhere((m) => m['type'] == 'checklist');
        if (idx != -1) _messages[idx] = {..._messages[idx]};
        _messages.add({
          'text':
              "Job cancelled. Customer has been notified and will be rematched.\n\n⚠️ This cancellation has been recorded on your profile.",
          'isUser': false,
        });
      });
      _scrollBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error cancelling job: $e'),
              backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  void _markComplete() async {
    if (widget.bookingId == null) return;
    final checklist = _bookingData?['checklist'] as List? ?? [];
    final allDone = checklist.every((item) => item['completed'] == true);
    if (!allDone) return;
    try {
      final res = await ApiService.post('/booking/status',
          {'booking_id': widget.bookingId, 'status': 'COMPLETED'});
      if (!mounted) return;
      setState(() {
        if (res['booking'] != null) {
          _bookingData = Map<String, dynamic>.from(res['booking'] as Map);
          final idx2 = _messages.indexWhere((m) => m['type'] == 'checklist');
          if (idx2 != -1) _messages[idx2] = {..._messages[idx2]};
        }
        _messages.add({
          'text':
              "Job marked complete. Customer has been sent a rating request.",
          'isUser': false,
        });
      });
      _scrollBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error completing job: $e'),
              backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAF5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF163300),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded,
              color: Colors.white, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(_jobTitle ?? 'New Job',
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.white)),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
            ),
            child: const Row(children: [
              Icon(Icons.handyman_rounded, size: 16, color: Colors.white),
              SizedBox(width: 4),
              Text('Provider',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white)),
            ]),
          ),
        ],
      ),
      body: SafeArea(
          child: Column(children: [
        Expanded(
            child: ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          itemCount: _messages.length,
          itemBuilder: (_, i) => KeyedSubtree(
            key: ObjectKey(_messages[i]),
            child: _buildItem(_messages[i]),
          ),
        )),
        if (_loading)
          const Padding(
              padding: EdgeInsets.all(8),
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: const Color(0xFF3A9010))),
      ])),
    );
  }

  Widget _buildItem(Map<String, dynamic> msg) {
    if (msg['type'] == 'negotiation_trace') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: NegotiationWidget(
          negotiationTrace: msg['trace'] as Map<String, dynamic>,
          contractId: msg['contract_id'] as String?,
        ),
      );
    }
    if (msg['type'] == 'job_offer')
      return _jobOfferCard(msg['job'] as Map<String, dynamic>);
    if (msg['type'] == 'agent_messages')
      return _agentMessagesCard(msg['messages'] as List<dynamic>);
    if (msg['type'] == 'checklist') return _checklistCard();
    if (msg['type'] == 'job_history') return _jobHistoryCard();

    final isUser = msg['isUser'] as bool;
    final text = msg['text'] as String? ?? '';
    final chips = msg['chips'] as List?;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 5),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78),
          decoration: BoxDecoration(
            color: isUser
                ? const Color(0xFF3A9010).withValues(alpha: 0.15)
                : Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(isUser ? 18 : 4),
              bottomRight: Radius.circular(isUser ? 4 : 18),
            ),
            border: Border.all(
                color: isUser
                    ? const Color(0xFF3A9010).withValues(alpha: 0.3)
                    : const Color(0xFFE8EDE6)),
          ),
          child: Text(text,
              style: TextStyle(
                  color: isUser
                      ? const Color(0xFF3A9010)
                      : const Color(0xFF21231D),
                  fontSize: 13,
                  height: 1.5)),
        ),
      ),
      if (chips != null && !isUser)
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 4),
          child: Wrap(
              spacing: 8,
              children: chips
                  .map((c) => GestureDetector(
                        onTap: () => _send(c),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: const Color(0xFF3A9010)
                                      .withValues(alpha: 0.4))),
                          child: Text(c,
                              style: const TextStyle(
                                  color: const Color(0xFF3A9010),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ))
                  .toList()),
        ),
    ]);
  }

  Widget _agentMessagesCard(List<dynamic> messages) {
    if (messages.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF163300).withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF163300).withValues(alpha: 0.15)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.receipt_long_rounded, size: 15, color: Color(0xFF3A9010)),
          const SizedBox(width: 6),
          const Text("Job Activity",
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF3A9010),
                  letterSpacing: 0.3)),
        ]),
        const SizedBox(height: 10),
        ...messages.map((m) {
          final msg = m as Map<String, dynamic>;
          final isProvider = msg['from'] == 'provider_agent';
          final label = isProvider ? 'Sent to customer' : 'Customer confirmed ✅';
          final labelColor = isProvider ? const Color(0xFF3A9010) : const Color(0xFF163300);
          final ts = msg['timestamp'] as String? ?? '';
          final time = ts.length >= 16 ? ts.substring(11, 16) : '';
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: labelColor)),
                const Spacer(),
                Text(time,
                    style: const TextStyle(
                        fontSize: 10, color: Color(0xFFB0B5AE))),
              ]),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE8EDE6)),
                ),
                child: Text(msg['message'] as String? ?? '',
                    style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF3E3F3B),
                        height: 1.5)),
              ),
            ]),
          );
        }),
      ]),
    );
  }

  Widget _jobOfferCard(Map<String, dynamic> job) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF3A9010).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border:
            Border.all(color: const Color(0xFF3A9010).withValues(alpha: 0.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.notifications_active,
              color: const Color(0xFF3A9010), size: 18),
          const SizedBox(width: 8),
          const Text("Naya Kaam Aaya!",
              style: TextStyle(
                  color: const Color(0xFF3A9010),
                  fontSize: 15,
                  fontWeight: FontWeight.bold))
        ]),
        const SizedBox(height: 14),
        _jobRow("Service:", job['service'] as String),
        _jobRow("Problem:", job['problem'] as String),
        _jobRow(
            "Location:", "${job['location']} — ${job['distance']}km aap se"),
        _jobRow("Time:", job['time'] as String),
        _jobRow("Urgency:", job['urgency'] as String),
        _jobRow("Quoted:", "Rs. ${job['min']} – Rs. ${job['max']}"),
        const Divider(color: const Color(0xFFE8EDE6), height: 20),
        const Text(
            "Parts & equipment costs are separate — discuss with the customer on-site.",
            style: TextStyle(color: const Color(0xFF767773), fontSize: 11)),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
              child: GestureDetector(
            onTap: _jobOffered ? _acceptJob : null,
            child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                    color: _jobOffered ? const Color(0xFF3A9010) : const Color(0xFFCCCCCC),
                    borderRadius: BorderRadius.circular(16)),
                alignment: Alignment.center,
                child: Text("Accept",
                    style: TextStyle(
                        color: _jobOffered ? Colors.white : const Color(0xFF888888),
                        fontWeight: FontWeight.bold,
                        fontSize: 14))),
          )),
          const SizedBox(width: 10),
          Expanded(
              child: GestureDetector(
            onTap: _jobOffered ? _declineJob : null,
            child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                    color: _jobOffered
                        ? Colors.redAccent.withValues(alpha: 0.12)
                        : const Color(0xFFF0F0F0),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: _jobOffered
                            ? Colors.redAccent.withValues(alpha: 0.5)
                            : const Color(0xFFCCCCCC))),
                alignment: Alignment.center,
                child: Text("Decline",
                    style: TextStyle(
                        color: _jobOffered ? Colors.redAccent : const Color(0xFFAAAAAA),
                        fontWeight: FontWeight.bold,
                        fontSize: 14))),
          )),
        ]),
      ]),
    );
  }

  Widget _checklistCard() {
    final checklist = _bookingData?['checklist'] as List? ?? [];
    final allDone = checklist.isNotEmpty &&
        checklist.every((item) => item['completed'] == true);
    final bookingStatus = _bookingData?['status'] as String? ?? '';
    final isCompleted = bookingStatus == 'COMPLETED';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE8EDE6)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text("📋 Job Checklist",
              style: TextStyle(
                  color: const Color(0xFF21231D),
                  fontSize: 14,
                  fontWeight: FontWeight.bold)),
          const Spacer(),
          if (isCompleted)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: const Color(0xFF3A9010).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8)),
              child: const Text("COMPLETED",
                  style: TextStyle(
                      color: const Color(0xFF3A9010),
                      fontSize: 10,
                      fontWeight: FontWeight.bold)),
            ),
        ]),
        const SizedBox(height: 12),
        if (checklist.isEmpty)
          const Text("No checklist items yet.",
              style: TextStyle(color: const Color(0xFF767773), fontSize: 13))
        else
          ...checklist.asMap().entries.map((e) {
            final idx = e.key;
            final item = e.value as Map;
            final done = item['completed'] == true;
            return GestureDetector(
              onTap:
                  (!done && !isCompleted) ? () => _tapChecklistItem(idx) : null,
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: done
                      ? const Color(0xFF3A9010).withValues(alpha: 0.10)
                      : const Color(0xFFF7FAF5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: done
                        ? const Color(0xFF3A9010).withValues(alpha: 0.35)
                        : const Color(0xFFE8EDE6),
                  ),
                ),
                child: Row(children: [
                  Icon(
                    done ? Icons.check_circle_rounded : Icons.circle_outlined,
                    size: 18,
                    color: done
                        ? const Color(0xFF3A9010)
                        : const Color(0xFF767773),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item['item'] as String? ?? '',
                      style: TextStyle(
                        color: done
                            ? const Color(0xFF565955)
                            : const Color(0xFF3E3F3B),
                        fontSize: 13,
                        decoration: done ? TextDecoration.lineThrough : null,
                        decorationColor: const Color(0xFF767773),
                      ),
                    ),
                  ),
                  if (!done && !isCompleted)
                    const Icon(Icons.touch_app_rounded,
                        size: 14, color: const Color(0xFFB0B5AE)),
                ]),
              ),
            );
          }),
        if (!isCompleted) ...[
          const SizedBox(height: 8),
          GestureDetector(
            onTap: allDone ? _markComplete : null,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color:
                    allDone ? const Color(0xFF3A9010) : const Color(0xFFE8EDE6),
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Text(
                allDone ? "Mark Job as Complete" : "Complete all items first",
                style: TextStyle(
                  color: allDone ? Colors.white : const Color(0xFF767773),
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          ),
          if (bookingStatus != 'CANCELLED_PROVIDER' &&
              bookingStatus != 'CANCELLED_CUSTOMER') ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _cancelJob,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: Colors.redAccent.withValues(alpha: 0.3)),
                ),
                alignment: Alignment.center,
                child: const Text(
                  "Cancel Job",
                  style: TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 12),
                ),
              ),
            ),
          ],
        ],
      ]),
    );
  }

  Widget _jobHistoryCard() {
    final b = _bookingData ?? {};
    final checklist = b['checklist'] as List? ?? [];
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border:
            Border.all(color: const Color(0xFF3A9010).withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.check_circle_rounded,
              color: const Color(0xFF3A9010), size: 18),
          const SizedBox(width: 8),
          const Text("Job History",
              style: TextStyle(
                  color: const Color(0xFF3A9010),
                  fontSize: 14,
                  fontWeight: FontWeight.bold)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
                color: const Color(0xFF3A9010).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8)),
            child: const Text("COMPLETED",
                style: TextStyle(
                    color: const Color(0xFF3A9010),
                    fontSize: 10,
                    fontWeight: FontWeight.bold)),
          ),
        ]),
        const Divider(color: const Color(0xFFE8EDE6), height: 20),
        _jobRow("Booking ID:", b['booking_id'] as String? ?? '—'),
        _jobRow("Service:", b['service_type'] as String? ?? '—'),
        _jobRow("Location:", b['location'] as String? ?? '—'),
        _jobRow("Amount:", "Rs. ${b['final_price'] ?? '—'}"),
        _jobRow("Customer:", b['customer_id'] as String? ?? '—'),
        if (b['scheduled_time'] != null)
          _jobRow(
              "Scheduled:", (b['scheduled_time'] as String).substring(0, 16)),
        const SizedBox(height: 12),
        const Text("Work completed:",
            style: TextStyle(
                color: const Color(0xFF565955),
                fontSize: 12,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        ...checklist.map((item) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                const Icon(Icons.check_circle_rounded,
                    size: 14, color: const Color(0xFF3A9010)),
                const SizedBox(width: 8),
                Text(item['item'] as String? ?? '',
                    style: const TextStyle(
                        color: const Color(0xFF565955),
                        fontSize: 12,
                        decoration: TextDecoration.lineThrough,
                        decorationColor: const Color(0xFFB0B5AE))),
              ]),
            )),
      ]),
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'PENDING_PROVIDER':
        return 'Pending';
      case 'ACCEPTED':
        return 'Accepted';
      case 'ARRIVING':
        return 'En Route';
      case 'ARRIVED':
        return 'On Site';
      case 'IN_PROGRESS':
        return 'In Progress';
      case 'COMPLETED':
        return 'Completed';
      default:
        return status.replaceAll('_', ' ');
    }
  }

  Widget _jobRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 80,
              child: Text(label,
                  style: const TextStyle(
                      color: const Color(0xFF767773), fontSize: 12))),
          Expanded(
              child: Text(value,
                  style: const TextStyle(
                      color: const Color(0xFF3E3F3B),
                      fontSize: 12,
                      fontWeight: FontWeight.w600))),
        ]),
      );

}
