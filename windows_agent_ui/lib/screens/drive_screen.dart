import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:system_tray/system_tray.dart';
import 'package:window_manager/window_manager.dart';
import '../services/drive_service.dart';
import '../services/backend_service.dart';
import 'login_screen.dart';

class DriveScreen extends StatefulWidget {
  const DriveScreen({super.key});

  @override
  State<DriveScreen> createState() => _DriveScreenState();
}

class _DriveScreenState extends State<DriveScreen> with WindowListener {
  static const int kRefreshInterval = 5;

  // Nav pages
  int _navIndex = 0; // 0=Drives 1=Telemetry 2=Encryption 3=Config

  List<Map<String, dynamic>> _drives = [];
  String? _selectedDrive;
  bool _isLoading = true;
  bool _isOnline = false;
  bool _goingOnline = false;
  String _userEmail = '';

  // Tray
  final SystemTray _systemTray = SystemTray();
  final AppWindow _appWindow = AppWindow();

  // Telemetry
  Map<String, dynamic>? _telemetry;
  List<String> _localIPs = [];
  Timer? _telemetryTimer;

  // Config
  bool _autoRefresh = true;
  bool _startOnBoot = true;
  int _refreshInterval = 5;
  String _dashboardUrl = 'https://drivenet.vercel.app';
  String _brokerUrl = 'https://drivenet-broker.onrender.com';

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _loadData();
    _initTray();
    _fetchTelemetry();
    _telemetryTimer = Timer.periodic(const Duration(seconds: kRefreshInterval), (_) => _fetchTelemetry());
    _loadLocalIPs();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _telemetryTimer?.cancel();
    super.dispose();
  }

  @override
  void onWindowClose() async {
    // X button → hide to tray instead of exit
    await windowManager.hide();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('drivenet_user') ?? '';
    final savedDrive = prefs.getString('selected_drive');
    _autoRefresh = prefs.getBool('auto_refresh') ?? true;
    _startOnBoot = prefs.getBool('start_on_boot') ?? true;
    final dashUrl = prefs.getString('dashboard_url') ?? 'https://drivenet.vercel.app';
    final brokUrl = prefs.getString('broker_url') ?? 'https://drivenet-broker.onrender.com';

    final rawDrives = await DriveService.getWindowsDrives();
    final detailedDrives = await DriveService.getDriveDetails(rawDrives);

    setState(() {
      _userEmail = email;
      _dashboardUrl = dashUrl;
      _brokerUrl = brokUrl;
      _drives = detailedDrives;
      _selectedDrive = savedDrive ?? (detailedDrives.isNotEmpty ? detailedDrives[0]['name'] : null);
      _isOnline = prefs.getBool('is_online') ?? false;
      _isLoading = false;
    });

    if (_isOnline && _selectedDrive != null) {
      BackendService.syncConfig().catchError((e) => debugPrint('Auto-sync error: $e'));
    }
  }

  Future<void> _loadLocalIPs() async {
    try {
      final interfaces = await NetworkInterface.list();
      final ips = <String>[];
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            ips.add('${iface.name}: ${addr.address}');
          }
        }
      }
      setState(() => _localIPs = ips);
    } catch (e) {
      debugPrint('IP fetch error: $e');
    }
  }

  Future<void> _fetchTelemetry() async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 3);
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('drivenet_jwt') ?? '';
      final brokerUrl = prefs.getString('broker_url') ?? 'https://drivenet-broker.onrender.com';
      final req = await client.getUrl(Uri.parse('$brokerUrl/api/fs/stats'));
      req.headers.set('Authorization', 'Bearer $token');
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode == 200) {
        final data = jsonDecode(body) as Map<String, dynamic>;
        if (mounted) setState(() => _telemetry = data);
      }
    } catch (_) {}
  }

  Future<void> _initTray() async {
    try {
      // Use the .ico file on Windows (required format for system tray)
      const iconPath = 'assets/icon.ico';
      await _systemTray.initSystemTray(title: 'DriveNet', iconPath: iconPath);
      final menu = Menu();
      await menu.buildFrom([
        MenuItemLabel(label: 'DriveNet Agent', enabled: false),
        MenuSeparator(),
        MenuItemLabel(label: 'Show Window', onClicked: (_) => _appWindow.show()),
        MenuItemLabel(label: 'Go Offline', onClicked: (_) async {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('is_online', false);
          if (mounted) setState(() => _isOnline = false);
        }),
        MenuItemLabel(label: 'Logout', onClicked: (_) => _handleLogout()),
        MenuItemLabel(label: 'Exit', onClicked: (_) { windowManager.destroy(); exit(0); }),
      ]);
      await _systemTray.setContextMenu(menu);
      _systemTray.registerSystemTrayEventHandler((ev) {
        if (ev == kSystemTrayEventClick) _appWindow.show();
        if (ev == kSystemTrayEventRightClick) _systemTray.popUpContextMenu();
      });
    } catch (e) {
      debugPrint('Tray skipped: $e');
    }
  }

  Future<void> _goOnline() async {
    if (_selectedDrive == null || _goingOnline) return;
    setState(() => _goingOnline = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('selected_drive', _selectedDrive!);
      await prefs.setStringList('selected_drives', [_selectedDrive!]);
      await prefs.setBool('is_online', true);
      
      // Fire and forget so we don't wait for potential HTTP timeouts
      BackendService.syncConfig().catchError((e) => debugPrint('Sync error: $e'));
      
      setState(() { _isOnline = true; _goingOnline = false; });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('✓ $_selectedDrive\\ IS ONLINE — Web access enabled', style: const TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFFFF4655),
          duration: const Duration(seconds: 4),
        ));
      }
    } catch (e) {
      setState(() => _goingOnline = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed: $e'),
          backgroundColor: Colors.red[900],
        ));
      }
    }
  }

  Future<void> _goOffline() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_online', false);
    setState(() => _isOnline = false);
  }

  Future<void> _handleLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('drivenet_jwt');
    await prefs.remove('drivenet_user');
    await prefs.setBool('is_online', false);
    await BackendService.syncConfig();
    if (mounted) {
      await windowManager.show();
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  // ─── BUILD ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D14),
      body: Stack(children: [
        Column(children: [
          _buildTopBar(),
          Expanded(child: Row(children: [
            _buildSidebar(),
            Expanded(child: _buildPageContent()),
          ])),
          _buildBottomBar(),
        ]),
        // Drag region
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

  Widget _buildPageContent() {
    switch (_navIndex) {
      case 0: return _buildDrivesPage();
      case 1: return _buildTelemetryPage();
      case 2: return _buildEncryptionPage();
      case 3: return _buildConfigPage();
      default: return _buildDrivesPage();
    }
  }

  // ─── TOP BAR ─────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Container(
      height: 44,
      color: const Color(0xFF0D0D14),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        Container(
          width: 28, height: 28,
          decoration: BoxDecoration(color: const Color(0xFFFF4655), borderRadius: BorderRadius.circular(4)),
          child: const Center(child: Icon(Icons.usb, color: Colors.white, size: 16)),
        ),
        const SizedBox(width: 12),
        const Text('DEVICE INTERFACE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 2.0)),
        const Text(' // ', style: TextStyle(color: Colors.white24, fontSize: 12)),
        Text(_navLabel(), style: const TextStyle(color: Color(0xFFFF4655), fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 2.0)),
        const SizedBox(width: 8),
        Text('($_userEmail)', style: TextStyle(color: Colors.grey[600], fontSize: 9, fontFamily: 'Courier')),
        const Spacer(),
        if (_isOnline) ...[
          Container(width: 8, height: 8, decoration: BoxDecoration(color: const Color(0xFFFF4655), borderRadius: BorderRadius.circular(4), boxShadow: const [BoxShadow(color: Color(0xFFFF4655), blurRadius: 6)])),
          const SizedBox(width: 6),
          const Text('ONLINE', style: TextStyle(color: Color(0xFFFF4655), fontSize: 9, letterSpacing: 1.5, fontWeight: FontWeight.bold)),
          const SizedBox(width: 12),
        ],
        Text('V2.4.0-STABLE', style: TextStyle(color: Colors.grey[700], fontSize: 9, fontFamily: 'Courier')),
        const SizedBox(width: 12),
        InkWell(
          onTap: () => windowManager.hide(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(border: Border.all(color: Colors.white12)),
            child: const Text('─', style: TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(width: 6),
        InkWell(
          onTap: () => windowManager.hide(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(border: Border.all(color: Colors.white12)),
            child: const Text('✕', style: TextStyle(color: Colors.white38, fontSize: 11)),
          ),
        ),
      ]),
    );
  }

  String _navLabel() {
    switch (_navIndex) {
      case 0: return 'DRIVE SELECTION';
      case 1: return 'TELEMETRY';
      case 2: return 'ENCRYPTION';
      case 3: return 'CONFIGURATION';
      default: return 'DRIVE SELECTION';
    }
  }

  // ─── SIDEBAR ─────────────────────────────────────────────────────────────

  Widget _buildSidebar() {
    return Container(
      width: 180,
      color: const Color(0xFF0A0A12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.only(left: 16, top: 20, bottom: 8),
          child: Text('NAVIGATION', style: TextStyle(color: Colors.grey[700], fontSize: 9, letterSpacing: 2.0, fontWeight: FontWeight.bold)),
        ),
        _navItem(Icons.storage, 'DRIVES', 0),
        _navItem(Icons.analytics_outlined, 'TELEMETRY', 1),
        _navItem(Icons.lock_outline, 'ENCRYPTION', 2),
        _navItem(Icons.settings_outlined, 'CONFIG', 3),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('COMMS STRENGTH', style: TextStyle(color: Colors.grey[700], fontSize: 8, letterSpacing: 1.5)),
            const SizedBox(height: 8),
            Row(children: List.generate(5, (i) => Container(
              margin: const EdgeInsets.only(right: 3),
              width: 10,
              height: 12 + (i * 3.0),
              color: i < (_isOnline ? 4 : 1) ? const Color(0xFFFF4655) : Colors.grey[800],
            ))),
            const SizedBox(height: 16),
            Text('TRAY STATE', style: TextStyle(color: Colors.grey[700], fontSize: 8, letterSpacing: 1.5)),
            const SizedBox(height: 4),
            Row(children: [
              Container(width: 7, height: 7, decoration: BoxDecoration(
                color: _isOnline ? const Color(0xFFFF4655) : Colors.grey,
                borderRadius: BorderRadius.circular(3.5),
                boxShadow: _isOnline ? const [BoxShadow(color: Color(0xFFFF4655), blurRadius: 6)] : [],
              )),
              const SizedBox(width: 6),
              Text(_isOnline ? 'ACTIVE' : 'STANDBY', style: TextStyle(color: _isOnline ? const Color(0xFFFF4655) : Colors.grey, fontSize: 9, letterSpacing: 1.5, fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 16),
            InkWell(onTap: _handleLogout, child: Text('[ LOGOUT ]', style: TextStyle(color: Colors.grey[600], fontSize: 9, letterSpacing: 1.5))),
          ]),
        ),
      ]),
    );
  }

  Widget _navItem(IconData icon, String label, int index) {
    final selected = _navIndex == index;
    return InkWell(
      onTap: () => setState(() => _navIndex = index),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFF4655) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: ListTile(
          dense: true, minLeadingWidth: 0,
          leading: Icon(icon, color: selected ? Colors.white : Colors.grey[700], size: 16),
          title: Text(label, style: TextStyle(color: selected ? Colors.white : Colors.grey[700], fontSize: 10, letterSpacing: 2.0, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  // ─── DRIVES PAGE ─────────────────────────────────────────────────────────

  Widget _buildDrivesPage() {
    return Container(
      color: const Color(0xFF0F0F1A),
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 3, height: 24, color: const Color(0xFFFF4655)),
          const SizedBox(width: 12),
          const Text('CONNECTED TACTICAL STORAGE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 2.0)),
          const Spacer(),
          Row(children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: const Color(0xFFFF4655), borderRadius: BorderRadius.circular(4), boxShadow: const [BoxShadow(color: Color(0xFFFF4655), blurRadius: 8)])),
            const SizedBox(width: 8),
            const Text('SCANNER ACTIVE', style: TextStyle(color: Color(0xFFFF4655), fontSize: 10, letterSpacing: 2.0, fontWeight: FontWeight.bold)),
          ]),
        ]),
        const SizedBox(height: 20),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF4655)))
              : _drives.isEmpty
                  ? _buildNoDrives()
                  : ListView(children: [
                      ..._drives.map((d) => _buildDriveCard(d)),
                      _buildAddDriveButton(),
                    ]),
        ),
        // Bottom action bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(color: const Color(0xFF0A0A12), border: Border.all(color: Colors.white10)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Toggles row
              Row(children: [
                _toggleWidget('AUTO-REFRESH:', _autoRefresh),
                const SizedBox(width: 24),
                _toggleWidget('START ON BOOT:', _startOnBoot),
              ]),
              const SizedBox(height: 10),
              // Buttons row
              Row(children: [
                if (_isOnline) ...[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _goOffline,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white24),
                        shape: const ContinuousRectangleBorder(),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('GO OFFLINE', style: TextStyle(color: Colors.white54, fontSize: 11, letterSpacing: 1.5)),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: (_selectedDrive == null || _goingOnline) ? null : _goOnline,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isOnline ? const Color(0xFF0a2a0a) : const Color(0xFFFF4655),
                      disabledBackgroundColor: Colors.grey[800],
                      shape: const ContinuousRectangleBorder(),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _goingOnline
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Icon(_isOnline ? Icons.wifi_tethering : Icons.wifi_tethering_sharp,
                                size: 16,
                                color: _isOnline ? Colors.greenAccent : Colors.white),
                            const SizedBox(width: 8),
                            Text(
                              _isOnline ? '✓ SWITCH DRIVE' : 'GO ONLINE',
                              style: TextStyle(
                                color: _isOnline ? Colors.greenAccent : Colors.white,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 2.0,
                                fontSize: 12,
                              ),
                            ),
                          ]),
                  ),
                ),
              ]),
            ],
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
    final isActiveDrive = _isOnline && isSelected;

    return GestureDetector(
      onTap: () async {
        setState(() { _selectedDrive = name; });
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('selected_drive', name);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFF4655).withOpacity(0.08) : const Color(0xFF0A0A12),
          border: Border.all(color: isSelected ? const Color(0xFFFF4655) : Colors.white10, width: isSelected ? 2 : 1),
        ),
        child: Row(children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(color: isSelected ? const Color(0xFFFF4655) : const Color(0xFF1A1A2E), borderRadius: BorderRadius.circular(8)),
            child: Center(child: Icon(Icons.usb, color: isSelected ? Colors.white : Colors.grey[600], size: 24)),
          ),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(label.toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 1.5)),
              const SizedBox(width: 8),
              if (isActiveDrive) Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.greenAccent.withOpacity(0.2), borderRadius: BorderRadius.circular(3)),
                child: const Text('● LIVE', style: TextStyle(color: Colors.greenAccent, fontSize: 8, fontWeight: FontWeight.bold)),
              ) else if (isSelected) Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: const Color(0xFFFF4655).withOpacity(0.15), borderRadius: BorderRadius.circular(3)),
                child: const Text('SELECTED', style: TextStyle(color: Color(0xFFFF4655), fontSize: 8, fontWeight: FontWeight.bold)),
              ),
              const Spacer(),
              Text('CAPACITY UTILIZATION', style: TextStyle(color: Colors.grey[600], fontSize: 9, letterSpacing: 1.5)),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              Text('DRIVE: $name\\', style: TextStyle(color: Colors.grey[500], fontSize: 10, fontFamily: 'Courier')),
              const Spacer(),
              Text('${usedGb.toStringAsFixed(1)} GB  /  ${totalGb.toStringAsFixed(1)} GB',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
            ]),
            const SizedBox(height: 10),
            if (isSelected) ...[
              Row(children: [
                Text('BLOCK-SEGMENTED DATA ALLOCATION', style: TextStyle(color: Colors.grey[700], fontSize: 8, letterSpacing: 1)),
                const Spacer(),
                Text('${(pct * 100).toStringAsFixed(1)}%', style: const TextStyle(color: Color(0xFFFF4655), fontSize: 9, fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 4),
            ],
            SizedBox(
              height: 4,
              child: Row(children: List.generate(24, (i) {
                final filled = i < (pct * 24).round();
                return Expanded(child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 0.5),
                  color: filled ? (isSelected ? const Color(0xFFFF4655) : const Color(0xFF137FEC)) : Colors.white10,
                ));
              })),
            ),
          ])),
        ]),
      ),
    );
  }

  Widget _buildAddDriveButton() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(border: Border.all(color: Colors.white10)),
      child: Center(child: Column(children: [
        Icon(Icons.add_circle_outline, color: Colors.grey[700], size: 28),
        const SizedBox(height: 8),
        Text('CONNECT NEW TACTICAL DEVICE', style: TextStyle(color: Colors.grey[700], fontSize: 10, letterSpacing: 2.0, fontWeight: FontWeight.bold)),
      ])),
    );
  }

  Widget _buildNoDrives() {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.usb_off, size: 48, color: Colors.grey[700]),
      const SizedBox(height: 16),
      Text('NO DRIVES DETECTED', style: TextStyle(color: Colors.grey[600], fontSize: 14, letterSpacing: 3.0, fontWeight: FontWeight.bold)),
      const SizedBox(height: 16),
      ElevatedButton(onPressed: _loadData, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF4655)), child: const Text('REFRESH SCANNER')),
    ]));
  }

  // ─── TELEMETRY PAGE ──────────────────────────────────────────────────────

  Widget _buildTelemetryPage() {
    final t = _telemetry;
    return Container(
      color: const Color(0xFF0F0F1A),
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _pageHeader('SYSTEM TELEMETRY', 'LIVE — refreshes every ${kRefreshInterval}s'),
        const SizedBox(height: 20),
        Expanded(
          child: ListView(children: [
            // Status cards
            Row(children: [
              _telemetryCard('CONNECTION', _isOnline ? 'ONLINE' : 'STANDBY', _isOnline ? Colors.greenAccent : Colors.grey, Icons.wifi_tethering),
              const SizedBox(width: 12),
              _telemetryCard('AGENT NODE', 'NATIVE DART CORE', const Color(0xFFFF4655), Icons.developer_board),
              const SizedBox(width: 12),
              _telemetryCard('CLOUD API', 'RENDER.COM', const Color(0xFF137FEC), Icons.cloud),
            ]),
            const SizedBox(height: 16),
            // Active drive info
            if (_isOnline && _selectedDrive != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0A12),
                  border: Border.all(color: const Color(0xFFFF4655).withOpacity(0.4)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Icon(Icons.usb, color: Color(0xFFFF4655), size: 16),
                    const SizedBox(width: 8),
                    const Text('ACTIVE DRIVE BROADCAST', style: TextStyle(color: Color(0xFFFF4655), fontSize: 11, letterSpacing: 2, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    Container(width: 8, height: 8, decoration: BoxDecoration(color: const Color(0xFFFF4655), borderRadius: BorderRadius.circular(4), boxShadow: const [BoxShadow(color: Color(0xFFFF4655), blurRadius: 8)])),
                  ]),
                  const SizedBox(height: 12),
                  _infoRow('DRIVE PATH', '$_selectedDrive\\'),
                  _infoRow('ACCESSIBLE AT', '$_dashboardUrl/dashboard'),
                  _infoRow('BACKEND SOCKET', _brokerUrl.replaceAll('http://', 'ws://').replaceAll('https://', 'wss://')),
                ]),
              ),
            const SizedBox(height: 16),
            // Network interfaces
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: const Color(0xFF0A0A12), border: Border.all(color: Colors.white10)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.lan, color: Color(0xFF137FEC), size: 16),
                  const SizedBox(width: 8),
                  const Text('NETWORK INTERFACES', style: TextStyle(color: Color(0xFF137FEC), fontSize: 11, letterSpacing: 2, fontWeight: FontWeight.bold)),
                ]),
                const SizedBox(height: 12),
                if (_localIPs.isEmpty)
                  Text('Scanning interfaces...', style: TextStyle(color: Colors.grey[600], fontSize: 11))
                else
                  ..._localIPs.map((ip) {
                    final parts = ip.split(': ');
                    return _infoRow(parts[0].toUpperCase(), parts.length > 1 ? parts[1] : ip);
                  }),
              ]),
            ),
            const SizedBox(height: 16),
            // System stats from agent
            if (t != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: const Color(0xFF0A0A12), border: Border.all(color: Colors.white10)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('AGENT SYSTEM METRICS', style: TextStyle(color: Colors.white, fontSize: 11, letterSpacing: 2, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: _metricBar('CPU', ((t['cpu'] as num?) ?? 0).toDouble(), '%')),
                    const SizedBox(width: 16),
                    Expanded(child: _metricBar('RAM', ((t['ram'] as num?) ?? 0).toDouble(), '%')),
                  ]),
                  const SizedBox(height: 12),
                  _infoRow('UPLOAD SPEED', '${((t['up'] as num?) ?? 0).toStringAsFixed(1)} KB/s'),
                  _infoRow('DOWNLOAD SPEED', '${((t['down'] as num?) ?? 0).toStringAsFixed(1)} KB/s'),
                  _infoRow('STORAGE TOTAL', _formatBytes(((t['storageTotal'] as num?) ?? 0).toInt())),
                  _infoRow('STORAGE FREE', _formatBytes(((t['storageAvailable'] as num?) ?? 0).toInt())),
                ]),
              ),
            ] else
              Center(child: Text('Agent telemetry unavailable — ensure drive is online', style: TextStyle(color: Colors.grey[600], fontSize: 11))),
            const SizedBox(height: 16),
            // Refresh button
            Align(alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: _fetchTelemetry,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('REFRESH', style: TextStyle(letterSpacing: 2, fontSize: 11)),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1a1a2e), shape: const ContinuousRectangleBorder()),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _telemetryCard(String label, String value, Color color, IconData icon) {
    return Expanded(child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFF0A0A12), border: Border.all(color: color.withOpacity(0.3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 8),
        Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 9, letterSpacing: 2)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5, fontFamily: 'Courier')),
      ]),
    ));
  }

  Widget _metricBar(String label, double value, String unit) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(label, style: TextStyle(color: Colors.grey[500], fontSize: 9, letterSpacing: 1.5)),
        const Spacer(),
        Text('${value.toStringAsFixed(1)}$unit', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
      ]),
      const SizedBox(height: 4),
      SizedBox(
        height: 4,
        child: LinearProgressIndicator(
          value: value / 100,
          backgroundColor: Colors.white10,
          color: value > 80 ? const Color(0xFFFF4655) : const Color(0xFF137FEC),
        ),
      ),
    ]);
  }

  // ─── ENCRYPTION PAGE ──────────────────────────────────────────────────────

  Widget _buildEncryptionPage() {
    return Container(
      color: const Color(0xFF0F0F1A),
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _pageHeader('ENCRYPTION PROTOCOL', 'AES-256-GCM tunnel active'),
        const SizedBox(height: 20),
        Expanded(
          child: ListView(children: [
            Row(children: [
              _encryptionCard('TRANSPORT', 'JWT / HS256', Colors.greenAccent, Icons.verified_user, 'All API calls use Bearer token authentication'),
              const SizedBox(width: 12),
              _encryptionCard('TUNNEL', 'WSS + TLS 1.3', const Color(0xFF137FEC), Icons.lock, 'WebSocket tunnel encrypted in transit'),
              const SizedBox(width: 12),
              _encryptionCard('ACCESS KEY', 'GOOGLE OAuth 2.0', const Color(0xFFFF4655), Icons.key, 'Google account is the identity anchor'),
            ]),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: const Color(0xFF0A0A12), border: Border.all(color: Colors.white10)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.shield, color: Color(0xFFFF4655), size: 18),
                  const SizedBox(width: 8),
                  const Text('SECURITY STATUS', style: TextStyle(color: Colors.white, fontSize: 12, letterSpacing: 2, fontWeight: FontWeight.bold)),
                ]),
                const SizedBox(height: 16),
                _securityItem('JWT Token Authentication', true, 'HS256 / 7-day expiry'),
                _securityItem('WebSocket Tunnel', _isOnline, _isOnline ? 'Active on port 8000' : 'Inactive'),
                _securityItem('CORS Policy', true, 'Managed by backend'),
                _securityItem('Drive Path Traversal Guard', true, 'Path resolved & sandboxed'),
                _securityItem('File Type Validation', true, 'All uploads validated'),
              ]),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: const Color(0xFF0A0A12), border: Border.all(color: Colors.yellow.withOpacity(0.2))),
              child: Row(children: [
                Icon(Icons.info_outline, color: Colors.yellow[700], size: 18),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('SECURITY NOTE', style: TextStyle(color: Colors.yellow[700], fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('This software is designed for LAN/local use. For internet-facing deployments, enable HTTPS on port 8000 and use a reverse proxy (Nginx/Caddy) with SSL certificates.',
                      style: TextStyle(color: Colors.grey[500], fontSize: 10, height: 1.6)),
                ])),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _encryptionCard(String label, String protocol, Color color, IconData icon, String desc) {
    return Expanded(child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFF0A0A12), border: Border.all(color: color.withOpacity(0.3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 8),
        Text(label, style: TextStyle(color: Colors.grey[500], fontSize: 9, letterSpacing: 2)),
        const SizedBox(height: 4),
        Text(protocol, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
        const SizedBox(height: 8),
        Text(desc, style: TextStyle(color: Colors.grey[700], fontSize: 9, height: 1.5)),
      ]),
    ));
  }

  Widget _securityItem(String label, bool active, String detail) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        Icon(active ? Icons.check_circle : Icons.cancel, color: active ? Colors.greenAccent : Colors.grey, size: 16),
        const SizedBox(width: 12),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 11, letterSpacing: 1)),
        const Spacer(),
        Text(detail, style: TextStyle(color: Colors.grey[600], fontSize: 10, fontFamily: 'Courier')),
      ]),
    );
  }

  // ─── CONFIG PAGE ─────────────────────────────────────────────────────────

  Widget _buildConfigPage() {
    return Container(
      color: const Color(0xFF0F0F1A),
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _pageHeader('CONFIGURATION', 'System settings and preferences'),
        const SizedBox(height: 20),
        Expanded(child: ListView(children: [
          _configSection('AGENT SETTINGS', [
            _configToggle('Auto-Refresh Drive List', _autoRefresh, (v) async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('auto_refresh', v);
              setState(() => _autoRefresh = v);
            }),
            _configToggle('Start on System Boot', _startOnBoot, (v) async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('start_on_boot', v);
              setState(() => _startOnBoot = v);
            }),
          ]),
          const SizedBox(height: 16),
          _configSection('NETWORK SETTINGS', [
            _configInfoRow('Backend API URL', _brokerUrl),
            _configInfoRow('Local IPC Port', 'N/A (NATIVE DART)'),
            _configInfoRow('WebSocket Path', _brokerUrl.replaceAll('http://', 'ws://').replaceAll('https://', 'wss://')),
            _configInfoRow('Agent ID', 'desktop-node-01'),
          ]),
          const SizedBox(height: 16),
          _configSection('CLOUD ACCESS', [
            _configInfoRow('Auth Method', 'Google OAuth 2.0'),
            _configInfoRow('Token Type', 'JWT / HS256'),
            _configInfoRow('Session Duration', '7 days'),
            _configInfoRow('Active Account', _userEmail.isNotEmpty ? _userEmail : 'Not logged in'),
          ]),
          const SizedBox(height: 16),
          _configSection('ACTIONS', [
            _configAction('Re-sync Config to Agent', Icons.sync, () async {
              await BackendService.syncConfig();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Config synced to Node.js agent'),
                  backgroundColor: Color(0xFFFF4655),
                ));
              }
            }),
            _configAction('Refresh Drive List', Icons.refresh, _loadData),
            _configAction('View System Telemetry', Icons.bar_chart, () => setState(() => _navIndex = 1)),
            _configAction('Logout & Clear Session', Icons.logout, _handleLogout, danger: true),
          ]),
        ])),
      ]),
    );
  }

  Widget _configSection(String title, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(color: const Color(0xFF0A0A12), border: Border.all(color: Colors.white10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white10))),
          child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.bold)),
        ),
        ...children,
      ]),
    );
  }

  Widget _configToggle(String label, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(children: [
        Text(label, style: TextStyle(color: Colors.grey[400], fontSize: 11)),
        const Spacer(),
        Switch(value: value, onChanged: onChanged, activeColor: const Color(0xFFFF4655)),
      ]),
    );
  }

  Widget _configInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        Text(label, style: TextStyle(color: Colors.grey[500], fontSize: 10)),
        const Spacer(),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 10, fontFamily: 'Courier')),
      ]),
    );
  }

  Widget _configAction(String label, IconData icon, VoidCallback onTap, {bool danger = false}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white10))),
        child: Row(children: [
          Icon(icon, color: danger ? const Color(0xFFFF4655) : Colors.grey[500], size: 16),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(color: danger ? const Color(0xFFFF4655) : Colors.grey[300], fontSize: 11)),
          const Spacer(),
          Icon(Icons.chevron_right, color: Colors.grey[700], size: 16),
        ]),
      ),
    );
  }

  // ─── BOTTOM BAR ──────────────────────────────────────────────────────────

  Widget _buildBottomBar() {
    return Container(
      height: 28,
      color: const Color(0xFF0A0A12),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        Text(_isOnline ? 'SECURE_LINK: ACTIVE — $_selectedDrive\\' : 'SECURE_LINK: INACTIVE',
            style: TextStyle(color: _isOnline ? const Color(0xFFFF4655) : Colors.grey[700], fontSize: 9, letterSpacing: 1.0)),
        _div(),
        Text('NODE: NATIVE DART CORE', style: TextStyle(color: Colors.grey[700], fontSize: 9)),
        _div(),
        Text('API: RENDER.COM', style: TextStyle(color: Colors.grey[700], fontSize: 9)),
        const Spacer(),
        Text('${DateTime.now().toUtc().toIso8601String().substring(0, 16)} UTC', style: TextStyle(color: Colors.grey[700], fontSize: 9)),
      ]),
    );
  }

  // ─── HELPERS ─────────────────────────────────────────────────────────────

  Widget _pageHeader(String title, String subtitle) {
    return Row(children: [
      Container(width: 3, height: 24, color: const Color(0xFFFF4655)),
      const SizedBox(width: 12),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 2.0)),
        Text(subtitle, style: TextStyle(color: Colors.grey[600], fontSize: 9, letterSpacing: 1.5)),
      ]),
    ]);
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 10, letterSpacing: 1)),
        const SizedBox(width: 12),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 10, fontFamily: 'Courier')),
      ]),
    );
  }

  Widget _toggleWidget(String label, bool value) {
    return Row(children: [
      Container(width: 10, height: 10, color: const Color(0xFFFF4655)),
      const SizedBox(width: 8),
      Text('$label ', style: TextStyle(color: Colors.grey[600], fontSize: 9, letterSpacing: 1.5)),
      Text(value ? 'ENABLED' : 'DISABLED', style: const TextStyle(color: Colors.white, fontSize: 9, letterSpacing: 1.5, fontWeight: FontWeight.bold)),
    ]);
  }

  Widget _div() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Text('//', style: TextStyle(color: Colors.grey[800], fontSize: 9)),
  );

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suf = ['B', 'KB', 'MB', 'GB', 'TB'];
    int i = 0;
    double val = bytes.toDouble();
    while (val >= 1024 && i < suf.length - 1) { val /= 1024; i++; }
    return '${val.toStringAsFixed(1)} ${suf[i]}';
  }
}
