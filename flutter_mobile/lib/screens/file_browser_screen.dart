import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';

class FileBrowserScreen extends StatefulWidget {
  const FileBrowserScreen({super.key});

  @override
  State<FileBrowserScreen> createState() => _FileBrowserScreenState();
}

class _FileBrowserScreenState extends State<FileBrowserScreen> {
  final String _brokerUrl = 'https://drivenet-broker.onrender.com';
  String _currentPath = '\\';
  List<Map<String, dynamic>> _items = [];
  bool _isLoading = false;
  String _error = '';
  Map<String, double> _uploadProgress = {};

  @override
  void initState() {
    super.initState();
    _fetchFiles();
  }

  Future<void> _fetchFiles() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('drivenet_jwt');

      if (token == null) {
        throw Exception('Not authenticated');
      }

      final url = Uri.parse('$_brokerUrl/api/fs/list?path=${Uri.encodeComponent(_currentPath)}');
      final response = await http.get(url, headers: {
        'Authorization': 'Bearer $token',
      });

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _items = List<Map<String, dynamic>>.from(data['items'] ?? []);
        });
      } else {
        throw Exception(jsonDecode(response.body)['error'] ?? 'Failed to fetch files');
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        // Fallback to offline message if the proxy fails
        if (e.toString().contains('OFFLINE') || e.toString().contains('disconnected')) {
          _error = 'Agent is offline. Ensure Windows Agent is running and connected.';
        }
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _navigateTo(String newPath) {
    setState(() {
      _currentPath = newPath;
    });
    _fetchFiles();
  }

  void _navigateUp() {
    if (_currentPath == '\\' || _currentPath.isEmpty) return;
    
    List<String> parts = _currentPath.split('\\');
    parts.removeLast(); // Remove empty string after trailing slash if exists
    if (parts.isNotEmpty && parts.last.isEmpty) parts.removeLast();
    parts.removeLast(); // Remove current folder

    if (parts.isEmpty || (parts.length == 1 && parts[0].endsWith(':'))) {
      _navigateTo('\\');
    } else {
      _navigateTo('${parts.join('\\')}\\');
    }
  }

  Future<void> _uploadFile() async {
    try {
      final result = await FilePicker.platform.pickFiles();
      if (result == null || result.files.isEmpty) return;

      final file = File(result.files.single.path!);
      final fileName = result.files.single.name;
      final fileSize = await file.length();

      setState(() {
        _uploadProgress[fileName] = 0.0;
      });

      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('drivenet_jwt');

      final uploadId = DateTime.now().millisecondsSinceEpoch.toString();
      const int chunkSize = 1 * 1024 * 1024; // 1MB chunks
      final RandomAccessFile raf = await file.open(mode: FileMode.read);

      for (int i = 0; i < fileSize; i += chunkSize) {
        final int bytesToRead = (i + chunkSize > fileSize) ? fileSize - i : chunkSize;
        final List<int> chunk = await raf.read(bytesToRead);
        
        final base64Chunk = base64Encode(chunk);
        final isFirst = i == 0;
        final isLast = (i + bytesToRead) >= fileSize;

        final response = await http.post(
          Uri.parse('$_brokerUrl/api/fs/upload_chunk'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'uploadId': uploadId,
            'path': _currentPath,
            'name': fileName,
            'chunk': base64Chunk,
            'isFirst': isFirst,
            'isLast': isLast,
          }),
        );

        if (response.statusCode != 200) {
          throw Exception('Upload failed');
        }

        setState(() {
          _uploadProgress[fileName] = (i + bytesToRead) / fileSize;
        });
      }

      await raf.close();

      setState(() {
        _uploadProgress.remove(fileName);
      });

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Uploaded: $fileName')));
      _fetchFiles();

    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload error: $e')));
    }
  }

  Future<void> _downloadAndOpenFile(Map<String, dynamic> item) async {
    final name = item['name'] as String;
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Downloading $name...')));
    setState(() => _isLoading = true);
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('drivenet_jwt');
      String relPath = _currentPath == '\\' ? name : '$_currentPath\\$name';
      
      final url = Uri.parse('$_brokerUrl/api/fs/download?path=${Uri.encodeComponent(relPath)}');
      final response = await http.get(url, headers: {'Authorization': 'Bearer $token'});

      if (response.statusCode == 200) {
        final dir = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/$name');
        await file.writeAsBytes(response.bodyBytes);
        
        // Open file natively
        final result = await OpenFilex.open(file.path);
        if (result.type != ResultType.done && mounted) {
           ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open file: ${result.message}')));
        }
      } else {
        throw Exception('Server rejected download request.');
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Download error: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _shareFile(Map<String, dynamic> item) async {
    final name = item['name'] as String;
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('drivenet_jwt');
      String relPath = _currentPath == '\\' ? name : '$_currentPath\\$name';
      
      final downloadUrl = '$_brokerUrl/api/fs/download?path=${Uri.encodeComponent(relPath)}&token=$token';
      
      await Share.share('Check out this file from DriveNet:\n\n$downloadUrl');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Share error: $e')));
    }
  }

  Future<void> _deleteItem(Map<String, dynamic> item) async {
      final name = item['name'] as String;
      try {
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString('drivenet_jwt');
        String relPath = _currentPath == '\\' ? name : '$_currentPath\\$name';
        
        final url = Uri.parse('$_brokerUrl/api/fs/delete?path=${Uri.encodeComponent(relPath)}');
        final response = await http.delete(url, headers: {'Authorization': 'Bearer $token'});
        
        if (response.statusCode == 200) {
            _fetchFiles();
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Deleted $name')));
        } else {
            throw Exception('Delete failed');
        }
      } catch (e) {
         if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete error: $e')));
      }
  }

  void _showFileOptions(Map<String, dynamic> item) {
    if (item['is_dir'] == true) return; // For now, only interact with files

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF14141E),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.download, color: Colors.white),
                title: const Text('Download & Open', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _downloadAndOpenFile(item);
                },
              ),
              ListTile(
                leading: const Icon(Icons.share, color: Colors.white),
                title: const Text('Share Link', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _shareFile(item);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.redAccent),
                title: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
                onTap: () {
                  Navigator.pop(context);
                  _deleteItem(item);
                },
              ),
            ],
          ),
        );
      }
    );
  }

  Widget _buildBreadcrumbs() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF14141E),
        border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05))),
      ),
      child: Row(
        children: [
          if (_currentPath != '\\' && _currentPath.isNotEmpty) ...[
            GestureDetector(
              onTap: _navigateUp,
              child: const Icon(Icons.arrow_upward, color: Color(0xFFFF4655), size: 18),
            ),
            const SizedBox(width: 12),
          ],
          const Icon(Icons.storage, color: Colors.grey, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _currentPath == '\\' ? 'Root' : _currentPath,
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.grey, size: 18),
            onPressed: _fetchFiles,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          )
        ],
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    int i = 0;
    double val = bytes.toDouble();
    while (val >= 1024 && i < suffixes.length - 1) {
      val /= 1024;
      i++;
    }
    return '${val.toStringAsFixed(1)} ${suffixes[i]}';
  }

  String _formatDate(dynamic timestamp) {
    if (timestamp == null) return '';
    try {
      int ms;
      if (timestamp is int) {
        ms = timestamp;
      } else if (timestamp is String) {
        ms = int.tryParse(timestamp) ?? 0;
      } else {
        return '';
      }
      final date = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  Widget _buildFileItem(Map<String, dynamic> item) {
    final bool isDir = item['is_dir'] == true;
    final String name = item['name'] ?? 'Unknown';
    final int size = item['size'] ?? 0;
    final String date = _formatDate(item['modified']);
    
    IconData iconData = isDir ? Icons.folder : Icons.insert_drive_file;
    Color iconColor = isDir ? const Color(0xFF137FEC) : Colors.grey;

    // Basic icons for common types
    if (!isDir) {
      final ext = name.split('.').last.toLowerCase();
      if (['png', 'jpg', 'jpeg', 'gif'].contains(ext)) { iconData = Icons.image; iconColor = Colors.purpleAccent; }
      else if (['mp4', 'mov', 'avi'].contains(ext)) { iconData = Icons.video_file; iconColor = Colors.orangeAccent; }
      else if (['pdf'].contains(ext)) { iconData = Icons.picture_as_pdf; iconColor = Colors.redAccent; }
      else if (['txt', 'md', 'dart', 'js', 'json'].contains(ext)) { iconData = Icons.description; iconColor = Colors.greenAccent; }
    }

    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: iconColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(iconData, color: iconColor),
      ),
      title: Text(
        name,
        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        isDir ? 'Folder • $date' : '${_formatSize(size)} • $date',
        style: TextStyle(color: Colors.grey[500], fontSize: 12),
      ),
      onTap: isDir ? () {
        // Ensure path formatting handles Windows backslashes correctly
        String newPath = _currentPath;
        if (!newPath.endsWith('\\')) newPath += '\\';
        newPath += '$name\\';
        _navigateTo(newPath);
      } : () {
        _showFileOptions(item);
      },
      trailing: IconButton(
        icon: const Icon(Icons.more_vert, color: Colors.grey, size: 20),
        onPressed: () => _showFileOptions(item),
      ),
    );
  }

  Widget _buildUploadProgress() {
    if (_uploadProgress.isEmpty) return const SizedBox.shrink();
    return Column(
      children: _uploadProgress.entries.map((e) {
        return Container(
          color: const Color(0xFF14141E),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Uploading: ${e.key}', style: const TextStyle(color: Colors.white, fontSize: 12)),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(value: e.value, color: const Color(0xFFFF4655), backgroundColor: Colors.grey[800]),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Text('${(e.value * 100).toStringAsFixed(0)}%', style: const TextStyle(color: Colors.white, fontSize: 12)),
            ],
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent, // inherited from dashboard
      body: Column(
        children: [
          _buildBreadcrumbs(),
          _buildUploadProgress(),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF4655)))
              : _error.isNotEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.cloud_off, color: Color(0xFFFF4655), size: 48),
                            const SizedBox(height: 16),
                            Text(
                              _error,
                              style: const TextStyle(color: Colors.white70),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _fetchFiles,
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF4655)),
                              child: const Text('Retry', style: TextStyle(color: Colors.white)),
                            )
                          ],
                        ),
                      ),
                    )
                  : _items.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.folder_open, color: Colors.grey[800], size: 64),
                              const SizedBox(height: 16),
                              Text('Folder is empty', style: TextStyle(color: Colors.grey[500])),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          color: const Color(0xFFFF4655),
                          backgroundColor: const Color(0xFF14141E),
                          onRefresh: _fetchFiles,
                          child: ListView.separated(
                            itemCount: _items.length,
                            separatorBuilder: (context, index) => Divider(color: Colors.white.withOpacity(0.05), height: 1),
                            itemBuilder: (context, index) {
                              // Sort folders first
                              final sortedItems = List<Map<String, dynamic>>.from(_items)
                                ..sort((a, b) {
                                  if (a['is_dir'] == true && b['is_dir'] != true) return -1;
                                  if (a['is_dir'] != true && b['is_dir'] == true) return 1;
                                  return (a['name'] ?? '').compareTo(b['name'] ?? '');
                                });
                                
                              return _buildFileItem(sortedItems[index]);
                            },
                          ),
                        ),
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton(
      onPressed: _uploadFile,
      backgroundColor: const Color(0xFFFF4655),
      child: const Icon(Icons.upload_file, color: Colors.white),
    ),
    );
  }
}
