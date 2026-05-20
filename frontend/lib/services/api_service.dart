import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ApiService {
  // Injected at build time via --dart-define=BACKEND_URL=https://...
  // Falls back to emulator/local URLs for dev builds.
  static const String _prodUrl = String.fromEnvironment('BACKEND_URL');

  static String get baseUrl {
    if (_prodUrl.isNotEmpty) return _prodUrl;
    if (kIsWeb) return 'http://127.0.0.1:3000/api';
    if (Platform.isAndroid) return 'http://10.0.2.2:3000/api';
    return 'http://127.0.0.1:3000/api';
  }

  // Create Session
  static Future<Map<String, dynamic>> createSession(String customerId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/session/create'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'customer_id': customerId}),
    );
    return jsonDecode(response.body);
  }

  // Orchestrate (Start/Continue Pipeline with History and Session ID)
  static Future<Map<String, dynamic>> orchestrate(String input, List<Map<String, String>> history, {String? sessionId}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/orchestrate'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'input': input,
        'history': history,
        if (sessionId != null) 'session_id': sessionId,
      }),
    );
    return jsonDecode(response.body);
  }

  // Negotiation Actions
  static Future<Map<String, dynamic>> respondToNegotiation(
    String threadId,
    String party,
    String action, {
    double? counterPrice,
    String? message,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/negotiate/$party'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'thread_id': threadId,
        'action': action,
        'counter_price': counterPrice,
        'message': message,
      }),
    );
    return jsonDecode(response.body);
  }

  // Confirm Booking
  static Future<Map<String, dynamic>> confirmBooking(Map<String, dynamic> data) async {
    final response = await http.post(
      Uri.parse('$baseUrl/booking/confirm'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(data),
    );
    return jsonDecode(response.body);
  }

  // Generic GET
  static Future<dynamic> get(String endpoint) async {
    final path = endpoint.startsWith('/') ? endpoint : '/$endpoint';
    final response = await http.get(Uri.parse('$baseUrl$path'));
    return jsonDecode(response.body);
  }


  // Status Updates
  static Future<Map<String, dynamic>> updateStatus(String bookingId, String status) async {
    final response = await http.post(
      Uri.parse('$baseUrl/booking/status'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'booking_id': bookingId, 'status': status}),
    );
    return jsonDecode(response.body);
  }

  // Timeout Negotiation Simulation
  static Future<Map<String, dynamic>> timeoutNegotiation(String sessionId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/negotiate/timeout'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'session_id': sessionId}),
    );
    return jsonDecode(response.body);
  }

  // Generic POST helper
  static Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) async {
    final response = await http.post(
      Uri.parse(path.startsWith('http') ? path : '$baseUrl$path'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    return jsonDecode(response.body);
  }
}
