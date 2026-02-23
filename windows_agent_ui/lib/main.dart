import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:system_tray/system_tray.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/login_screen.dart';
import 'screens/drive_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Detect if launched at boot (--minimized flag set by registry startup entry)
  final args = Platform.executableArguments;
  final startMinimized = args.contains('--minimized');

  // Initialize window manager FIRST
  await windowManager.ensureInitialized();

  const WindowOptions windowOptions = WindowOptions(
    size: Size(940, 620),
    minimumSize: Size(820, 540),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
    title: 'DriveNet Agent',
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setPreventClose(true);
    if (startMinimized) {
      // Boot start: hide window, only show tray icon
      await windowManager.hide();
    } else {
      await windowManager.show();
      await windowManager.focus();
    }
  });

  runApp(const DriveSyncApp());
}

/// Registers / removes the app in the Windows startup registry key.
/// HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run
class StartupService {
  static Future<void> enable() async {
    final exe = Platform.resolvedExecutable;
    // --minimized = start silently in tray on boot
    final cmd = '"$exe" --minimized';
    await Process.run('powershell', [
      '-NoProfile', '-NonInteractive', '-Command',
      'Set-ItemProperty -Path "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Run" -Name "DriveNetAgent" -Value \'$cmd\'',
    ]);
  }

  static Future<void> disable() async {
    await Process.run('powershell', [
      '-NoProfile', '-NonInteractive', '-Command',
      'Remove-ItemProperty -Path "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Run" -Name "DriveNetAgent" -ErrorAction SilentlyContinue',
    ]);
  }

  static Future<bool> isEnabled() async {
    final result = await Process.run('powershell', [
      '-NoProfile', '-NonInteractive', '-Command',
      '(Get-ItemProperty -Path "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Run" -Name "DriveNetAgent" -ErrorAction SilentlyContinue)."DriveNetAgent" -ne \$null',
    ]);
    return result.stdout.toString().trim() == 'True';
  }
}

class DriveSyncApp extends StatelessWidget {
  const DriveSyncApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Drive Net Client',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0D0D14),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFF4655),
          secondary: Color(0xFF137FEC),
        ),
      ),
      home: const TrayManager(),
      debugShowCheckedModeBanner: false,
    );
  }
}

/// Manages the system tray icon and intercepts window close to minimize-to-tray.
class TrayManager extends StatefulWidget {
  const TrayManager({super.key});

  @override
  State<TrayManager> createState() => _TrayManagerState();
}

class _TrayManagerState extends State<TrayManager> with WindowListener {
  final SystemTray _systemTray = SystemTray();
  bool _trayInitialized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _initTray();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _initTray() async {
    try {
      // Use .ico file for Windows system tray
      await _systemTray.initSystemTray(
        title: 'Drive Net Client',
        iconPath: 'assets/icon.ico',
        toolTip: 'Drive Net Client — Click to open',
      );

      final menu = Menu();
      await menu.buildFrom([
        MenuItemLabel(label: 'Drive Net Client', enabled: false),
        MenuSeparator(),
        MenuItemLabel(label: 'Open', onClicked: (_) => _showWindow()),
        MenuItemLabel(label: 'Exit', onClicked: (_) => _exitApp()),
      ]);
      await _systemTray.setContextMenu(menu);

      _systemTray.registerSystemTrayEventHandler((eventName) {
        if (eventName == kSystemTrayEventClick || eventName == kSystemTrayEventRightClick) {
          _showWindow();
        }
      });

      _trayInitialized = true;
    } catch (e) {
      debugPrint('Tray init skipped: $e');
      // App works fine without tray
    }
  }

  Future<void> _showWindow() async {
    if (!await windowManager.isVisible()) {
      await windowManager.show();
    }
    await windowManager.focus();
    await windowManager.restore();
  }

  Future<void> _exitApp() async {
    await windowManager.setPreventClose(false);
    await windowManager.close();
  }

  /// Called when user presses X — hide to tray instead of closing
  @override
  void onWindowClose() async {
    await windowManager.hide();
  }

  /// Called when user minimizes — allow it to stay minimized (don't hide)
  @override
  void onWindowMinimize() {
    // intentionally do nothing — let it minimize normally on taskbar
  }

  @override
  Widget build(BuildContext context) {
    return const AppRouter();
  }
}

/// Checks for existing session on startup and routes accordingly.
class AppRouter extends StatefulWidget {
  const AppRouter({super.key});

  @override
  State<AppRouter> createState() => _AppRouterState();
}

class _AppRouterState extends State<AppRouter> {
  bool _loading = true;
  bool _isLoggedIn = false;

  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('drivenet_jwt');
    final email = prefs.getString('drivenet_user');

    bool valid = false;
    if (token != null && token.isNotEmpty && email != null) {
      // Decode JWT and check expiry
      try {
        final parts = token.split('.');
        if (parts.length == 3) {
          // Base64 decode the payload
          String payload = parts[1];
          // Pad base64 to correct length
          while (payload.length % 4 != 0) payload += '=';
          final decoded = String.fromCharCodes(base64Decode(payload));
          final data = jsonDecode(decoded) as Map<String, dynamic>;
          final exp = data['exp'] as int?;
          if (exp != null) {
            final expiry = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
            valid = DateTime.now().isBefore(expiry);
          } else {
            valid = true; // No exp claim — assume valid
          }
        }
      } catch (_) {
        valid = false; // Malformed token
      }
    }

    if (!valid) {
      // Clear stale/expired session
      await prefs.remove('drivenet_jwt');
      await prefs.remove('drivenet_user');
      await prefs.setBool('is_online', false);
    }

    setState(() {
      _isLoggedIn = valid;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0D0D14),
        body: Center(child: CircularProgressIndicator(color: Color(0xFFFF4655))),
      );
    }
    return _isLoggedIn ? const DriveScreen() : const LoginScreen();
  }
}
