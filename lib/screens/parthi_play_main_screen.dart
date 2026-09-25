import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:next_gen_video_player/services/vault_service.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/share_service.dart';

import 'dart:io';

import '../widgets/parthi_play_video_player.dart';
import '../services/memory_monitor_service.dart';
import '../services/video_scanner_service.dart';
import '../services/playlist_service.dart';
import '../services/file_browser_service.dart';
import '../services/theme_service.dart';
import '../services/thumbnail_service.dart';
import '../services/stream_sources_service.dart';
import '../core/video_player_controller.dart';
import 'settings_screen.dart';

class ParthiPlayMainScreen extends ConsumerStatefulWidget {
  const ParthiPlayMainScreen({super.key});

  @override
  ConsumerState<ParthiPlayMainScreen> createState() =>
      _ParthiPlayMainScreenState();
}

class _ParthiPlayMainScreenState extends ConsumerState<ParthiPlayMainScreen>
    with TickerProviderStateMixin {
  String? _videoUrl;
  String? _videoPath;
  final TextEditingController _urlController = TextEditingController();
  StreamSubscription<List<SharedMediaFile>>? _shareMediaSub;
  late TabController _tabController;
  List<VideoFile> _localVideos = [];
  List<VideoFile> _filteredVideos = [];
  String? _currentFilter;
  String? _currentFolderName;
  final Map<String, List<VideoFile>> _foldersMap = {};
  final List<String> _folderNames = [];
  List<VideoFile> _streamVideos = [];
  bool _isLoadingStreams = false;
  Set<String> _customStreamUrls = {};
  static const String _recentUrlsKey = 'recent_stream_urls';
  static const int _maxRecentUrls = 8;
  DateTime? _lastScanSnackAt;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    MemoryMonitorService.startMonitoring();
    ThumbnailService.initialize();
    _initShareIntentHandling();
    _loadStreams();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _initializeVideoScanner();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _urlController.dispose();
    _shareMediaSub?.cancel();
    MemoryMonitorService.stopMonitoring();
    super.dispose();
  }

  Future<void> _initializeVideoScanner() async {
    try {
      await Future.delayed(const Duration(milliseconds: 600));
      final cachedVideos = await VideoScannerService.getCachedVideos();
      if (mounted && cachedVideos.isNotEmpty) {
        setState(() {
          _localVideos = cachedVideos;
          _filteredVideos = cachedVideos;
        });
      }
      await PlaylistService.initialize();
      if (!mounted) return;
      Future.delayed(const Duration(milliseconds: 2000), () {
        if (mounted) {
          _scanVideos(background: true);
        }
      });
    } catch (e) {
      debugPrint('Error initializing video scanner: $e');
    }
  }

  void _initShareIntentHandling() {
    _shareMediaSub = ReceiveSharingIntent.instance.getMediaStream().listen(
      (files) {
        _handleSharedMedia(files);
      },
      onError: (e) {
        debugPrint('Share intent stream error: $e');
      },
    );

    ReceiveSharingIntent.instance
        .getInitialMedia()
        .then((files) {
          if (files.isNotEmpty) {
            _handleSharedMedia(files);
          }
          ReceiveSharingIntent.instance.reset();
        })
        .catchError((e) {
          debugPrint('Initial share intent error: $e');
        });
  }

  void _handleSharedMedia(List<SharedMediaFile> files) {
    if (files.isEmpty) return;
    final textFile = files.firstWhere(
      (f) => f.type == SharedMediaType.text,
      orElse: () => files.first,
    );
    _handleSharedText(textFile.path);
  }

  void _handleSharedText(String text) {
    if (!mounted) return;
    final url = _extractFirstUrl(text);
    if (url == null) return;
    setState(() {
      _videoUrl = url;
      _videoPath = null;
    });
    ReceiveSharingIntent.instance.reset();
  }

  String? _extractFirstUrl(String text) {
    final match = RegExp(r'(https?://\S+)').firstMatch(text);
    if (match == null) return null;
    final url = match.group(0)?.trim();
    if (url == null || url.isEmpty) return null;
    return url;
  }

  Future<void> _loadStreams({bool showError = false}) async {
    if (mounted) {
      setState(() {
        _isLoadingStreams = true;
      });
    }
    try {
      final streams = await StreamSourcesService.loadAllStreams();
      final customStreams = await StreamSourcesService.loadCustomStreams();
      if (!mounted) return;
      setState(() {
        _streamVideos = streams
            .map(
              (s) => VideoFile(
                path: s.url,
                name: s.title,
                size: 0,
                lastModified: DateTime.now(),
                type: MediaType.streaming,
              ),
            )
            .toList();
        _customStreamUrls = customStreams.map((s) => s.url.trim()).toSet();
        if (_currentFilter == 'streaming') {
          _filteredVideos = _streamVideos;
        }
        _isLoadingStreams = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingStreams = false;
      });
      if (showError) {
        _showErrorSnackBar('Failed to load streams');
      }
    }
  }

  Future<void> _scanVideos({bool background = false}) async {
    try {
      final videos = await VideoScannerService.scanAllVideos(useCache: false);
      if (!mounted) return;
      setState(() {
        _localVideos = videos;
        _organizeVideosByFolders();
        _applyFilter();
      });

      if (!background) {
        if (videos.isNotEmpty) {
          final now = DateTime.now();
          if (_lastScanSnackAt == null ||
              now.difference(_lastScanSnackAt!) > const Duration(seconds: 8)) {
            _showSuccessSnackBar('Found ${videos.length} files');
            _lastScanSnackAt = now;
          }
        } else {
          _showErrorSnackBar('No files found.');
        }
      }
    } catch (e) {
      if (mounted) {
        if (!background) {
          _showErrorSnackBar('Failed to scan files: ${e.toString()}');
        }
      }
    }
  }

  void _playVideo(String videoPath) {
    // Set current folder in video controller for navigation
    if (_currentFolderName != null &&
        _foldersMap.containsKey(_currentFolderName)) {
      final videoController = ref.read(videoPlayerControllerProvider.notifier);
      videoController.setCurrentFolder(
        _foldersMap[_currentFolderName]!,
        _currentFolderName!,
      );
    }

    setState(() {
      _videoPath = videoPath;
      _videoUrl = null;
    });
  }

  void _playStream(VideoFile video) {
    setState(() {
      _videoUrl = video.path;
      _videoPath = null;
    });
  }

  void _playVideoItem(VideoFile video) {
    if (video.type == MediaType.streaming) {
      _playStream(video);
    } else {
      _playVideo(video.path);
    }
  }

  void _organizeVideosByFolders() {
    _foldersMap.clear();
    _folderNames.clear();

    for (final video in _localVideos) {
      final folderPath = video.path.contains(Platform.pathSeparator)
          ? video.path.substring(
              0,
              video.path.lastIndexOf(Platform.pathSeparator),
            )
          : 'Root';
      final folderName = folderPath.contains(Platform.pathSeparator)
          ? folderPath.substring(
              folderPath.lastIndexOf(Platform.pathSeparator) + 1,
            )
          : folderPath;

      if (!_foldersMap.containsKey(folderName)) {
        _foldersMap[folderName] = [];
        _folderNames.add(folderName);
      }
      _foldersMap[folderName]!.add(video);
    }

    _folderNames.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  void _onVideoEnded() {
    setState(() {
      _videoUrl = null;
      _videoPath = null;
    });
    _showSuccessSnackBar('Video completed');
  }

  Future<void> _performExit() async {
    if (!mounted) return;
    try {
      await SystemNavigator.pop();
    } catch (e) {
      debugPrint('Exit error: $e');
      try {
        if (!mounted) return;
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      } catch (e2) {
        debugPrint('Navigator exit fallback failed: $e2');
      }
    }
  }

  Future<void> _handleExitRequest() async {
    if (_videoPath != null || _videoUrl != null) {
      setState(() {
        _videoPath = null;
        _videoUrl = null;
      });
      return;
    }

    final shouldExit =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Exit App'),
            content: const Text('Do you want to close the app?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('No'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Yes'),
              ),
            ],
          ),
        ) ??
        false;

    if (!mounted) return;
    if (shouldExit) {
      await _performExit();
    }
  }

  /// Recomputes [_filteredVideos]. Callers are expected to wrap this in
  /// `setState`.
  void _applyFilter() {
    if (_currentFilter == 'folders') {
      _filteredVideos = [];
    } else if (_currentFilter == 'streaming') {
      _filteredVideos = _streamVideos;
    } else if (_currentFolderName != null) {
      _filteredVideos = _foldersMap[_currentFolderName] ?? [];
    } else {
      _filteredVideos = _localVideos
          .where((v) => v.type == MediaType.video)
          .toList();
    }
  }

  Future<void> _onChipTap(String label) async {
    unawaited(HapticFeedback.lightImpact());
    if (label == 'Privacy') {
      final isSetup = await VaultService.isVaultSetup();
      if (!mounted) return;
      Navigator.of(context).pushNamed(isSetup ? '/vault-auth' : '/vault-setup');
      return;
    }
    if (label == 'Streaming') {
      unawaited(_loadStreams());
    }
    setState(() {
      _currentFilter = label.toLowerCase() == 'all'
          ? null
          : label.toLowerCase();
      _currentFolderName = null;
      _applyFilter();
    });
  }

  void _showUrlDialog() {
    _openUrlDialog();
  }

  Future<void> _moveToVault(VideoFile video) async {
    if (video.type != MediaType.video) {
      _showErrorSnackBar('Only video files can be moved to vault');
      return;
    }

    final isSetup = await VaultService.isVaultSetup();
    if (!mounted) return;
    if (!isSetup) {
      Navigator.of(context).pushNamed('/vault-setup');
      return;
    }

    if (!VaultService.isAuthenticated) {
      Navigator.of(context).pushNamed('/vault-auth');
      return;
    }

    final success = await VaultService.hideVideo(video.path);
    if (!mounted) return;
    if (success) {
      _showSuccessSnackBar('Moved to vault');
      await _scanVideos(background: true);
    } else {
      _showErrorSnackBar('Failed to move to vault');
    }
  }

  bool _isValidStreamUrl(String input) {
    if (input.trim().isEmpty) return false;
    final normalized = input.contains('://')
        ? input.trim()
        : 'https://${input.trim()}';
    final uri = Uri.tryParse(normalized);
    if (uri == null) return false;
    const allowedSchemes = ['http', 'https', 'rtsp', 'rtmp'];
    return allowedSchemes.contains(uri.scheme);
  }

  Future<List<String>> _getRecentUrls() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_recentUrlsKey) ?? [];
  }

  Future<void> _saveRecentUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getStringList(_recentUrlsKey) ?? [];
    final normalized = url.trim();
    if (normalized.isEmpty) return;
    final updated = [normalized, ...current.where((u) => u != normalized)];
    await prefs.setStringList(
      _recentUrlsKey,
      updated.take(_maxRecentUrls).toList(),
    );
  }

  Future<void> _removeRecentUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getStringList(_recentUrlsKey) ?? [];
    final updated = current.where((u) => u != url).toList();
    await prefs.setStringList(_recentUrlsKey, updated);
  }

  Future<void> _clearRecentUrls() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_recentUrlsKey);
  }

  Future<void> _openUrlDialog() async {
    final recentUrls = await _getRecentUrls();
    if (!mounted) return;

    unawaited(
      showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Play from URL'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _urlController,
                builder: (context, value, _) {
                  final isValid = _isValidStreamUrl(value.text);
                  return Column(
                    children: [
                      TextField(
                        controller: _urlController,
                        decoration: InputDecoration(
                          hintText: 'Enter video or stream URL',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.content_paste),
                            tooltip: 'Paste',
                            onPressed: () async {
                              final data = await Clipboard.getData(
                                'text/plain',
                              );
                              final text = data?.text ?? '';
                              if (text.trim().isEmpty) return;
                              _urlController.text = text.trim();
                            },
                          ),
                        ),
                      ),
                      if (value.text.trim().isNotEmpty && !isValid)
                        const Padding(
                          padding: EdgeInsets.only(top: 6),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Enter a valid URL (http/https/rtsp/rtmp)',
                              style: TextStyle(fontSize: 12, color: Colors.red),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
              if (recentUrls.isNotEmpty) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Recent',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(
                        dialogContext,
                      ).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: 160,
                  child: ListView.builder(
                    itemCount: recentUrls.length,
                    itemBuilder: (context, index) {
                      final url = recentUrls[index];
                      return ListTile(
                        dense: true,
                        title: Text(
                          url,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () async {
                            await _removeRecentUrl(url);
                            if (!dialogContext.mounted) return;
                            Navigator.pop(dialogContext);
                            await _openUrlDialog();
                          },
                        ),
                        onTap: () {
                          _urlController.text = url;
                        },
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
          actions: [
            if (recentUrls.isNotEmpty)
              TextButton(
                onPressed: () async {
                  await _clearRecentUrls();
                  if (!dialogContext.mounted) return;
                  Navigator.pop(dialogContext);
                  await _openUrlDialog();
                },
                child: const Text('Clear Recent'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                var input = _urlController.text.trim();
                if (input.isEmpty) {
                  if (!mounted) return;
                  _showErrorSnackBar('Enter a valid URL');
                  return;
                }

                if (!_isValidStreamUrl(input)) {
                  if (!mounted) return;
                  _showErrorSnackBar('Enter a valid stream URL');
                  return;
                }

                if (!input.contains('://')) {
                  input = 'https://$input';
                }

                await _saveRecentUrl(input);
                if (!dialogContext.mounted) return;
                Navigator.pop(dialogContext);
                if (!mounted) return;
                setState(() {
                  _videoUrl = input;
                  _videoPath = null;
                });
              },
              child: const Text('Play'),
            ),
          ],
        ),
      ),
    );
  }

  void _showSortOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      isScrollControlled: true,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'Sort By',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(
              child: ListView(
                shrinkWrap: true,
                children: [
                  ListTile(
                    leading: const Icon(Icons.sort_by_alpha),
                    title: const Text('Name'),
                    onTap: () {
                      _sortVideos((a, b) => a.name.compareTo(b.name));
                      Navigator.pop(context);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.date_range),
                    title: const Text('Date'),
                    onTap: () {
                      _sortVideos(
                        (a, b) => b.lastModified.compareTo(a.lastModified),
                      );
                      Navigator.pop(context);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.straighten),
                    title: const Text('Size'),
                    onTap: () {
                      _sortVideos((a, b) => b.size.compareTo(a.size));
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _sortVideos(int Function(VideoFile, VideoFile) compare) {
    setState(() {
      _localVideos.sort(compare);
      _applyFilter();
    });
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  Widget _buildFolderListItem(String folderName, int videoCount) {
    final theme = ref.watch(themeModeProvider);
    final isDark = theme == ThemeMode.dark;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - value)),
            child: child,
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
              spreadRadius: 0,
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              setState(() {
                _currentFolderName = folderName;
                _currentFilter = null;
                _applyFilter();
              });
            },
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    width: 80,
                    height: 50,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.orange.shade600,
                          Colors.orange.shade800,
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.orange.withValues(alpha: 0.4),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.folder_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          folderName,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '$videoCount videos',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.orange.shade600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeModeProvider);
    final isDark = theme == ThemeMode.dark;

    if (_videoPath != null || _videoUrl != null) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          _handleExitRequest();
        },
        child: Scaffold(
          backgroundColor: isDark ? Colors.black : Colors.white,
          body: ParthiPlayVideoPlayer(
            videoUrl: _videoUrl,
            videoPath: _videoPath,
            autoPlay: true,
            looping: false,
            onVideoEnded: _onVideoEnded,
            onBackPressed: () {
              setState(() {
                _videoPath = null;
                _videoUrl = null;
              });
            },
          ),
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleExitRequest();
      },
      child: Scaffold(
        backgroundColor: theme == ThemeMode.dark
            ? const Color(0xFF0A0A0A)
            : const Color(0xFFF5F5F7),
        appBar: AppBar(
          backgroundColor: theme == ThemeMode.dark
              ? const Color(0xFF0A0A0A)
              : const Color(0xFFF5F5F7),
          elevation: 0,
          centerTitle: false,
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.red.shade600, Colors.orange.shade600],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.play_circle_filled,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  'PARTHI PLAY',
                  style: TextStyle(
                    color: theme == ThemeMode.dark
                        ? Colors.white
                        : Colors.black,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Settings',
              icon: Icon(
                Icons.settings_outlined,
                color: theme == ThemeMode.dark
                    ? Colors.white70
                    : Colors.black54,
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SettingsScreen(),
                  ),
                );
              },
            ),
            PopupMenuButton<String>(
              icon: Icon(
                Icons.more_vert,
                color: theme == ThemeMode.dark
                    ? Colors.white54
                    : Colors.black54,
              ),
              onSelected: (value) {
                switch (value) {
                  case 'theme':
                    ref.read(themeModeProvider.notifier).toggleTheme();
                    break;
                  case 'cast':
                    break;
                  case 'url':
                    _showUrlDialog();
                    break;
                  case 'sort':
                    _showSortOptions();
                    break;
                  case 'settings':
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const SettingsScreen(),
                      ),
                    );
                    break;
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'theme',
                  child: Row(
                    children: [
                      Icon(
                        theme == ThemeMode.dark
                            ? Icons.light_mode
                            : Icons.dark_mode,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        theme == ThemeMode.dark ? 'Light Mode' : 'Dark Mode',
                      ),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'cast',
                  child: const Row(
                    children: [
                      Icon(Icons.cast, size: 20),
                      SizedBox(width: 12),
                      Text('Cast'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'url',
                  child: const Row(
                    children: [
                      Icon(Icons.search, size: 20),
                      SizedBox(width: 12),
                      Text('Play URL'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'sort',
                  child: const Row(
                    children: [
                      Icon(Icons.sort, size: 20),
                      SizedBox(width: 12),
                      Text('Sort'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'settings',
                  child: const Row(
                    children: [
                      Icon(Icons.settings_outlined, size: 20),
                      SizedBox(width: 12),
                      Text('Settings'),
                    ],
                  ),
                ),
              ],
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(60),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  _buildChip(
                    'Videos',
                    Icons.movie_outlined,
                    Colors.red,
                    () => _onChipTap('Videos'),
                    isActive: _currentFilter == 'videos',
                  ),
                  _buildChip(
                    'Folders',
                    Icons.folder_outlined,
                    Colors.orange,
                    () => _onChipTap('Folders'),
                    isActive: _currentFilter == 'folders',
                  ),
                  _buildChip(
                    'Streaming',
                    Icons.sensors,
                    Colors.purple,
                    () => _onChipTap('Streaming'),
                    isActive: _currentFilter == 'streaming',
                  ),
                  _buildChip(
                    'Privacy',
                    Icons.lock_outline,
                    Colors.blue,
                    () => _onChipTap('Privacy'),
                  ),
                ],
              ),
            ),
          ),
        ),
        body: RefreshIndicator(
          onRefresh: () async {
            if (_currentFilter == 'streaming') {
              await _loadStreams(showError: true);
            } else {
              await _scanVideos(background: false);
            }
          },
          color: Colors.red.shade600,
          child: _buildContent(),
        ),
      ),
    );
  }

  void _showAddStreamDialog() {
    final nameController = TextEditingController();
    final urlController = TextEditingController();

    unawaited(
      showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Add Stream'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Stream name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: urlController,
                decoration: const InputDecoration(
                  labelText: 'Stream URL (HLS)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                final name = nameController.text.trim();
                final url = urlController.text.trim();
                final uri = Uri.tryParse(url);
                if (name.isEmpty || uri == null || !uri.hasScheme) {
                  if (!mounted) return;
                  _showErrorSnackBar('Enter a valid name and URL');
                  return;
                }

                await StreamSourcesService.addCustomStream(
                  StreamSource(title: name, url: url, isLive: true),
                );
                if (!dialogContext.mounted) return;
                Navigator.of(dialogContext).pop();
                if (!mounted) return;
                await _loadStreams();
                _showSuccessSnackBar('Stream added');
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _removeStream(VideoFile video) async {
    await StreamSourcesService.removeCustomStream(video.path);
    if (!mounted) return;
    _showSuccessSnackBar('Stream removed');
    await _loadStreams();
  }

  void _generateVisibleThumbnails(List<VideoFile> videos) {
    final paths = videos
        .where((v) => v.type == MediaType.video)
        .map((v) => v.path)
        .toList();
    if (paths.isEmpty) {
      _showErrorSnackBar('No videos to generate thumbnails');
      return;
    }
    ThumbnailService.generateThumbnailsBatch(paths)
        .then((_) {
          if (mounted) {
            setState(() {});
          }
        })
        .catchError((e) {
          debugPrint('Error generating thumbnails: $e');
        });
    _showSuccessSnackBar('Generating thumbnails...');
  }

  Widget _buildContent() {
    final theme = ref.watch(themeModeProvider);
    final isDark = theme == ThemeMode.dark;

    final bool isFiltering =
        _currentFilter != null || _currentFolderName != null;
    final List<VideoFile> displayVideos = isFiltering
        ? _filteredVideos
        : _localVideos;

    // Show folders when folders filter is active
    if (_currentFilter == 'folders') {
      return _buildFoldersList();
    }

    if (_currentFilter == 'streaming') {
      return _buildStreamingList(displayVideos);
    }

    if (displayVideos.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 800),
                curve: Curves.easeOut,
                builder: (context, value, child) {
                  return Transform.scale(
                    scale: value,
                    child: Opacity(
                      opacity: value,
                      child: Container(
                        padding: const EdgeInsets.all(32),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: isDark
                                ? [
                                    const Color(0xFF1A1A1A),
                                    const Color(0xFF2A2A2A),
                                  ]
                                : [Colors.white, Colors.grey[50]!],
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(
                                alpha: isDark ? 0.3 : 0.1,
                              ),
                              blurRadius: 30,
                              offset: const Offset(0, 15),
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.movie_outlined,
                          size: 64,
                          color: isDark ? Colors.grey[300] : Colors.grey[700],
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 40),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeOut,
                builder: (context, value, child) {
                  return Opacity(
                    opacity: value,
                    child: Transform.translate(
                      offset: Offset(0, 20 * (1 - value)),
                      child: child,
                    ),
                  );
                },
                child: Column(
                  children: [
                    Text(
                      'No videos found',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Pull down to scan for videos',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'or check your storage permissions',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.grey[500] : Colors.grey[500],
                      ),
                    ),
                    const SizedBox(height: 40),
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.red.shade600, Colors.orange.shade600],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.red.withValues(alpha: 0.4),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: ElevatedButton.icon(
                        onPressed: () => _scanVideos(background: false),
                        icon: const Icon(Icons.refresh, color: Colors.white),
                        label: const Text(
                          'Scan Videos',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 16,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _showUrlDialog,
                      icon: const Icon(Icons.link),
                      label: const Text('Play URL'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: isDark ? Colors.white : Colors.black87,
                        side: BorderSide(
                          color: isDark ? Colors.white54 : Colors.grey.shade400,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is UserScrollNotification) {
          ThumbnailService.setPausedDebounced(
            notification.direction != ScrollDirection.idle,
          );
        }
        return false;
      },
      child: CustomScrollView(
        slivers: [
          if (_localVideos.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Row(
                  children: [
                    Icon(
                      Icons.video_library,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${displayVideos.length} ${displayVideos.length == 1 ? 'video' : 'videos'}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () =>
                          _generateVisibleThumbnails(displayVideos),
                      icon: const Icon(Icons.image_outlined, size: 18),
                      label: const Text('Thumbnails'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.red.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                final video = displayVideos[index];
                return _buildVideoListItem(video);
              }, childCount: displayVideos.length),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStreamingList(List<VideoFile> displayVideos) {
    final theme = ref.watch(themeModeProvider);
    final isDark = theme == ThemeMode.dark;

    if (_isLoadingStreams) {
      return const Center(child: CircularProgressIndicator());
    }

    if (displayVideos.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.sensors_rounded,
                size: 64,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
              const SizedBox(height: 16),
              Text(
                'No streams available',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Add a free stream to get started',
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _showAddStreamDialog,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple.shade600,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Add Stream'),
              ),
            ],
          ),
        ),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is UserScrollNotification) {
          ThumbnailService.setPausedDebounced(
            notification.direction != ScrollDirection.idle,
          );
        }
        return false;
      },
      child: CustomScrollView(
        // Keeps compatibility with Flutter versions before ScrollCacheExtent.
        // ignore: deprecated_member_use
        cacheExtent: 800,
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Icon(
                    Icons.sensors,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${displayVideos.length} streams',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _showAddStreamDialog,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.purple.shade600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                final video = displayVideos[index];
                return _buildVideoListItem(video);
              }, childCount: displayVideos.length),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChip(
    String label,
    IconData icon,
    Color color,
    VoidCallback onTap, {
    bool isActive = false,
  }) {
    final theme = ref.watch(themeModeProvider);
    final isDark = theme == ThemeMode.dark;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontSize: 14)),
          ],
        ),
        selected: isActive,
        onSelected: (_) => onTap(),
        backgroundColor: isDark
            ? Colors.white.withValues(alpha: 0.1)
            : Colors.grey[200],
        selectedColor: color.withValues(alpha: isDark ? 0.3 : 0.2),
        labelStyle: TextStyle(
          color: isActive
              ? (isDark ? Colors.white : color)
              : (isDark ? Colors.grey[300] : Colors.grey[700]),
          fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
          fontSize: 14,
        ),
        side: BorderSide.none,
        elevation: isActive ? 4 : 0,
        pressElevation: 2,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        avatar: null,
      ),
    );
  }

  Widget _buildFoldersList() {
    final theme = ref.watch(themeModeProvider);
    final isDark = theme == ThemeMode.dark;

    if (_folderNames.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.folder_outlined,
                  size: 64,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
              const SizedBox(height: 32),
              Text(
                'No folders found',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Pull down to scan for videos',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              children: [
                Icon(
                  Icons.folder,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  '${_folderNames.length} ${_folderNames.length == 1 ? 'folder' : 'folders'}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              final folderName = _folderNames[index];
              final videoCount = _foldersMap[folderName]?.length ?? 0;
              return _buildFolderListItem(folderName, videoCount);
            }, childCount: _folderNames.length),
          ),
        ),
      ],
    );
  }

  Widget _buildVideoListItem(VideoFile video) {
    final theme = ref.watch(themeModeProvider);
    final isDark = theme == ThemeMode.dark;

    return Container(
      key: ValueKey(video.path),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _playVideoItem(video),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Hero(
                  tag: 'video_thumb_${video.path}',
                  child: _VideoThumbnailWidget(
                    videoPath: video.path,
                    videoType: video.type,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        video.name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          if (video.type == MediaType.streaming)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'LIVE',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.red,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  (video.type == MediaType.audio
                                          ? Colors.blue
                                          : (video.type == MediaType.streaming
                                                ? Colors.purple
                                                : Colors.red))
                                      .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              video.type == MediaType.audio
                                  ? 'Audio'
                                  : video.type == MediaType.streaming
                                  ? 'Stream'
                                  : 'Video',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color: video.type == MediaType.audio
                                    ? Colors.blue.shade600
                                    : video.type == MediaType.streaming
                                    ? Colors.purple.shade600
                                    : Colors.red.shade600,
                              ),
                            ),
                          ),
                          Text(
                            video.type == MediaType.streaming
                                ? 'Live stream'
                                : video.formattedSize,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? Colors.grey[400]
                                  : Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_vert,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                  onSelected: (value) async {
                    switch (value) {
                      case 'play':
                        _playVideoItem(video);
                        break;
                      case 'info':
                        _showVideoInfo(video);
                        break;
                      case 'vault':
                        await _moveToVault(video);
                        break;
                      case 'remove_stream':
                        await _removeStream(video);
                        break;
                      case 'share':
                        if (video.type == MediaType.streaming) {
                          await Clipboard.setData(
                            ClipboardData(text: video.path),
                          );
                          _showSuccessSnackBar('Link copied');
                        } else {
                          await _shareVideo(video);
                        }
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'play',
                      child: Row(
                        children: [
                          Icon(Icons.play_arrow),
                          SizedBox(width: 8),
                          Text('Play'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'info',
                      child: Row(
                        children: [
                          Icon(Icons.info_outline),
                          SizedBox(width: 8),
                          Text('Info'),
                        ],
                      ),
                    ),
                    if (video.type == MediaType.video)
                      const PopupMenuItem(
                        value: 'vault',
                        child: Row(
                          children: [
                            Icon(Icons.lock_outline),
                            SizedBox(width: 8),
                            Text('Move to Vault'),
                          ],
                        ),
                      ),
                    if (video.type == MediaType.streaming &&
                        _customStreamUrls.contains(video.path))
                      const PopupMenuItem(
                        value: 'remove_stream',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline),
                            SizedBox(width: 8),
                            Text('Remove Stream'),
                          ],
                        ),
                      ),
                    PopupMenuItem(
                      value: 'share',
                      child: Row(
                        children: [
                          Icon(
                            video.type == MediaType.streaming
                                ? Icons.link
                                : Icons.share,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            video.type == MediaType.streaming
                                ? 'Copy Link'
                                : 'Share',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showVideoInfo(VideoFile video) {
    unawaited(
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(video.name),
          content: SizedBox(
            width: MediaQuery.of(context).size.width * 0.8,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Path: ${video.path}'),
                const SizedBox(height: 8),
                Text('Size: ${video.formattedSize}'),
                const SizedBox(height: 8),
                Text('Type: ${video.type.name}'),
                const SizedBox(height: 8),
                Text('Format: ${video.format}'),
                const SizedBox(height: 8),
                Text('Modified: ${video.lastModified}'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _shareVideo(VideoFile video) async {
    try {
      final shareFile = await ShareService.prepareShareFile(video.path);
      if (!mounted) return;

      await Share.shareXFiles(
        [shareFile],
        subject: 'Video from Parthi Play',
        text: 'Check out this video: ${video.name}',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Video shared successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } on ShareException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.orange),
        );
      }
    } catch (e) {
      debugPrint('Error sharing video: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sharing video: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

class _VideoThumbnailWidget extends StatefulWidget {
  final String videoPath;
  final MediaType videoType;

  const _VideoThumbnailWidget({
    required this.videoPath,
    required this.videoType,
  });

  @override
  State<_VideoThumbnailWidget> createState() => _VideoThumbnailWidgetState();
}

class _VideoThumbnailWidgetState extends State<_VideoThumbnailWidget> {
  String? _thumbnailPath;
  bool _isLoading = true;
  bool _thumbnailExists = false;

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  Future<void> _loadThumbnail() async {
    if (widget.videoType == MediaType.video) {
      final cached = await ThumbnailService.getThumbnailPath(widget.videoPath);
      if (cached != null) {
        final exists = await File(cached).exists();
        if (!mounted) return;
        if (exists) {
          setState(() {
            _thumbnailPath = cached;
            _thumbnailExists = true;
            _isLoading = false;
          });
          return;
        }
      }
      if (mounted) {
        unawaited(ThumbnailService.generateThumbnailsBatch([widget.videoPath]));
        unawaited(_retryLoadThumbnail());
      }
    } else {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _retryLoadThumbnail() async {
    const retries = 6;
    for (int i = 0; i < retries; i++) {
      await Future.delayed(const Duration(milliseconds: 400));
      final cached = await ThumbnailService.getThumbnailPath(widget.videoPath);
      if (cached == null) continue;
      final exists = await File(cached).exists();
      if (!mounted) return;
      if (!exists) continue;
      setState(() {
        _thumbnailPath = cached;
        _thumbnailExists = true;
        _isLoading = false;
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 100,
      height: 60,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: _isLoading || _thumbnailPath == null
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: widget.videoType == MediaType.audio
                    ? [Colors.blue.shade600, Colors.blue.shade800]
                    : widget.videoType == MediaType.streaming
                    ? [Colors.purple.shade600, Colors.purple.shade800]
                    : [Colors.red.shade600, Colors.orange.shade700],
              )
            : null,
        boxShadow: [
          BoxShadow(
            color:
                (widget.videoType == MediaType.audio
                        ? Colors.blue
                        : (widget.videoType == MediaType.streaming
                              ? Colors.purple
                              : Colors.red))
                    .withValues(alpha: 0.4),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: _thumbnailExists
          ? ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(_thumbnailPath!),
                width: 100,
                height: 60,
                fit: BoxFit.cover,
                cacheWidth: 200,
                cacheHeight: 120,
                filterQuality: FilterQuality.low,
                errorBuilder: (context, error, stackTrace) {
                  return _buildPlaceholder();
                },
              ),
            )
          : _buildPlaceholder(),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: widget.videoType == MediaType.audio
              ? [Colors.blue.shade600, Colors.blue.shade800]
              : widget.videoType == MediaType.streaming
              ? [Colors.purple.shade600, Colors.purple.shade800]
              : [Colors.red.shade600, Colors.orange.shade700],
        ),
      ),
      child: _isLoading
          ? const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            )
          : Icon(
              widget.videoType == MediaType.audio
                  ? Icons.music_note_rounded
                  : widget.videoType == MediaType.streaming
                  ? Icons.sensors_rounded
                  : Icons.play_circle_filled_rounded,
              color: Colors.white,
              size: 32,
            ),
    );
  }
}
