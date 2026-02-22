import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'drive_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoading = false;
  String _statusText = 'PERIPHERAL DATA ACCESS REQUIRED';
  String _statusCode = '// AUTH_PENDING';
  HttpServer? _callbackServer;

  @override
  void dispose() {
    _callbackServer?.close(force: true);
    super.dispose();
  }

  Future<void> _startGoogleSignIn() async {
    setState(() {
      _isLoading = true;
      _statusText = 'LAUNCHING AUTH GATEWAY...';
      _statusCode = '// CONNECTING';
    });

    try {
      // Start local callback server on 5173 redirect
      await _callbackServer?.close(force: true);
      _callbackServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 9292);
      
      // Open the web frontend login page in the browser
      // The web frontend will handle the Google OAuth and save the JWT to localStorage
      // We redirect the user to a special deep-link URL that our local server will intercept
      final loginUrl = Uri.parse('http://localhost:5173/login?agent=true');
      await launchUrl(loginUrl, mode: LaunchMode.externalApplication);

      setState(() {
        _statusText = 'BROWSER OPENED — SIGN IN WITH GOOGLE';
        _statusCode = '// AWAITING_RESPONSE';
      });

      // Listen for callback — the web frontend will POST the JWT token to our local server
      await for (final request in _callbackServer!) {
        if (request.method == 'POST' && request.uri.path == '/token') {
          final body = await utf8.decoder.bind(request).join();
          final data = jsonDecode(body) as Map<String, dynamic>;
          
          final token = data['token'] as String?;
          final user = data['user'] as String?;

          if (token != null && token.isNotEmpty) {
            request.response
              ..headers.add('Access-Control-Allow-Origin', '*')
              ..statusCode = 200
              ..write('{"status":"ok"}');
            await request.response.close();
            await _callbackServer!.close(force: true);
            
            // Save session to prefs
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('drivenet_jwt', token);
            await prefs.setString('drivenet_user', user ?? 'user');

            if (mounted) {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const DriveScreen()),
                (route) => false,
              );
            }
            break;
          } else {
            request.response
              ..statusCode = 400
              ..write('{"error":"no token"}');
            await request.response.close();
          }
        } else if (request.method == 'OPTIONS') {
          // CORS preflight
          request.response
            ..headers.add('Access-Control-Allow-Origin', '*')
            ..headers.add('Access-Control-Allow-Methods', 'POST, GET, OPTIONS')
            ..headers.add('Access-Control-Allow-Headers', 'Content-Type')
            ..statusCode = 200;
          await request.response.close();
        } else {
          request.response..statusCode = 404;
          await request.response.close();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusText = 'CONNECTION FAILED — ${e.runtimeType}';
          _statusCode = '// ERROR';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D14),
      body: Stack(
        children: [
          // Drag handle for frameless window
          Positioned(
            top: 0, left: 0, right: 0,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: (_) {},
              child: const SizedBox(height: 40),
            ),
          ),
          // Main layout: left red panel + right dark panel
          Row(
            children: [
              // === LEFT RED PANEL ===
              Container(
                width: 260,
                color: const Color(0xFFFF4655),
                padding: const EdgeInsets.all(32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Logo area
                    Row(
                      children: [
                        Image.asset(
                          'assets/icon.ico',
                          width: 36,
                          height: 36,
                          errorBuilder: (_, __, ___) => Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Icon(Icons.usb, color: Colors.white, size: 22),
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'USB-TO-CLOUD',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                            letterSpacing: 2.0,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      margin: const EdgeInsets.symmetric(vertical: 20),
                      height: 2,
                      width: 40,
                      color: Colors.white.withOpacity(0.5),
                    ),
                    const Text(
                      'SECURE PERIPHERAL ENCRYPTION & CLOUD SYNCHRONIZATION AGENT.',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        letterSpacing: 1.0,
                        height: 1.8,
                      ),
                    ),
                    const Spacer(),
                    // Status indicators
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4),
                            boxShadow: const [BoxShadow(color: Colors.white54, blurRadius: 6)],
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text('STATUS: ONLINE', style: TextStyle(color: Colors.white, fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('ID: 44-X00-SECURE-TERM', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 9, fontFamily: 'Courier')),
                    Text('LOC: [GLOBAL_CLUSTER_01]', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 9, fontFamily: 'Courier')),
                  ],
                ),
              ),

              // === RIGHT DARK PANEL ===
              Expanded(
                child: Container(
                  color: const Color(0xFF1A1A2E),
                  padding: const EdgeInsets.all(40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Top-right status codes
                      Align(
                        alignment: Alignment.topRight,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('// 0x442', style: TextStyle(color: Colors.grey[600], fontFamily: 'Courier', fontSize: 10)),
                            Text(_statusCode, style: const TextStyle(color: Color(0xFFFF4655), fontFamily: 'Courier', fontSize: 10, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      const Spacer(),
                      // Title
                      const Text(
                        'AGENT AUTHENTICATION',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 28,
                          letterSpacing: 2.0,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _statusText,
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 11,
                          letterSpacing: 3.0,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 40),

                      // Google Sign-In Button
                      SizedBox(
                        width: double.infinity,
                        child: _isLoading
                            ? Container(
                                padding: const EdgeInsets.symmetric(vertical: 20),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  border: Border.all(color: const Color(0xFFFF4655).withOpacity(0.5)),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Color(0xFFFF4655), strokeWidth: 2)),
                                    const SizedBox(width: 16),
                                    Text('// WAITING FOR BROWSER AUTH...', style: TextStyle(color: Colors.grey[400], letterSpacing: 2.0, fontSize: 12, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              )
                            : ElevatedButton(
                                onPressed: _startGoogleSignIn,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFFF4655),
                                  padding: const EdgeInsets.symmetric(vertical: 22),
                                  shape: const ContinuousRectangleBorder(),
                                  elevation: 0,
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text('[G]', style: TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 2.0)),
                                    SizedBox(width: 16),
                                    Text(
                                      'SIGN IN WITH GOOGLE',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 3.0,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                      ),
                      const SizedBox(height: 30),

                      // Stay connected info box
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          border: Border(left: BorderSide(color: const Color(0xFFFF4655).withOpacity(0.8), width: 3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.refresh, color: Color(0xFFFF4655), size: 14),
                                SizedBox(width: 8),
                                Text('STAY CONNECTED', style: TextStyle(color: Color(0xFFFF4655), fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 2.0)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'THIS SERVICE RUNS ON SYSTEM STARTUP. CONTINUOUSLY MAINTAINS CONNECTION. NO MANUAL INTERACTION REQUIRED AFTER BOOT.',
                              style: TextStyle(color: Colors.grey[500], fontSize: 10, height: 1.7, letterSpacing: 1.0),
                            ),
                          ],
                        ),
                      ),

                      const Spacer(),
                      // Bottom system info
                      Row(
                        children: [
                          Text('SYSTEM_ARCH: WIN_X64', style: TextStyle(color: Colors.grey[700], fontSize: 9, fontFamily: 'Courier')),
                          const SizedBox(width: 20),
                          Text('BUILD: STABLE_1.0.2', style: TextStyle(color: Colors.grey[700], fontSize: 9, fontFamily: 'Courier')),
                          const SizedBox(width: 20),
                          Text('KERNEL: USB_SRV_V2', style: TextStyle(color: Colors.grey[700], fontSize: 9, fontFamily: 'Courier')),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // Top window controls (close / minimize)
          Positioned(
            top: 8, right: 12,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.close, size: 16, color: Colors.white38),
                  onPressed: () async {
                    await _callbackServer?.close(force: true);
                    exit(0);
                  },
                  tooltip: 'Exit',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
