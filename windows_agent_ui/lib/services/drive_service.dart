import 'dart:io';

class DriveService {
  /// Gets all logical drives and their details via PowerShell
  static Future<List<String>> getWindowsDrives() async {
    if (!Platform.isWindows) return [];

    try {
      final result = await Process.run('powershell', [
        '-Command',
        'Get-CimInstance Win32_LogicalDisk | Select-Object DeviceID, DriveType | Format-Table -HideTableHeaders'
      ]);

      if (result.exitCode == 0) {
        final lines = (result.stdout as String).split(RegExp(r'\r?\n'));
        final drives = <String>[];
        for (var line in lines) {
          line = line.trim();
          if (line.isNotEmpty && line.contains(':')) {
            final parts = line.split(RegExp(r'\s+'));
            if (parts.length >= 2) {
              final name = parts[0];
              final driveType = parts[1];
              if (driveType == '2' || driveType == '3') {
                drives.add(name);
              }
            }
          }
        }
        return drives;
      }
    } catch (e) {
      print('Error fetching drives: $e');
    }
    return [];
  }

  /// Gets detailed drive info including label, used space, total space, type
  static Future<List<Map<String, dynamic>>> getDriveDetails(List<String> driveNames) async {
    if (!Platform.isWindows || driveNames.isEmpty) return [];

    try {
      final result = await Process.run('powershell', [
        '-Command',
        r'''Get-CimInstance Win32_LogicalDisk | Select-Object DeviceID, DriveType, VolumeName, FreeSpace, Size | Format-List'''
      ]);

      if (result.exitCode == 0) {
        final output = result.stdout as String;
        final blocks = output.split(RegExp(r'\r?\n\r?\n'));
        final drives = <Map<String, dynamic>>[];

        for (final block in blocks) {
          if (block.trim().isEmpty) continue;
          final lines = block.split(RegExp(r'\r?\n'));
          final data = <String, String>{};
          for (final line in lines) {
            final parts = line.split(':');
            if (parts.length >= 2) {
              data[parts[0].trim()] = parts.sublist(1).join(':').trim();
            }
          }

          final deviceId = data['DeviceID'] ?? '';
          final driveType = data['DriveType'] ?? '';
          final volumeName = data['VolumeName'] ?? '';
          final freeSpace = double.tryParse(data['FreeSpace'] ?? '0') ?? 0;
          final size = double.tryParse(data['Size'] ?? '0') ?? 0;

          if (deviceId.isEmpty) continue;
          if (driveType != '2' && driveType != '3') continue;

          final used = size - freeSpace;
          final usedGb = used / (1024 * 1024 * 1024);
          final totalGb = size / (1024 * 1024 * 1024);

          final label = volumeName.isNotEmpty ? volumeName : (driveType == '2' ? 'REMOVABLE_USB' : 'LOCAL_DISK');

          drives.add({
            'name': deviceId,
            'label': label,
            'usedGb': usedGb,
            'totalGb': totalGb,
            'type': driveType,
          });
        }

        return drives;
      }
    } catch (e) {
      print('Error getting drive details: $e');
    }

    // Fallback: return drives without detail
    return driveNames.map((d) => {
      'name': d,
      'label': 'LOCAL_DISK',
      'usedGb': 0.0,
      'totalGb': 0.0,
      'type': '3',
    }).toList();
  }
}
