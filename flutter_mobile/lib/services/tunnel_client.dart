import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TunnelClient {
  WebSocketChannel? _channel;
  bool _isConnected = false;
  
  bool get isConnected => _isConnected;

  Future<void> connect(String brokerUrl) async {
    final prefs = await SharedPreferences.getInstance();
    final jwt = prefs.getString('drivenet_jwt');
    if (jwt == null) return;

    final wsUrl = brokerUrl.replaceFirst('http', 'ws');
    final uri = Uri.parse('\$wsUrl/api/fs/stream?token=\$jwt&device=mobile');

    try {
      _channel = WebSocketChannel.connect(uri);
      _isConnected = true;
      
      _channel!.stream.listen(
        (message) {
          // Handle incoming messages/files from broker
        },
        onDone: () => _isConnected = false,
        onError: (error) => _isConnected = false,
      );
    } catch (e) {
      _isConnected = false;
    }
  }

  void requestFileList(String path) {
    if (_isConnected && _channel != null) {
      // Send request map to broker for specific folder
      _channel!.sink.add('{"action": "list", "path": "\$path"}');
    }
  }

  /// FEATURE: Chunked Resumable Downloads (Evolution)
  void startChunkedDownload(String remotePath, String localPath) {
    if (_isConnected && _channel != null) {
      // Initiate TUS-style or internal Chunk ranged download
      _channel!.sink.add('{"action": "download_chunk", "path": "\$remotePath", "start": 0, "end": 1048576}');
    }
  }

  void dispose() {
    _channel?.sink.close();
    _isConnected = false;
  }
}
