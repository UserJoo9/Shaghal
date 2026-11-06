import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../state/providers.dart';
import 'glass.dart';

String formatSize(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB'];
  var v = bytes.toDouble();
  var u = 0;
  while (v >= 1024 && u < units.length - 1) {
    v /= 1024;
    u++;
  }
  return '${v.toStringAsFixed(u == 0 ? 0 : 1)} ${units[u]}';
}

String formatDuration(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

void openFullPlayer(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => const FullPlayerPage(),
    ),
  );
}

class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(currentItemProvider).value;
    final playing = ref.watch(playingProvider).value ?? false;
    final ctrl = ref.watch(playerProvider);
    if (item == null) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () => openFullPlayer(context),
      child: Glass(
        radius: 34,
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              icon: Icon(
                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: 30,
              ),
              color: Colors.white,
              onPressed: ctrl.player.playOrPause,
            ),
            IconButton(
              icon: const Icon(Icons.skip_next_rounded, size: 30),
              color: Colors.white,
              onPressed: ctrl.player.next,
            ),
          ],
        ),
      ),
    );
  }
}

class FullPlayerPage extends ConsumerStatefulWidget {
  const FullPlayerPage({super.key});

  @override
  ConsumerState<FullPlayerPage> createState() => _FullPlayerPageState();
}

class _FullPlayerPageState extends ConsumerState<FullPlayerPage> {
  static const _rates = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
  double? _drag;
  int _rateIndex = 2;

  @override
  Widget build(BuildContext context) {
    final ctrl = ref.watch(playerProvider);
    final item = ref.watch(currentItemProvider).value;
    final playing = ref.watch(playingProvider).value ?? false;
    final pos = ref.watch(positionProvider).value ?? Duration.zero;
    final dur = ref.watch(durationProvider).value ?? Duration.zero;

    final max = dur.inMilliseconds > 0 ? dur.inMilliseconds.toDouble() : 1.0;
    final value = (_drag ?? pos.inMilliseconds.toDouble()).clamp(0.0, max).toDouble();
    final shown = Duration(milliseconds: value.round());

    return Scaffold(
      body: GlassBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    GlassIconButton(
                      icon: Icons.keyboard_arrow_down_rounded,
                      size: 44,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        item?.name ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: (item?.isVideo ?? false)
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: Video(
                            controller: ctrl.video,
                            controls: NoVideoControls,
                          ),
                        )
                      : Center(
                          child: Glass(
                            radius: 44,
                            padding: const EdgeInsets.all(48),
                            child: const Icon(
                              Icons.music_note_rounded,
                              size: 96,
                              color: Colors.white,
                            ),
                          ),
                        ),
                ),
                const SizedBox(height: 16),
                Glass(
                  radius: 36,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    children: [
                      Slider(
                        value: value,
                        min: 0,
                        max: max,
                        activeColor: Colors.white,
                        inactiveColor: Colors.white24,
                        onChanged: (v) => setState(() => _drag = v),
                        onChangeEnd: (v) {
                          ctrl.player.seek(Duration(milliseconds: v.round()));
                          setState(() => _drag = null);
                        },
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(formatDuration(shown),
                                style: const TextStyle(fontSize: 12)),
                            Text(formatDuration(dur),
                                style: const TextStyle(fontSize: 12)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          IconButton(
                            iconSize: 34,
                            color: Colors.white,
                            icon: const Icon(Icons.skip_previous_rounded),
                            onPressed: ctrl.player.previous,
                          ),
                          IconButton(
                            iconSize: 30,
                            color: Colors.white,
                            icon: const Icon(Icons.replay_10_rounded),
                            onPressed: () => ctrl.player.seek(
                              ctrl.player.state.position -
                                  const Duration(seconds: 10),
                            ),
                          ),
                          GestureDetector(
                            onTap: ctrl.player.playOrPause,
                            child: Container(
                              width: 68,
                              height: 68,
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                playing
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                size: 38,
                                color: Colors.black,
                              ),
                            ),
                          ),
                          IconButton(
                            iconSize: 30,
                            color: Colors.white,
                            icon: const Icon(Icons.forward_10_rounded),
                            onPressed: () => ctrl.player.seek(
                              ctrl.player.state.position +
                                  const Duration(seconds: 10),
                            ),
                          ),
                          IconButton(
                            iconSize: 34,
                            color: Colors.white,
                            icon: const Icon(Icons.skip_next_rounded),
                            onPressed: ctrl.player.next,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      GestureDetector(
                        onTap: () {
                          setState(() =>
                              _rateIndex = (_rateIndex + 1) % _rates.length);
                          ctrl.player.setRate(_rates[_rateIndex]);
                        },
                        child: Text(
                          'السرعة ${_rates[_rateIndex]}x',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
