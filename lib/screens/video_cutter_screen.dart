import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';
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
  final List<StreamSubscription<Object?>> _subscriptions = [];

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
    _subscriptions.add(
      _player.stream.duration.listen((d) {
        if (mounted) {
          setState(() {
            _duration = d;
            _endValue = d.inMilliseconds.toDouble();
          });
        }
      }),
    );
    _subscriptions.add(
      _player.stream.position.listen((p) {
        if (mounted) setState(() => _position = p);
      }),
    );
    await _player.open(Media(widget.videoPath));
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_player.dispose());
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

      final startPos = CutterControlsPanel.formatDuration(
        Duration(milliseconds: _startValue.toInt()),
      );
      final durationToCut = CutterControlsPanel.formatDuration(
        Duration(milliseconds: (_endValue - _startValue).toInt()),
      );

      // Stream copy (no re-encode). Arguments are passed as a list so file
      // names containing quotes or spaces can't break or inject arguments.
      final arguments = <String>[
        '-ss',
        startPos,
        '-t',
        durationToCut,
        '-i',
        widget.videoPath,
        '-c',
        'copy',
        outputFilePath,
      ];

      await FFmpegKit.executeWithArguments(arguments).then((session) async {
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

  Widget _buildControlsPanel() => CutterControlsPanel(
    position: _position,
    duration: _duration,
    start: _startValue,
    end: _endValue,
    isProcessing: _isProcessing,
    onSeek: (position) => _player.seek(position),
    onRangeChanged: (values) => setState(() {
      _startValue = values.start;
      _endValue = values.end;
    }),
    onRangeChangeStart: () => _player.pause(),
    onRangeChangeEnd: (values) =>
        _player.seek(Duration(milliseconds: values.start.toInt())),
    onCut: _cutVideo,
  );
}

/// Trim controls for [VideoCutterScreen]. Scrolls when space is short
/// (small phones, landscape, large text) instead of overflowing.
class CutterControlsPanel extends StatelessWidget {
  const CutterControlsPanel({
    super.key,
    required this.position,
    required this.duration,
    required this.start,
    required this.end,
    required this.isProcessing,
    required this.onSeek,
    required this.onRangeChanged,
    required this.onRangeChangeStart,
    required this.onRangeChangeEnd,
    required this.onCut,
  });

  final Duration position;
  final Duration duration;
  final double start;
  final double end;
  final bool isProcessing;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<RangeValues> onRangeChanged;
  final VoidCallback onRangeChangeStart;
  final ValueChanged<RangeValues> onRangeChangeEnd;
  final VoidCallback onCut;

  static String formatDuration(Duration d) {
    final hours = d.inHours.toString().padLeft(2, '0');
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final milliseconds = d.inMilliseconds
        .remainder(1000)
        .toString()
        .padLeft(3, '0');
    return '$hours:$minutes:$seconds.$milliseconds';
  }

  /// Two labels pushed to opposite edges that wrap onto separate lines
  /// when they don't fit side by side.
  Widget _labels(
    String left,
    String right,
    TextStyle leftStyle,
    TextStyle rightStyle,
  ) {
    return SizedBox(
      width: double.infinity,
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        runSpacing: 4,
        children: [
          Text(left, style: leftStyle),
          Text(right, style: rightStyle),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxMs = duration.inMilliseconds > 0
        ? duration.inMilliseconds.toDouble()
        : 1.0;
    final currentMs = position.inMilliseconds.toDouble().clamp(0.0, maxMs);
    final rangeStart = start.clamp(0.0, maxMs);
    final rangeEnd = end.clamp(rangeStart, maxMs);

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF121212),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(30),
          topRight: Radius.circular(30),
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _labels(
              formatDuration(position),
              formatDuration(duration),
              const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              const TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w600,
              ),
            ),
            Slider(
              min: 0.0,
              max: maxMs,
              value: currentMs,
              activeColor: Colors.red,
              inactiveColor: Colors.white12,
              onChanged: (value) =>
                  onSeek(Duration(milliseconds: value.round())),
            ),
            const SizedBox(height: 8),
            _labels(
              formatDuration(Duration(milliseconds: rangeStart.toInt())),
              formatDuration(Duration(milliseconds: rangeEnd.toInt())),
              const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
              const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
            RangeSlider(
              values: RangeValues(rangeStart, rangeEnd),
              min: 0.0,
              max: maxMs,
              activeColor: Colors.red,
              inactiveColor: Colors.white12,
              onChanged: onRangeChanged,
              onChangeStart: (_) => onRangeChangeStart(),
              onChangeEnd: onRangeChangeEnd,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: isProcessing ? null : onCut,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                child: isProcessing
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(color: Colors.white),
                      )
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
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
