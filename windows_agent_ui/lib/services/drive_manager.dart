import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'dart:isolate';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image/image.dart' as img;

class DriveManager {
  static final Map<String, IOSink> _activeUploads = {};

  static Future<String> _getRootPath() async {
    final prefs = await SharedPreferences.getInstance();
    final drives = prefs.getStringList('selected_drives') ?? [];
    if (drives.isNotEmpty) {
      return '${drives.first}\\';
    }
    return 'D:\\';
  }

  static Future<String> _getSafePath(String? subPath) async {
    final root = await _getRootPath();
    final targetPath = p.normalize(p.join(root, subPath ?? ''));
    if (!targetPath.startsWith(root)) {
      throw Exception('Access Denied: Path Traversal Attempted');
    }
    return targetPath;
  }

  static Future<dynamic> handleFileRequest(
      String action, Map<String, dynamic> payload, void Function(Map<String, dynamic>) wsSend, String requestId) async {
    switch (action) {
      case 'fs:list':
        return await _listFiles(payload['path'] as String?);
      case 'fs:mkdir':
        return await _createFolder(payload['path'] as String?, payload['name'] as String?);
      case 'fs:delete':
        return await _deleteItem(payload['path'] as String?);
      case 'fs:upload_chunk':
        return await _handleUploadChunk(payload);
      case 'fs:download':
        await _downloadFile(payload['path'] as String?, wsSend, requestId);
        return null;
      case 'fs:thumbnail':
        return await _getThumbnail(payload['path'] as String?, wsSend, requestId);
      case 'sys:stats':
        return await _collectStats();
      default:
        throw Exception('Unknown filesystem action: $action');
    }
  }

  static Future<Map<String, dynamic>> _listFiles(String? dirPath) async {
    final target = await _getSafePath(dirPath);
    final dir = Directory(target);
    if (!await dir.exists()) {
      throw Exception('Path is not a directory');
    }

    final items = <Map<String, dynamic>>[];
    await for (final entity in dir.list(followLinks: false)) {
      try {
        final stat = await entity.stat();
        final isDir = entity is Directory;
        items.add({
          'name': p.basename(entity.path),
          'is_dir': isDir,
          'size': isDir ? 0 : stat.size,
          'modified': stat.modified.millisecondsSinceEpoch,
        });
      } catch (_) {
        // Ignore permission denied
      }
    }
    return {'path': dirPath ?? '', 'items': items};
  }

  static Future<Map<String, dynamic>> _createFolder(String? parentPath, String? folderName) async {
    if (folderName == null || folderName.isEmpty) throw Exception('Folder name required');
    final target = await _getSafePath(p.join(parentPath ?? '', folderName));
    await Directory(target).create(recursive: true);
    return {'success': true, 'path': target};
  }

  static Future<Map<String, dynamic>> _deleteItem(String? itemPath) async {
    if (itemPath == null || itemPath.isEmpty) throw Exception('Path required');
    final target = await _getSafePath(itemPath);
    final stat = await FileStat.stat(target);
    if (stat.type == FileSystemEntityType.directory) {
      await Directory(target).delete(recursive: true);
    } else if (stat.type == FileSystemEntityType.file) {
      await File(target).delete();
    }
    return {'success': true};
  }

  static Future<Map<String, dynamic>> _handleUploadChunk(Map<String, dynamic> payload) async {
    final uploadId = payload['uploadId'] as String;
    final folderPath = payload['path'] as String?;
    final name = payload['name'] as String;
    final chunkBase64 = payload['chunk'] as String;
    final isFirst = payload['isFirst'] as bool;
    final isLast = payload['isLast'] as bool;

    final targetDir = await _getSafePath(folderPath);
    final targetFile = p.join(targetDir, name);
    await _getSafePath(targetFile);

    if (isFirst) {
      if (_activeUploads.containsKey(uploadId)) {
        await _activeUploads[uploadId]!.close();
        _activeUploads.remove(uploadId);
      }
      final file = File(targetFile);
      await file.parent.create(recursive: true);
      _activeUploads[uploadId] = file.openWrite(mode: FileMode.append);
    }

    final sink = _activeUploads[uploadId];
    if (sink == null) throw Exception('Upload stream not found');

    String base64Str = chunkBase64;
    if (base64Str.contains(',')) {
      base64Str = base64Str.split(',').last;
    }

    if (base64Str.isNotEmpty) {
      sink.add(base64Decode(base64Str));
    }

    if (isLast) {
      await sink.close();
      _activeUploads.remove(uploadId);
      return {'success': true, 'finished': true};
    } else {
      return {'success': true, 'finished': false};
    }
  }

  static Future<void> _downloadFile(String? filePath, void Function(Map<String, dynamic>) wsSend, String requestId) async {
    if (filePath == null) throw Exception('File path required');
    final target = await _getSafePath(filePath);
    final file = File(target);
    if (!await file.exists()) throw Exception('Cannot download a directory or missing file');
    
    final size = await file.length();
    wsSend({
      'requestId': requestId,
      'payload': {
        'type': 'start',
        'filename': p.basename(target),
        'size': size,
      }
    });

    final stream = file.openRead();
    List<int> buffer = [];
    const chunkSize = 1024 * 1024; // 1MB chunks
    
    await for (final chunk in stream) {
      buffer.addAll(chunk);
      if (buffer.length >= chunkSize) {
        wsSend({
          'requestId': requestId,
          'payload': {
            'type': 'chunk',
            'data': base64Encode(buffer),
          }
        });
        buffer.clear();
      }
    }
    
    if (buffer.isNotEmpty) {
      wsSend({
        'requestId': requestId,
        'payload': {
          'type': 'chunk',
          'data': base64Encode(buffer),
        }
      });
    }

    wsSend({
      'requestId': requestId,
      'payload': {
        'type': 'end',
      }
    });
  }

  static Future<dynamic> _getThumbnail(String? filePath, void Function(Map<String, dynamic>) wsSend, String requestId) async {
    if (filePath == null) throw Exception('File path required');
    final target = await _getSafePath(filePath);
    final file = File(target);
    if (!await file.exists()) throw Exception('Cannot thumbnail a directory');

    try {
      final bytes = await file.readAsBytes();
      final base64String = await Isolate.run(() {
        final image = img.decodeImage(bytes);
        if (image == null) throw Exception('Could not decode image');
        final resized = img.copyResize(image, width: 200);
        final jpg = img.encodeJpg(resized, quality: 70);
        return base64Encode(jpg);
      });

      return {
        'isFile': true,
        'filename': 'thumb_${p.basename(target)}.jpg',
        'payload': base64String,
      };
    } catch (e) {
      print('Thumbnail error: $e.');
      await _downloadFile(filePath, wsSend, requestId);
      return null;
    }
  }

  static Future<Map<String, dynamic>> _collectStats() async {
    final root = await _getRootPath();
    int total = 0;
    int free = 0;
    try {
      final queryDrive = root.endsWith('\\') ? root.substring(0, root.length - 1) : root;
      final result = await Process.run('powershell', [
        '-Command',
        'Get-CimInstance Win32_LogicalDisk | Where-Object DeviceID -eq "$queryDrive" | Select-Object Size, FreeSpace | ConvertTo-Json'
      ]);
      if (result.exitCode == 0) {
        final dat = jsonDecode(result.stdout);
        total = int.tryParse(dat['Size']?.toString() ?? '0') ?? 0;
        free = int.tryParse(dat['FreeSpace']?.toString() ?? '0') ?? 0;
      }
    } catch (_) {}

    return {
      'cpu': 5.0,
      'ram': 25.0,
      'up': 0.0,
      'down': 0.0,
      'storageTotal': total,
      'storageAvailable': free,
    };
  }
}
