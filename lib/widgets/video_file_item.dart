import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../services/file_browser_service.dart';
import '../services/thumbnail_service.dart';
import '../core/video_player_controller.dart';
import '../services/vault_service.dart';

class VideoFileItem extends StatelessWidget {
  final VideoFile videoFile;
  final VoidCallback onTap;
  final VoidCallback? onMoreTap;

  const VideoFileItem({
    super.key,
    required this.videoFile,
    required this.onTap,
    this.onMoreTap,
  });

  @override
  Widget build(BuildContext context) {
    // Use slightly darker/richer colors for premium feel
    // Use slightly darker/richer colors for premium feel

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.05),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          splashColor: Colors.red.withValues(alpha: 0.1),
          highlightColor: Colors.red.withValues(alpha: 0.05),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Premium Video Thumbnail / Icon Placeholder
                Hero(
                  tag: 'video_thumb_${videoFile.path}', // Simple hero tag
                  child: _VideoItemThumbnail(videoFile: videoFile),
                ),

                const SizedBox(width: 16),

                // Video Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        videoFile.displayName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildInfoBadge(videoFile.format.toUpperCase()),
                            const SizedBox(width: 8),
                            _buildInfoText(videoFile.formattedSize),
                            const SizedBox(width: 8),
                            _buildInfoText('•'),
                            const SizedBox(width: 8),
                            _buildInfoText(_formatDate(videoFile.lastModified)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // More Options Button
                Material(
                  color: Colors.transparent,
                  child: IconButton(
                    icon: const Icon(Icons.more_vert_rounded),
                    color: Colors.grey[400],
                    splashRadius: 24,
                    onPressed:
                        onMoreTap ??
                        () {
                          _showMoreOptions(context);
                        },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showMoreOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[700],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.info_outline, color: Colors.white),
              title: const Text(
                'File Info',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                // Can show info dialog here
              },
            ),
            ListTile(
              leading: const Icon(Icons.share, color: Colors.white),
              title: const Text('Share', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _shareVideo(context);
              },
            ),
            if (videoFile.type == MediaType.video)
              ListTile(
                leading: const Icon(Icons.lock_outline, color: Colors.white),
                title: const Text(
                  'Move to Vault',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  await _moveToVault(context);
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Delete', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                // Implement delete
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _moveToVault(BuildContext context) async {
    final isSetup = await VaultService.isVaultSetup();
    if (!context.mounted) return;
    if (!isSetup) {
      Navigator.of(context).pushNamed('/vault-setup');
      return;
    }

    if (!VaultService.isAuthenticated) {
      Navigator.of(context).pushNamed('/vault-auth');
      return;
    }

    final success = await VaultService.hideVideo(videoFile.path);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? 'Moved to vault' : 'Failed to move to vault'),
        backgroundColor: success ? Colors.green : Colors.red,
      ),
    );
  }

  Widget _buildInfoBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildInfoText(String text) {
    return Text(
      text,
      style: TextStyle(
        color: Colors.grey[400],
        fontSize: 12,
        fontWeight: FontWeight.w400,
      ),
    );
  }

  String _formatDate(DateTime date) {
    // Simple date formatting
    return '${date.day}/${date.month}/${date.year}';
  }

  Future<void> _shareVideo(BuildContext context) async {
    try {
      final file = File(videoFile.path);
      if (!await file.exists()) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Video file not found'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      await Share.shareXFiles(
        [XFile(videoFile.path)],
        subject: 'Video from Parthi Play',
        text: 'Check out this video: ${videoFile.displayName}',
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sharing video: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

class _VideoItemThumbnail extends StatefulWidget {
  final VideoFile videoFile;

  const _VideoItemThumbnail({required this.videoFile});

  @override
  State<_VideoItemThumbnail> createState() => _VideoItemThumbnailState();
}

class _VideoItemThumbnailState extends State<_VideoItemThumbnail> {
  String? _thumbnailPath;
  bool _isLoading = true;
  bool _thumbnailExists = false;

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  Future<void> _loadThumbnail() async {
    if (widget.videoFile.type != MediaType.video) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      return;
    }

    final cached = await ThumbnailService.getThumbnailPath(
      widget.videoFile.path,
    );
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
    if (!mounted) return;
    unawaited(ThumbnailService.generateThumbnailsBatch([widget.videoFile.path]));
    unawaited(_retryLoadThumbnail());
  }

  Future<void> _retryLoadThumbnail() async {
    const retries = 6;
    for (int i = 0; i < retries; i++) {
      await Future.delayed(const Duration(milliseconds: 400));
      final cached = await ThumbnailService.getThumbnailPath(
        widget.videoFile.path,
      );
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
                colors: widget.videoFile.type == MediaType.audio
                    ? [Colors.blue.shade600, Colors.blue.shade800]
                    : widget.videoFile.type == MediaType.streaming
                    ? [Colors.purple.shade600, Colors.purple.shade800]
                    : [const Color(0xFFE50914), const Color(0xFFB71C1C)],
              )
            : null,
        boxShadow: [
          BoxShadow(
            color:
                (widget.videoFile.type == MediaType.audio
                        ? Colors.blue
                        : (widget.videoFile.type == MediaType.streaming
                              ? Colors.purple
                              : Colors.red))
                    .withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
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
                errorBuilder: (_, __, ___) => _buildPlaceholder(),
              ),
            )
          : _buildPlaceholder(),
    );
  }

  Widget _buildPlaceholder() {
    return _isLoading
        ? const Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
          )
        : Center(
            child: Icon(
              widget.videoFile.type == MediaType.audio
                  ? Icons.music_note_rounded
                  : widget.videoFile.type == MediaType.streaming
                  ? Icons.sensors_rounded
                  : Icons.play_arrow_rounded,
              color: Colors.white,
              size: 28,
            ),
          );
  }
}
