import 'package:flutter/material.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;

class VideoCutterScreen extends StatefulWidget {
  final String videoPath;

  const VideoCutterScreen({super.key, required this.videoPath});

  @override
  State<VideoCutterScreen> createState() => _VideoCutterScreenState();
}

class _VideoCutterScreenState extends State<VideoCutterScreen> {
  late final Player _player;
  late final VideoController _controller;

  double _startValue = 0.0;
  double _endValue = 1.0;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    await _player.open(Media(widget.videoPath));
    _player.stream.duration.listen((d) {
      if (mounted) {
        setState(() {
          _duration = d;
          _endValue = d.inMilliseconds.toDouble();
        });
      }
    });
    _player.stream.position.listen((p) {
      if (mounted) {
        setState(() {
          _position = p;
        });
      }
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _cutVideo() async {
    if (!mounted) return;
    setState(() => _isProcessing = true);

    try {
      final directoryPath = p.dirname(widget.videoPath);
      final fileName = p.basenameWithoutExtension(widget.videoPath);
      final extension = p.extension(widget.videoPath);
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final outputFilePath = p.join(
        directoryPath,
        '${fileName}_cut_$timestamp$extension',
      );

      if (_endValue <= _startValue) {
        setState(() => _isProcessing = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Invalid range selected')),
          );
        }
        return;
      }

      final startPos = _formatDuration(
        Duration(milliseconds: _startValue.toInt()),
      );
      final durationToCut = _formatDuration(
        Duration(milliseconds: (_endValue - _startValue).toInt()),
      );

      // FFmpeg command: -ss (start), -t (duration), -i (input), -c copy (fast)
      final command =
          '-ss $startPos -t $durationToCut -i "${widget.videoPath}" -c copy "$outputFilePath"';

      await FFmpegKit.execute(command).then((session) async {
        final returnCode = await session.getReturnCode();
        if (ReturnCode.isSuccess(returnCode)) {
          if (!mounted) return;
          setState(() {
            _isProcessing = false;
          });
          _showSuccessDialog(outputFilePath);
        } else {
          if (!mounted) return;
          setState(() => _isProcessing = false);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Failed to cut video')));
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours.toString().padLeft(2, '0');
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final milliseconds = d.inMilliseconds
        .remainder(1000)
        .toString()
        .padLeft(3, '0');
    return '$hours:$minutes:$seconds.$milliseconds';
  }

  void _showSuccessDialog(String path) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Success', style: TextStyle(color: Colors.white)),
        content: Text(
          'Video saved to:\n$path',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // Logic to open/play the new file could be here
            },
            child: const Text('Play Cut Video'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Video Cutter'),
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        child: isLandscape
            ? Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Container(
                      color: Colors.black,
                      child: Center(child: Video(controller: _controller)),
                    ),
                  ),
                  Expanded(flex: 2, child: _buildControlsPanel()),
                ],
              )
            : Column(
                children: [
                  Expanded(
                    flex: 3,
                    child: Container(
                      color: Colors.black,
                      child: Center(child: Video(controller: _controller)),
                    ),
                  ),
                  Expanded(flex: 2, child: _buildControlsPanel()),
                ],
              ),
      ),
    );
  }

  Widget _buildControlsPanel() {
    final maxMs = _duration.inMilliseconds.toDouble();
    final currentMs = _position.inMilliseconds.toDouble().clamp(
      0.0,
      maxMs > 0 ? maxMs : 1.0,
    );

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Color(0xFF121212),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(30),
          topRight: Radius.circular(30),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(_position),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                _formatDuration(_duration),
                style: const TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          Slider(
            min: 0.0,
            max: maxMs > 0 ? maxMs : 1.0,
            value: currentMs,
            activeColor: Colors.red,
            inactiveColor: Colors.white12,
            onChanged: (value) {
              final pos = Duration(milliseconds: value.round());
              _player.seek(pos);
            },
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(Duration(milliseconds: _startValue.toInt())),
                style: const TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                _formatDuration(Duration(milliseconds: _endValue.toInt())),
                style: const TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          RangeSlider(
            values: RangeValues(_startValue, _endValue),
            min: 0.0,
            max: maxMs > 0 ? maxMs : 1.0,
            activeColor: Colors.red,
            inactiveColor: Colors.white12,
            onChanged: (values) {
              setState(() {
                _startValue = values.start;
                _endValue = values.end;
              });
            },
            onChangeStart: (values) => _player.pause(),
            onChangeEnd: (values) {
              _player.seek(Duration(milliseconds: values.start.toInt()));
            },
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _isProcessing ? null : _cutVideo,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              child: _isProcessing
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text(
                      'CUT VIDEO',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Select range and click "CUT VIDEO" to trim.',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
