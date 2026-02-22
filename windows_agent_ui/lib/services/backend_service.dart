import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'tunnel_client.dart';

class BackendService {
  static Future<void> startAgent() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('drivenet_jwt') ?? '';
    if (token.isNotEmpty) {
      await TunnelClient.start(token);
    }
  }

  static Future<void> stopAgent() async {
    TunnelClient.stop();
  }

  static Future<void> syncConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('drivenet_jwt') ?? '';
    final isOnline = prefs.getBool('is_online') ?? false;

    if (isOnline && token.isNotEmpty) {
      if (!TunnelClient.isConnected) {
        await TunnelClient.start(token);
      }
    } else {
      TunnelClient.stop();
    }
  }
}
