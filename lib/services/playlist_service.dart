import 'package:flutter/foundation.dart';
import 'file_browser_service.dart';

class Playlist {
  final String id;
  final String name;
  final List<VideoFile> videos;
  final DateTime createdAt;
  final DateTime? lastPlayed;

  Playlist({
    required this.id,
    required this.name,
    required this.videos,
    required this.createdAt,
    this.lastPlayed,
  });

  Playlist copyWith({
    String? id,
    String? name,
    List<VideoFile>? videos,
    DateTime? createdAt,
    DateTime? lastPlayed,
  }) {
    return Playlist(
      id: id ?? this.id,
      name: name ?? this.name,
      videos: videos ?? this.videos,
      createdAt: createdAt ?? this.createdAt,
      lastPlayed: lastPlayed ?? this.lastPlayed,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'videos': videos.map((v) => v.path).toList(),
      'createdAt': createdAt.toIso8601String(),
      'lastPlayed': lastPlayed?.toIso8601String(),
    };
  }

  factory Playlist.fromJson(Map<String, dynamic> json) {
    return Playlist(
      id: json['id'],
      name: json['name'],
      videos: [], // Will be populated separately
      createdAt: DateTime.parse(json['createdAt']),
      lastPlayed: json['lastPlayed'] != null
          ? DateTime.parse(json['lastPlayed'])
          : null,
    );
  }
}

class PlaylistService {
  static const String _defaultPlaylistId = 'recent_videos';
  static final List<Playlist> _playlists = [];
  static Playlist? _currentPlaylist;
  static int _currentVideoIndex = 0;

  static Future<void> initialize() async {
    try {
      await _loadPlaylists();

      // Create default recent videos playlist if it doesn't exist
      if (!_playlists.any((p) => p.id == _defaultPlaylistId)) {
        final recentPlaylist = Playlist(
          id: _defaultPlaylistId,
          name: 'Recent Videos',
          videos: [],
          createdAt: DateTime.now(),
        );
        _playlists.add(recentPlaylist);
        await _savePlaylists();
      }
    } catch (e) {
      debugPrint('Error initializing playlist service: $e');
    }
  }

  static Future<void> _loadPlaylists() async {
    // In a real app, this would load from persistent storage
    // For now, we'll use in-memory storage
    _playlists.clear();
  }

  static Future<void> _savePlaylists() async {
    // In a real app, this would save to persistent storage
    // For now, we'll use in-memory storage
    debugPrint('Saving ${_playlists.length} playlists');
  }

  static List<Playlist> getPlaylists() {
    return List.unmodifiable(_playlists);
  }

  static Future<Playlist> createPlaylist(
    String name,
    List<VideoFile> videos,
  ) async {
    final playlist = Playlist(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      videos: videos,
      createdAt: DateTime.now(),
    );

    _playlists.add(playlist);
    await _savePlaylists();
    return playlist;
  }

  static Future<void> addToPlaylist(String playlistId, VideoFile video) async {
    final playlist = _playlists.firstWhere((p) => p.id == playlistId);
    final updatedVideos = List<VideoFile>.from(playlist.videos);

    // Check if video already exists
    if (!updatedVideos.any((v) => v.path == video.path)) {
      updatedVideos.add(video);

      final updatedPlaylist = playlist.copyWith(videos: updatedVideos);
      final index = _playlists.indexWhere((p) => p.id == playlistId);
      _playlists[index] = updatedPlaylist;
      await _savePlaylists();
    }
  }

  static Future<void> removeFromPlaylist(
    String playlistId,
    String videoPath,
  ) async {
    final playlist = _playlists.firstWhere((p) => p.id == playlistId);
    final updatedVideos = playlist.videos
        .where((v) => v.path != videoPath)
        .toList();

    final updatedPlaylist = playlist.copyWith(videos: updatedVideos);
    final index = _playlists.indexWhere((p) => p.id == playlistId);
    _playlists[index] = updatedPlaylist;
    await _savePlaylists();
  }

  static Future<void> deletePlaylist(String playlistId) async {
    if (playlistId == _defaultPlaylistId) {
      throw Exception('Cannot delete default playlist');
    }

    _playlists.removeWhere((p) => p.id == playlistId);
    await _savePlaylists();
  }

  static Future<void> updateRecentVideos(VideoFile video) async {
    final recentPlaylist = _playlists.firstWhere(
      (p) => p.id == _defaultPlaylistId,
    );
    final updatedVideos = List<VideoFile>.from(recentPlaylist.videos);

    // Remove if already exists
    updatedVideos.removeWhere((v) => v.path == video.path);

    // Add to beginning
    updatedVideos.insert(0, video);

    // Keep only last 50 videos
    if (updatedVideos.length > 50) {
      updatedVideos.removeRange(50, updatedVideos.length);
    }

    final updatedPlaylist = recentPlaylist.copyWith(
      videos: updatedVideos,
      lastPlayed: DateTime.now(),
    );

    final index = _playlists.indexWhere((p) => p.id == _defaultPlaylistId);
    _playlists[index] = updatedPlaylist;
    await _savePlaylists();
  }

  static Future<void> playPlaylist(
    Playlist playlist, {
    int startIndex = 0,
  }) async {
    _currentPlaylist = playlist;
    _currentVideoIndex = startIndex.clamp(0, playlist.videos.length - 1);

    final updatedPlaylist = playlist.copyWith(lastPlayed: DateTime.now());
    final index = _playlists.indexWhere((p) => p.id == playlist.id);
    _playlists[index] = updatedPlaylist;
    await _savePlaylists();
  }

  static Playlist? get currentPlaylist => _currentPlaylist;
  static int get currentVideoIndex => _currentVideoIndex;

  static VideoFile? getCurrentVideo() {
    if (_currentPlaylist == null ||
        _currentVideoIndex < 0 ||
        _currentVideoIndex >= _currentPlaylist!.videos.length) {
      return null;
    }
    return _currentPlaylist!.videos[_currentVideoIndex];
  }

  static VideoFile? getNextVideo() {
    if (_currentPlaylist == null ||
        _currentVideoIndex >= _currentPlaylist!.videos.length - 1) {
      return null;
    }
    _currentVideoIndex++;
    return getCurrentVideo();
  }

  static VideoFile? getPreviousVideo() {
    if (_currentPlaylist == null || _currentVideoIndex <= 0) {
      return null;
    }
    _currentVideoIndex--;
    return getCurrentVideo();
  }

  static bool hasNextVideo() {
    return _currentPlaylist != null &&
        _currentVideoIndex < _currentPlaylist!.videos.length - 1;
  }

  static bool hasPreviousVideo() {
    return _currentPlaylist != null && _currentVideoIndex > 0;
  }

  static Future<void> shufflePlaylist(String playlistId) async {
    final playlist = _playlists.firstWhere((p) => p.id == playlistId);
    final videos = List<VideoFile>.from(playlist.videos);
    videos.shuffle();

    final updatedPlaylist = playlist.copyWith(videos: videos);
    final index = _playlists.indexWhere((p) => p.id == playlistId);
    _playlists[index] = updatedPlaylist;
    await _savePlaylists();
  }

  static Future<void> clearPlaylist(String playlistId) async {
    final playlist = _playlists.firstWhere((p) => p.id == playlistId);
    final updatedPlaylist = playlist.copyWith(videos: []);
    final index = _playlists.indexWhere((p) => p.id == playlistId);
    _playlists[index] = updatedPlaylist;
    await _savePlaylists();
  }

  static Future<Playlist> createPlaylistFromDirectory(
    String directoryPath,
  ) async {
    final videos = await FileBrowserService.getVideoFilesInDirectory(
      directoryPath,
    );
    final playlistName = directoryPath.split('/').last;
    return createPlaylist(playlistName, videos);
  }
}
