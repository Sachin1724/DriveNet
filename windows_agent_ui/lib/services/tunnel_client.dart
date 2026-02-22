import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'dart:async';
import 'drive_manager.dart';

class TunnelClient {
  static IOWebSocketChannel? _channel;
  static bool _isConnected = false;
  static bool _shouldReconnect = true;
  static Timer? _reconnectTimer;

  static bool get isConnected => _isConnected;

  static Future<void> start(String token) async {
    _shouldReconnect = true;
    await _connect(token);
  }

  static Future<void> _connect(String token) async {
    if (_isConnected) return;

    final prefs = await SharedPreferences.getInstance();
    const cloudUrl = 'https://drivenet-broker.onrender.com';
    String agentId = prefs.getString('agent_id') ?? 'desktop-node-01';

    try {
      final wsUrl = Uri.parse(cloudUrl);
      final ws = await WebSocket.connect(
        wsUrl.toString(),
        headers: {
          'x-agent-id': agentId,
          'authorization': 'Bearer $token',
        },
      );
      
      _channel = IOWebSocketChannel(ws);
      _isConnected = true;
      debugPrint('[DriveNet Agent] Connected to Cloud Broker directly from Flutter.');

      _channel!.stream.listen(
        (message) async {
          try {
            final data = jsonDecode(message) as Map<String, dynamic>;
            final requestId = data['requestId']?.toString();
            final action = data['action']?.toString();
            final payload = data['payload'] as Map<String, dynamic>? ?? {};

            if (requestId != null && action != null) {
              try {
                void wsSend(Map<String, dynamic> response) {
                  if (_isConnected) {
                    _channel?.sink.add(jsonEncode(response));
                  }
                }
                
                final result = await DriveManager.handleFileRequest(action, payload, wsSend, requestId);
                
                if (result != null) {
                  wsSend({
                    'requestId': requestId,
                    'payload': result,
                  });
                }
              } catch (err) {
                if (_isConnected) {
                  _channel?.sink.add(jsonEncode({
                    'requestId': requestId,
                    'error': err.toString(),
                  }));
                }
              }
            }
          } catch (err) {
            debugPrint('[DriveNet Agent] Message parsing error: $err');
          }
        },
        onDone: () {
          debugPrint('[DriveNet Agent] Disconnected.');
          _isConnected = false;
          _scheduleReconnect(token);
        },
        onError: (err) {
          debugPrint('[DriveNet Agent] WS Error: $err');
          _isConnected = false;
        },
      );
    } catch (e) {
      debugPrint('[DriveNet Agent] Connection Failed: $e');
      _isConnected = false;
      _scheduleReconnect(token);
    }
  }

  static void _scheduleReconnect(String token) {
    if (!_shouldReconnect) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      _connect(token);
    });
  }

  static void stop() {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
    _isConnected = false;
  }
}
