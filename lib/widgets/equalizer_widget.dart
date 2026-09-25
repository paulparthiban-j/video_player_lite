import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/video_player_controller.dart';

class EqualizerWidget extends ConsumerWidget {
  const EqualizerWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Select only equalizer fields so position updates don't rebuild sliders.
    final videoState = ref.watch(
      videoPlayerControllerProvider.select(
        (s) => (
          equalizerBands: s.equalizerBands,
          isEqualizerEnabled: s.isEqualizerEnabled,
        ),
      ),
    );
    final videoController = ref.read(videoPlayerControllerProvider.notifier);

    final List<String> freqLabels = [
      '31Hz',
      '62Hz',
      '125Hz',
      '250Hz',
      '500Hz',
      '1kHz',
      '2kHz',
      '4kHz',
      '8kHz',
      '16kHz',
    ];

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF121212),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.all(20),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Equalizer',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Switch(
                value: videoState.isEqualizerEnabled,
                onChanged: (_) => videoController.toggleEqualizer(),
                activeThumbColor: Colors.red,
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: SizedBox(
              height: 200,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: videoState.equalizerBands.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Column(
                      children: [
                        Expanded(
                          child: RotatedBox(
                            quarterTurns: 3,
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 4,
                                thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 8,
                                ),
                                activeTrackColor: Colors.red,
                                inactiveTrackColor: Colors.white24,
                                thumbColor: Colors.red,
                              ),
                              child: Slider(
                                min: -20.0,
                                max: 20.0,
                                value: videoState.equalizerBands[index],
                                onChanged: videoState.isEqualizerEnabled
                                    ? (value) {
                                        videoController.setEqualizerBand(
                                          index,
                                          value,
                                        );
                                      }
                                    : null,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          freqLabels[index],
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                          ),
                        ),
                        Text(
                          '${videoState.equalizerBands[index].toStringAsFixed(1)}dB',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 8,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildPresetButton(context, 'Reset', () {
                for (int i = 0; i < 10; i++) {
                  videoController.setEqualizerBand(i, 0.0);
                }
              }),
              _buildPresetButton(context, 'Bass Boost', () {
                videoController.setEqualizerBand(0, 10.0);
                videoController.setEqualizerBand(1, 8.0);
                videoController.setEqualizerBand(2, 5.0);
              }),
            ],
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _buildPresetButton(
    BuildContext context,
    String label,
    VoidCallback onTap,
  ) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white10,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Text(label),
    );
  }
}
