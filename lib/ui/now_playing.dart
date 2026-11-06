import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../state/providers.dart';
import 'artwork.dart';
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

    // opaque: المنطقة الشفافة/الـ platform view بتخلّي اللمس يعدّي للقايمة اللي وراها
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => openFullPlayer(context),
      child: Glass(
        radius: 34,
        padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
        child: Row(
          children: [
            Artwork(
              path: item.path,
              size: 46,
              radius: 23,
              isVideo: item.isVideo,
            ),
            const SizedBox(width: 12),
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
  int _rateIndex = 2;

  @override
  Widget build(BuildContext context) {
    final ctrl = ref.watch(playerProvider);
    final item = ref.watch(currentItemProvider).value;
    final playing = ref.watch(playingProvider).value ?? false;

    return Rtl(child: Scaffold(
      body: GlassBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item?.name ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    GlassIconButton(
                      icon: Icons.chevron_left_rounded,
                      size: 46,
                      iconSize: 30,
                      onPressed: () => Navigator.of(context).pop(),
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
                      : (item == null
                          ? const SizedBox.shrink()
                          : Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 340,
                                  maxHeight: 340,
                                ),
                                child: AspectRatio(
                                  aspectRatio: 1,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(36),
                                      boxShadow: const [
                                        BoxShadow(
                                          color: Colors.black54,
                                          blurRadius: 40,
                                          offset: Offset(0, 20),
                                        ),
                                      ],
                                    ),
                                    child: LayoutBuilder(
                                      builder: (context, bc) => Artwork(
                                        path: item.path,
                                        size: bc.maxWidth,
                                        radius: 36,
                                        iconSize: bc.maxWidth * 0.35,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            )),
                ),
                const SizedBox(height: 16),
                // الشريط والأزرار دايماً LTR: السابق شمال والتالي يمين، والتقدّم من الشمال لليمين.
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Column(
                    children: [
                      const Glass(
                        radius: 28,
                        padding: EdgeInsets.fromLTRB(12, 6, 12, 12),
                        child: _SeekBody(),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          GlassIconButton(
                            icon: Icons.skip_previous_rounded,
                            size: 54,
                            iconSize: 30,
                            onPressed: ctrl.player.previous,
                          ),
                          GlassIconButton(
                            icon: Icons.replay_10_rounded,
                            size: 54,
                            iconSize: 28,
                            onPressed: () => ctrl.player.seek(
                              ctrl.player.state.position -
                                  const Duration(seconds: 10),
                            ),
                          ),
                          GlassIconButton(
                            icon: playing
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            size: 76,
                            iconSize: 42,
                            tint: const Color(0xFF0A84FF),
                            onPressed: ctrl.player.playOrPause,
                          ),
                          GlassIconButton(
                            icon: Icons.forward_10_rounded,
                            size: 54,
                            iconSize: 28,
                            onPressed: () => ctrl.player.seek(
                              ctrl.player.state.position +
                                  const Duration(seconds: 10),
                            ),
                          ),
                          GlassIconButton(
                            icon: Icons.skip_next_rounded,
                            size: 54,
                            iconSize: 30,
                            onPressed: ctrl.player.next,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      GestureDetector(
                        onTap: () {
                          setState(() =>
                              _rateIndex = (_rateIndex + 1) % _rates.length);
                          ctrl.player.setRate(_rates[_rateIndex]);
                        },
                        child: Glass(
                          radius: 20,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 10),
                          child: Text(
                            'السرعة ${_rates[_rateIndex]}x',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
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
    ));
  }
}


/// الشريط والأوقات لوحدهم عشان تحديث الموضع (كل أجزاء من الثانية) ما يعيدش بناء
/// باقي الصفحة والزجاج النيتيف، وده كان من أسباب الرعشة.
class _SeekBody extends ConsumerStatefulWidget {
  const _SeekBody();

  @override
  ConsumerState<_SeekBody> createState() => _SeekBodyState();
}

class _SeekBodyState extends ConsumerState<_SeekBody> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final ctrl = ref.watch(playerProvider);
    final pos = ref.watch(positionProvider).value ?? Duration.zero;
    final dur = ref.watch(durationProvider).value ?? Duration.zero;

    final max = dur.inMilliseconds > 0 ? dur.inMilliseconds.toDouble() : 1.0;
    final value =
        (_drag ?? pos.inMilliseconds.toDouble()).clamp(0.0, max).toDouble();
    final shown = Duration(milliseconds: value.round());

    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            overlayShape: SliderComponentShape.noOverlay,
            activeTrackColor: Colors.white,
            inactiveTrackColor: Colors.white24,
            thumbColor: Colors.white,
          ),
          child: Slider(
            value: value,
            min: 0,
            max: max,
            onChanged: (v) => setState(() => _drag = v),
            onChangeEnd: (v) {
              ctrl.player.seek(Duration(milliseconds: v.round()));
              setState(() => _drag = null);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(formatDuration(shown),
                  style: const TextStyle(fontSize: 12, color: Colors.white70)),
              Text(formatDuration(dur),
                  style: const TextStyle(fontSize: 12, color: Colors.white70)),
            ],
          ),
        ),
      ],
    );
  }
}
