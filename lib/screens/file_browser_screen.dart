import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/file_browser_service.dart';
import '../services/thumbnail_service.dart';
import '../widgets/video_file_item.dart';

class FileBrowserScreen extends StatefulWidget {
  const FileBrowserScreen({super.key});

  @override
  State<FileBrowserScreen> createState() => _FileBrowserScreenState();
}

class _FileBrowserScreenState extends State<FileBrowserScreen> {
  List<VideoFile> _videoFiles = [];
  List<VideoFile> _filteredVideoFiles = [];
  bool _isLoading = false;
  bool _hasPermission = false;
  String _currentPath = '';
  String _searchTerm = '';
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    ThumbnailService.initialize();
    _checkPermissionAndLoadFiles();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _checkPermissionAndLoadFiles() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final hasPermission = await FileBrowserService.requestStoragePermission();
      if (!mounted) return;
      
      if (hasPermission) {
        setState(() {
          _hasPermission = true;
        });
        await _loadVideoFiles();
      } else {
        setState(() {
          _hasPermission = false;
          _isLoading = false;
        });
        _showPermissionDeniedDialog();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      _showErrorSnackBar('Error checking permissions: $e');
    }
  }

  Future<void> _loadVideoFiles() async {
    try {
      final storageDirectories = await FileBrowserService.getStorageDirectories();
      if (!mounted) return;
      
      if (storageDirectories.isNotEmpty) {
        setState(() {
          _currentPath = storageDirectories.first;
        });
        await _loadVideosFromPath(_currentPath);
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      _showErrorSnackBar('Error loading storage directories: $e');
    }
  }

  Future<void> _loadVideosFromPath(String path) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final videoFiles = await FileBrowserService.getVideoFilesInDirectory(path);
      if (!mounted) return;
      setState(() {
        _videoFiles = videoFiles;
        _filteredVideoFiles = videoFiles;
        _isLoading = false;
      });

    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      _showErrorSnackBar('Error loading videos: $e');
    }
  }

  void _onSearchChanged() {
    final searchTerm = _searchController.text.toLowerCase();
    setState(() {
      _searchTerm = searchTerm;
      if (searchTerm.isEmpty) {
        _filteredVideoFiles = _videoFiles;
      } else {
        _filteredVideoFiles = _videoFiles.where((video) =>
          video.name.toLowerCase().contains(searchTerm)
        ).toList();
      }
    });
  }

  Future<void> _refreshFiles() async {
    await _loadVideosFromPath(_currentPath);
  }

  void _showPermissionDeniedDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Storage Permission Required'),
          content: const Text(
            'This app needs storage permission to browse and play video files from your device. '
            'Please grant the permission in settings.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await openAppSettings();
              },
              child: const Text('Open Settings'),
            ),
          ],
        );
      },
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _onVideoSelected(VideoFile videoFile) {
    Navigator.of(context).pop(videoFile.path);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        elevation: 0,
        title: const Text(
          'Video Browser',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        iconTheme: IconThemeData(
          color: isDark ? Colors.white : Colors.black,
        ),
        actions: [
          IconButton(
            onPressed: _refreshFiles,
            icon: Icon(
              Icons.refresh,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (!_hasPermission) {
      return _buildPermissionRequest();
    }

    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.red),
      );
    }

    return Column(
      children: [
        _buildSearchBar(),
        _buildPathIndicator(),
        _buildVideoList(),
      ],
    );
  }

  Widget _buildPermissionRequest() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.folder_off,
              size: 80,
              color: Colors.grey,
            ),
            const SizedBox(height: 24),
            Text(
              'Storage Permission Required',
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              'Allow access to your device storage to browse and play video files.',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _checkPermissionAndLoadFiles,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Grant Permission'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: _searchController,
        style: TextStyle(color: isDark ? Colors.white : Colors.black),
        decoration: InputDecoration(
          hintText: 'Search videos...',
          hintStyle: TextStyle(color: Colors.grey[400]),
          prefixIcon: const Icon(Icons.search, color: Colors.grey),
          suffixIcon: _searchTerm.isNotEmpty
              ? IconButton(
                  onPressed: () {
                    _searchController.clear();
                  },
                  icon: const Icon(Icons.clear, color: Colors.grey),
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }

  Widget _buildPathIndicator() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.grey[200],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.folder, color: Colors.grey, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _currentPath.isNotEmpty ? _currentPath : 'No directory selected',
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 12,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoList() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (_filteredVideoFiles.isEmpty) {
      return Expanded(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _searchTerm.isNotEmpty ? Icons.search_off : Icons.video_library_outlined,
                size: 80,
                color: Colors.grey,
              ),
              const SizedBox(height: 16),
              Text(
                _searchTerm.isNotEmpty
                    ? 'No videos found for "$_searchTerm"'
                    : 'No video files found',
                style: TextStyle(
                  color: isDark ? Colors.grey : Colors.grey[700],
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              if (_searchTerm.isEmpty)
                const Text(
                  'Try a different directory or check storage permissions',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 14,
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return Expanded(
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is UserScrollNotification) {
            ThumbnailService.setPausedDebounced(
              notification.direction != ScrollDirection.idle,
            );
          }
          return false;
        },
        child: ListView.builder(
          controller: _scrollController,
          // Keeps compatibility with Flutter versions before ScrollCacheExtent.
          // ignore: deprecated_member_use
          cacheExtent: 600,
          padding: const EdgeInsets.all(16),
          itemCount: _filteredVideoFiles.length,
          itemBuilder: (context, index) {
            final videoFile = _filteredVideoFiles[index];
            return VideoFileItem(
              key: ValueKey(videoFile.path),
              videoFile: videoFile,
              onTap: () => _onVideoSelected(videoFile),
            );
          },
        ),
      ),
    );
  }
}
