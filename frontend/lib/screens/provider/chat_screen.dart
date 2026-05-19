import 'package:flutter/material.dart';
import '../../services/api_service.dart';

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
  final _checklistItems = ['Kaam complete kiya', 'Area saaf kiya', 'Customer ko dikhaya', 'Customer ne confirm kiya'];
  final Set<int> _checkedItems = {};

  final _setupQuestions = [
    {'q': "Aap ka naam kya hai?", 'key': 'name', 'chips': null},
    {'q': "Kaunsi services dete hain aap?", 'key': 'services', 'chips': ["Plumber", "Electrician", "AC Technician", "Cleaner", "Carpenter", "Multiple"]},
    {'q': "Aap kis area mein kaam karte hain?", 'key': 'areas', 'chips': null},
    {'q': "Aap ka normal rate kya hai per hour? (PKR mein)", 'key': 'rate', 'chips': null},
    {'q': "Minimum rate? (Isse kam aap kaam nahi karenge)", 'key': 'min_rate', 'chips': null},
    {'q': "Aap ki skill level?", 'key': 'skill', 'chips': ["Basic", "Intermediate", "Expert/Complex"]},
  ];

  final List<Map<String, dynamic>> _messages = [];
  bool _loading = false;
  Map<String, dynamic>? _bookingData;

  @override
  void initState() {
    super.initState();
    if (widget.bookingId != null) {
      _fetchBooking();
    } else {
      _messages.add({'text': "Assalam o Alaikum! Khedmatgar mein khush aamdeed.\nMain aap ka profile set karta hoon. Pehle batayein — aap ka naam kya hai?", 'isUser': false, 'chips': null});
    }
  }

  Future<void> _fetchBooking() async {
    setState(() => _loading = true);
    try {
      final res = await ApiService.get('bookings');
      if (res is List) {
        final b = res.firstWhere((x) => x['booking_id'] == widget.bookingId, orElse: () => null);
        if (b != null) {
          setState(() {
            _bookingData = b;
            final status = b['status'];
            if (status == 'PENDING_PROVIDER') {
              _jobOffered = true;
              _messages.add({
                'text': null, 'isUser': false, 'type': 'job_offer',
                'job': {
                  'service': b['service_type'],
                  'problem': b['location'], // Using location as mock problem if not available
                  'location': b['location'],
                  'distance': b['distance_meters']?.toString() ?? '1.2',
                  'time': b['scheduled_time'],
                  'urgency': 'Medium',
                  'min': b['final_price'], 'max': b['final_price'],
                }
              });
            } else if (status == 'ACCEPTED' || status == 'ARRIVING' || status == 'ARRIVED' || status == 'IN_PROGRESS') {
              _jobAccepted = true;
              _messages.add({'text': "Current Status: $status", 'isUser': false});
              _messages.add({'text': null, 'isUser': false, 'type': 'checklist'});
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
  void dispose() { _ctrl.dispose(); _scroll.dispose(); super.dispose(); }

  void _scrollBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
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
        setState(() => _messages.add({'text': next['q'], 'isUser': false, 'chips': next['chips']}));
      } else {
        // Profile complete
        setState(() => _messages.add({
          'text': "Profile set ho gayi, ${_profile['name']}! Ab aap ka availability toggle on hai.\n\nJab bhi koi job aaye, main aap ko yahan message karunga. Agle kaam ka intezaar karein! 🙏",
          'isUser': false, 'chips': null,
        }));
        await Future.delayed(const Duration(seconds: 2));
        _offerJob();
      }
      _scrollBottom();
    } else if (_jobOffered && !_jobAccepted) {
      final lower = input.toLowerCase();
      if (lower.contains('accept') || lower.contains('haan') || lower.contains('ok') || lower.contains('✓')) {
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
        'text': null, 'isUser': false, 'type': 'job_offer',
        'job': {
          'service': 'Plumber',
          'problem': 'Kitchen mein pipe se pani aa raha hai',
          'location': 'G-11, Islamabad',
          'distance': '2.1',
          'time': 'Aaj, 4:00 PM',
          'urgency': 'Medium',
          'min': 1200, 'max': 1800,
          'countdown': 420,
        }
      });
    });
    _scrollBottom();
  }

  void _acceptJob() async {
    if (widget.bookingId != null) {
      await ApiService.post('booking/status', {'booking_id': widget.bookingId, 'status': 'ACCEPTED'});
    }
    setState(() {
      _jobOffered = false;
      _jobAccepted = true;
      _messages.add({
        'text': "✅ Job accept ho gayi!\n\nCustomer ka address:\n📍 House 12, Street 4, G-11/3, Islamabad\n\nYaad rakhein:\n• Seedha customer se equipment cost discuss karein on-site\n• Kaam complete karne ke baad checklist fill karein\n\n1 ghante pehle reminder milega. 🙏",
        'isUser': false, 'type': 'accepted',
      });
      _messages.add({'text': null, 'isUser': false, 'type': 'checklist'});
    });
    _scrollBottom();
  }

  void _declineJob() {
    setState(() {
      _jobOffered = false;
      _messages.add({'text': "Theek hai. Yeh job doosre provider ko bhej di gayi. Aap ki availability unchanged hai — agla job aane par notify karunga.", 'isUser': false});
    });
    _scrollBottom();
  }

  void _markComplete() async {
    if (_checkedItems.length < _checklistItems.length) return;
    if (widget.bookingId != null) {
      await ApiService.post('booking/status', {'booking_id': widget.bookingId, 'status': 'COMPLETED'});
    }
    setState(() {
      _messages.add({
        'text': "✅ Job complete ho gayi!\nCustomer ko rate karne ka request bhej diya gaya.\n\n📊 Aaj ka summary:\nJobs complete: 1\nEarnings: Rs. 1,400\nRating: 4.5★\n\nAgle kaam ka intezaar karein! 🙏",
        'isUser': false,
      });
    });
    _scrollBottom();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B), elevation: 0,
        title: Row(children: [
          Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.amber, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          const Text("Khedmatgar — Provider", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        ]),
      ),
      body: SafeArea(child: Column(children: [
        Expanded(child: ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          itemCount: _messages.length,
          itemBuilder: (_, i) => KeyedSubtree(
            key: ObjectKey(_messages[i]),
            child: _buildItem(_messages[i]),
          ),
        )),
        if (_loading) const Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amber)),
        _buildInput(),
      ])),
    );
  }

  Widget _buildItem(Map<String, dynamic> msg) {
    if (msg['type'] == 'job_offer') return _jobOfferCard(msg['job'] as Map<String, dynamic>);
    if (msg['type'] == 'checklist') return _checklistCard();

    final isUser = msg['isUser'] as bool;
    final text = msg['text'] as String? ?? '';
    final chips = msg['chips'] as List?;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 5),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
          decoration: BoxDecoration(
            color: isUser ? Colors.amber.withOpacity(0.15) : const Color(0xFF1E293B),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18), topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(isUser ? 18 : 4), bottomRight: Radius.circular(isUser ? 4 : 18),
            ),
            border: Border.all(color: isUser ? Colors.amber.withOpacity(0.3) : Colors.white.withOpacity(0.07)),
          ),
          child: Text(text, style: TextStyle(color: isUser ? Colors.amber : const Color(0xFFE2E8F0), fontSize: 13, height: 1.5)),
        ),
      ),
      if (chips != null && !isUser) Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 4),
        child: Wrap(spacing: 8, children: (chips as List<dynamic>).map((c) => GestureDetector(
          onTap: () => _send(c as String),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.amber.withOpacity(0.4))),
            child: Text(c as String, style: const TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        )).toList()),
      ),
    ]);
  }

  Widget _jobOfferCard(Map<String, dynamic> job) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Colors.amber.withOpacity(0.1), Colors.amber.withOpacity(0.03)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.amber.withOpacity(0.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [const Icon(Icons.notifications_active, color: Colors.amber, size: 18), const SizedBox(width: 8), const Text("🔔 Naya Kaam Aaya!", style: TextStyle(color: Colors.amber, fontSize: 15, fontWeight: FontWeight.bold))]),
        const SizedBox(height: 14),
        _jobRow("Service:", job['service'] as String),
        _jobRow("Problem:", job['problem'] as String),
        _jobRow("Location:", "${job['location']} — ${job['distance']}km aap se"),
        _jobRow("Time:", job['time'] as String),
        _jobRow("Urgency:", job['urgency'] as String),
        _jobRow("Quoted:", "Rs. ${job['min']} – Rs. ${job['max']}"),
        const Divider(color: Colors.white10, height: 20),
        const Text("⚠️ Parts/equipment cost alag hoga — on-site discuss karein.", style: TextStyle(color: Colors.white38, fontSize: 11)),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: GestureDetector(
            onTap: _acceptJob,
            child: Container(padding: const EdgeInsets.symmetric(vertical: 12), decoration: BoxDecoration(color: const Color(0xFF00C853), borderRadius: BorderRadius.circular(16)), alignment: Alignment.center,
              child: const Text("✓ Accept", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 14))),
          )),
          const SizedBox(width: 10),
          Expanded(child: GestureDetector(
            onTap: _declineJob,
            child: Container(padding: const EdgeInsets.symmetric(vertical: 12), decoration: BoxDecoration(color: Colors.redAccent.withOpacity(0.12), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.redAccent.withOpacity(0.5))), alignment: Alignment.center,
              child: const Text("✗ Decline", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 14))),
          )),
        ]),
      ]),
    );
  }

  Widget _checklistCard() {
    final allDone = _checkedItems.length == _checklistItems.length;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.white10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text("Kaam complete karne se pehle confirm karein:", style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        ..._checklistItems.asMap().entries.map((e) => GestureDetector(
          onTap: () => setState(() { _checkedItems.contains(e.key) ? _checkedItems.remove(e.key) : _checkedItems.add(e.key); }),
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _checkedItems.contains(e.key) ? const Color(0xFF00C853).withOpacity(0.12) : Colors.white.withOpacity(0.04),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _checkedItems.contains(e.key) ? const Color(0xFF00C853).withOpacity(0.4) : Colors.white12),
            ),
            child: Row(children: [
              Icon(_checkedItems.contains(e.key) ? Icons.check_circle_rounded : Icons.circle_outlined, size: 18, color: _checkedItems.contains(e.key) ? const Color(0xFF00C853) : Colors.white38),
              const SizedBox(width: 10),
              Text(e.value, style: TextStyle(color: _checkedItems.contains(e.key) ? const Color(0xFF00C853) : Colors.white70, fontSize: 13)),
            ]),
          ),
        )),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: allDone ? _markComplete : null,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(color: allDone ? const Color(0xFF00C853) : Colors.white12, borderRadius: BorderRadius.circular(14)),
            alignment: Alignment.center,
            child: Text("✅ Haan, sab kuch ho gaya — Job Complete Karo", style: TextStyle(color: allDone ? Colors.black : Colors.white38, fontWeight: FontWeight.bold, fontSize: 13)),
          ),
        ),
      ]),
    );
  }

  Widget _jobRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 80, child: Text(label, style: const TextStyle(color: Colors.white38, fontSize: 12))),
      Expanded(child: Text(value, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600))),
    ]),
  );

  Widget _buildInput() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(color: Color(0xFF1E293B), border: Border(top: BorderSide(color: Colors.white10))),
      child: Row(children: [
        Expanded(child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.amber.withOpacity(0.15))),
          child: TextField(
            controller: _ctrl,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(hintText: "Type karein...", hintStyle: TextStyle(color: Colors.white30, fontSize: 13), border: InputBorder.none),
            onSubmitted: (_) => _send(),
          ),
        )),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _send,
          child: Container(padding: const EdgeInsets.all(10), decoration: const BoxDecoration(color: Colors.amber, shape: BoxShape.circle), child: const Icon(Icons.send_rounded, color: Colors.black, size: 18)),
        ),
      ]),
    );
  }
}
