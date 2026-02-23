import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:system_tray/system_tray.dart';
import 'package:window_manager/window_manager.dart';
import '../services/drive_service.dart';
import '../services/backend_service.dart';
import '../services/tunnel_client.dart';
import 'login_screen.dart';

class DriveScreen extends StatefulWidget {
  const DriveScreen({super.key});
  @override
  State<DriveScreen> createState() => _DriveScreenState();
}

class _DriveScreenState extends State<DriveScreen> with WindowListener {
  List<Map<String, dynamic>> _drives = [];
  String? _selectedDrive;
  bool _isLoading = true;
  bool _isOnline = false;
  bool _goingOnline = false;
  String _userEmail = '';
  String _brokerUrl = 'https://drivenet-broker.onrender.com';

  // Live tunnel status
  bool get _isConnected => TunnelClient.isConnected;

  // Tray
  final SystemTray _systemTray = SystemTray();
  final AppWindow _appWindow = AppWindow();

  // Refresh timer for connection status indicator
  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _loadData();
    _initTray();
    // Refresh status dot every 3 seconds
    _statusTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _statusTimer?.cancel();
    super.dispose();
  }

  @override
  void onWindowClose() async => await windowManager.hide();

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('drivenet_user') ?? '';
    final savedDrive = prefs.getString('selected_drive');
    final brokerUrl = prefs.getString('broker_url') ?? 'https://drivenet-broker.onrender.com';
    final isOnline = prefs.getBool('is_online') ?? false;

    final rawDrives = await DriveService.getWindowsDrives();
    final detailedDrives = await DriveService.getDriveDetails(rawDrives);

    setState(() {
      _userEmail = email;
      _brokerUrl = brokerUrl;
      _drives = detailedDrives;
      _selectedDrive = savedDrive ?? (detailedDrives.isNotEmpty ? detailedDrives[0]['name'] : null);
      _isOnline = isOnline;
      _isLoading = false;
    });

    if (isOnline && _selectedDrive != null) {
      BackendService.syncConfig().catchError((e) => debugPrint('Auto-sync error: $e'));
    }
  }

  Future<void> _goOnline() async {
    if (_selectedDrive == null || _goingOnline) return;
    setState(() => _goingOnline = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('selected_drive', _selectedDrive!);
      await prefs.setBool('is_online', true);

      // Connect WebSocket tunnel to cloud
      await BackendService.syncConfig();

      // Register drive → email association on backend (email is the key)
      final token = prefs.getString('drivenet_jwt') ?? '';
      try {
        final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
        final req = await client.postUrl(Uri.parse('$_brokerUrl/api/fs/me/register-drive'));
        req.headers.set('Authorization', 'Bearer $token');
        req.headers.set('Content-Type', 'application/json');
        req.write('{"drive":"${_selectedDrive!.replaceAll('\\', '\\\\')}"}');
        await req.close();
      } catch (e) {
        debugPrint('[DriveNet] Drive registration (non-fatal): $e');
      }

      setState(() { _isOnline = true; _goingOnline = false; });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('✓ $_selectedDrive\\ is now YOUR cloud drive — access it from anywhere',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFFFF4655),
          duration: const Duration(seconds: 4),
        ));
      }
    } catch (e) {
      setState(() => _goingOnline = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'), backgroundColor: Colors.red[900],
        ));
      }
    }
  }

  Future<void> _goOffline() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_online', false);
    BackendService.stopAgent();
    setState(() => _isOnline = false);
  }

  Future<void> _handleLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('drivenet_jwt');
    await prefs.remove('drivenet_user');
    await prefs.setBool('is_online', false);
    BackendService.stopAgent();
    if (mounted) {
      await windowManager.show();
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  Future<void> _initTray() async {
    try {
      await _systemTray.initSystemTray(title: 'DriveNet', iconPath: 'assets/icon.ico');
      final menu = Menu();
      await menu.buildFrom([
        MenuItemLabel(label: 'DriveNet Agent', enabled: false),
        MenuSeparator(),
        MenuItemLabel(label: 'Show Window', onClicked: (_) => _appWindow.show()),
        MenuItemLabel(label: 'Go Offline', onClicked: (_) => _goOffline()),
        MenuItemLabel(label: 'Logout', onClicked: (_) => _handleLogout()),
        MenuItemLabel(label: 'Exit', onClicked: (_) { windowManager.destroy(); exit(0); }),
      ]);
      await _systemTray.setContextMenu(menu);
      _systemTray.registerSystemTrayEventHandler((ev) {
        if (ev == kSystemTrayEventClick) _appWindow.show();
        if (ev == kSystemTrayEventRightClick) _systemTray.popUpContextMenu();
      });
    } catch (e) { debugPrint('Tray skipped: $e'); }
  }

  // ─── BUILD ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D14),
      body: Stack(children: [
        Column(children: [
          _buildTitleBar(),
          Expanded(child: _buildBody()),
        ]),
        // Window drag region
        Positioned(
          top: 0, left: 0, right: 0,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanStart: (_) => windowManager.startDragging(),
            child: const SizedBox(height: 44),
          ),
        ),
      ]),
    );
  }

  Widget _buildTitleBar() {
    return Container(
      height: 44,
      color: const Color(0xFF0A0A10),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        Container(
          width: 24, height: 24,
          decoration: BoxDecoration(color: const Color(0xFFFF4655), borderRadius: BorderRadius.circular(4)),
          child: const Center(child: Icon(Icons.cloud_sync, color: Colors.white, size: 14)),
        ),
        const SizedBox(width: 10),
        const Text('DRIVENET', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 3)),
        const SizedBox(width: 6),
        Text('AGENT', style: TextStyle(color: Colors.grey[600], fontSize: 10, letterSpacing: 2)),
        const Spacer(),
        // Status dot
        if (_isOnline) ...[
          Container(
            width: 7, height: 7,
            decoration: BoxDecoration(
              color: _isConnected ? const Color(0xFFFF4655) : Colors.orange,
              borderRadius: BorderRadius.circular(4),
              boxShadow: [BoxShadow(color: _isConnected ? const Color(0xFFFF4655) : Colors.orange, blurRadius: 8)],
            ),
          ),
          const SizedBox(width: 6),
          Text(_isConnected ? 'ONLINE' : 'CONNECTING...', style: TextStyle(
            color: _isConnected ? const Color(0xFFFF4655) : Colors.orange,
            fontSize: 9, letterSpacing: 1.5, fontWeight: FontWeight.bold,
          )),
          const SizedBox(width: 16),
        ],
        InkWell(
          onTap: () => windowManager.hide(),
          child: Container(
            width: 28, height: 24,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(3), border: Border.all(color: Colors.white10)),
            child: const Center(child: Text('─', style: TextStyle(color: Colors.white38, fontSize: 12))),
          ),
        ),
        const SizedBox(width: 4),
        InkWell(
          onTap: () => windowManager.hide(),
          child: Container(
            width: 28, height: 24,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(3), border: Border.all(color: Colors.white10)),
            child: const Center(child: Text('✕', style: TextStyle(color: Colors.white38, fontSize: 11))),
          ),
        ),
      ]),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFFFF4655)));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── User identity ──────────────────────────────────────────────
        _buildUserCard(),
        const SizedBox(height: 24),

        // ── Drive selection ────────────────────────────────────────────
        const Text('SELECT YOUR DRIVE', style: TextStyle(
          color: Colors.white70, fontSize: 10, letterSpacing: 3, fontWeight: FontWeight.bold,
        )),
        const SizedBox(height: 12),
        if (_drives.isEmpty)
          _buildNoDrives()
        else
          ..._drives.map((d) => _buildDriveCard(d)),
        const SizedBox(height: 24),

        // ── GO ONLINE button ───────────────────────────────────────────
        _buildActionButton(),
        const SizedBox(height: 16),

        // ── Active session info (shows when online) ────────────────────
        if (_isOnline) _buildStatusPanel(),
        if (_isOnline) const SizedBox(height: 16),

        // ── Help text ──────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF0A0A12),
            border: Border.all(color: Colors.white10),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.info_outline, color: Colors.white24, size: 16),
            const SizedBox(width: 10),
            Expanded(child: Text(
              'After going online, open ${_brokerUrl.replaceAll('https://drivenet-broker.onrender.com', 'your web app')} in any browser on any network. Log in with the same Gmail to access your drive anywhere in the world.',
              style: TextStyle(color: Colors.grey[600], fontSize: 10, height: 1.6),
            )),
          ]),
        ),
      ]),
    );
  }

  Widget _buildUserCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A12),
        border: Border.all(color: Colors.white10),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFFFF4655).withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFFF4655).withOpacity(0.4)),
          ),
          child: const Center(child: Icon(Icons.person, color: Color(0xFFFF4655), size: 20)),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_userEmail, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text('Signed in via Google', style: TextStyle(color: Colors.grey[600], fontSize: 10)),
        ])),
        // Logout
        InkWell(
          onTap: _handleLogout,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(children: [
              Icon(Icons.logout, color: Colors.grey[700], size: 14),
              const SizedBox(width: 4),
              Text('Logout', style: TextStyle(color: Colors.grey[700], fontSize: 10)),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _buildDriveCard(Map<String, dynamic> drive) {
    final name = drive['name'] as String;
    final label = (drive['label'] as String?) ?? name;
    final usedGb = (drive['usedGb'] as num).toDouble();
    final totalGb = (drive['totalGb'] as num).toDouble();
    final pct = totalGb > 0 ? (usedGb / totalGb) : 0.0;
    final isSelected = _selectedDrive == name;
    final isLive = _isOnline && isSelected;

    return GestureDetector(
      onTap: () async {
        setState(() => _selectedDrive = name);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('selected_drive', name);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFF4655).withOpacity(0.07) : const Color(0xFF0A0A12),
          border: Border.all(
            color: isSelected ? const Color(0xFFFF4655) : Colors.white10,
            width: isSelected ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFFFF4655) : const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(child: Icon(Icons.storage, color: isSelected ? Colors.white : Colors.grey[600], size: 20)),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(label.toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1)),
              const SizedBox(width: 8),
              if (isLive) _chip('● LIVE', Colors.greenAccent),
              if (isSelected && !isLive) _chip('SELECTED', const Color(0xFFFF4655)),
            ]),
            const SizedBox(height: 4),
            Text('${usedGb.toStringAsFixed(1)} GB used of ${totalGb.toStringAsFixed(1)} GB',
                style: TextStyle(color: Colors.grey[500], fontSize: 10)),
            const SizedBox(height: 8),
            // Storage bar
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: SizedBox(
                height: 3,
                child: LinearProgressIndicator(
                  value: pct.clamp(0.0, 1.0),
                  backgroundColor: Colors.white10,
                  color: isSelected ? const Color(0xFFFF4655) : const Color(0xFF137FEC),
                ),
              ),
            ),
          ])),
        ]),
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      margin: const EdgeInsets.only(left: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildActionButton() {
    return SizedBox(
      width: double.infinity,
      child: _isOnline
          ? Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _goOffline,
                  icon: const Icon(Icons.wifi_off, size: 16),
                  label: const Text('GO OFFLINE', style: TextStyle(letterSpacing: 2, fontWeight: FontWeight.bold, fontSize: 11)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: const BorderSide(color: Colors.white24),
                    foregroundColor: Colors.white54,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: _selectedDrive != null ? _goOnline : null,
                  icon: Icon(_isConnected ? Icons.wifi_tethering : Icons.sync, size: 16, color: Colors.greenAccent),
                  label: Text(
                    _isConnected ? '✓ DRIVE ONLINE' : 'RECONNECTING...',
                    style: TextStyle(
                      color: _isConnected ? Colors.greenAccent : Colors.orange,
                      fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 12,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0a2a0a),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    elevation: 0,
                  ),
                ),
              ),
            ])
          : ElevatedButton.icon(
              onPressed: (_selectedDrive == null || _goingOnline) ? null : _goOnline,
              icon: _goingOnline
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.cloud_upload, size: 18, color: Colors.white),
              label: Text(
                _goingOnline ? 'CONNECTING...' : 'GO ONLINE — MAKE IT MY CLOUD',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 1.5, fontSize: 12),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF4655),
                disabledBackgroundColor: Colors.grey[800],
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                elevation: 0,
              ),
            ),
    );
  }

  // Shows the active session details when the drive is online.
  // Answers: which email is logged in + which drive is being served + where to access it.
  Widget _buildStatusPanel() {
    final webUrl = _brokerUrl.contains('onrender.com')
        ? 'https://drivenet.vercel.app'
        : _brokerUrl;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF001a0e),
        border: Border.all(color: Colors.greenAccent.withOpacity(0.4), width: 1.5),
        borderRadius: BorderRadius.circular(4),
        boxShadow: [BoxShadow(color: Colors.greenAccent.withOpacity(0.06), blurRadius: 16)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(
              color: Colors.greenAccent,
              borderRadius: BorderRadius.circular(4),
              boxShadow: const [BoxShadow(color: Colors.greenAccent, blurRadius: 8)],
            ),
          ),
          const SizedBox(width: 10),
          const Text('ACTIVE DRIVE SESSION', style: TextStyle(
            color: Colors.greenAccent, fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.bold,
          )),
        ]),
        const SizedBox(height: 14),
        const Divider(color: Colors.white10, height: 1),
        const SizedBox(height: 14),

        _statusRow(Icons.account_circle, 'ACCOUNT', _userEmail, Colors.greenAccent,
            subtitle: 'Gmail — your personal access key'),
        const SizedBox(height: 12),

        _statusRow(Icons.storage, 'DRIVE SERVING', _selectedDrive != null ? '$_selectedDrive\\' : '—',
            const Color(0xFFFF4655), subtitle: 'Shared as your personal cloud drive'),
        const SizedBox(height: 12),

        _statusRow(Icons.cloud_done, 'TUNNEL', _isConnected ? 'Connected to cloud' : 'Connecting...',
            _isConnected ? Colors.greenAccent : Colors.orange, subtitle: _brokerUrl),
        const SizedBox(height: 12),

        _statusRow(Icons.open_in_browser, 'ACCESS FROM ANY DEVICE', webUrl,
            const Color(0xFF137FEC), subtitle: 'Open in browser on any network — log in with same Gmail'),
      ]),
    );
  }

  Widget _statusRow(IconData icon, String label, String value, Color color, {String? subtitle}) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 32, height: 32,
        decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
        child: Center(child: Icon(icon, color: color, size: 16)),
      ),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 9, letterSpacing: 2, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'Courier')),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(subtitle, style: TextStyle(color: Colors.grey[700], fontSize: 9)),
        ],
      ])),
    ]);
  }

  Widget _buildNoDrives() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(color: const Color(0xFF0A0A12), border: Border.all(color: Colors.white10), borderRadius: BorderRadius.circular(4)),
      child: Center(child: Column(children: [
        Icon(Icons.storage, size: 40, color: Colors.grey[800]),
        const SizedBox(height: 12),
        Text('No drives detected', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: _loadData,
          style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFFFF4655)), foregroundColor: const Color(0xFFFF4655)),
          child: const Text('Refresh'),
        ),
      ])),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suf = ['B', 'KB', 'MB', 'GB', 'TB'];
    int i = 0;
    double val = bytes.toDouble();
    while (val >= 1024 && i < suf.length - 1) { val /= 1024; i++; }
    return '${val.toStringAsFixed(1)} ${suf[i]}';
  }
}
