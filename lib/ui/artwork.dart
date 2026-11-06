import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';

/// صورة مصغّرة للأغنية/الفيديو، وبديل بتدرّج لوني ثابت لكل ملف لو مفيش غلاف.
class Artwork extends ConsumerWidget {
  const Artwork({
    super.key,
    required this.path,
    required this.size,
    this.radius = 14,
    this.isVideo = false,
    this.iconSize,
  });

  final String path;
  final double size;
  final double radius;
  final bool isVideo;
  final double? iconSize;

  int _hash(String s) {
    var h = 7;
    for (final c in s.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return h;
  }

  Widget _fallback() {
    final hue = (_hash(path) % 360).toDouble();
    return DecoratedBox(
      key: const ValueKey('fallback'),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            HSLColor.fromAHSL(1, hue, 0.55, 0.36).toColor(),
            HSLColor.fromAHSL(1, (hue + 40) % 360, 0.60, 0.16).toColor(),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          isVideo ? Icons.movie_rounded : Icons.music_note_rounded,
          color: Colors.white70,
          size: iconSize ?? size * 0.45,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thumb = ref.watch(thumbProvider(path)).value;
    final dpr = MediaQuery.devicePixelRatioOf(context);

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: thumb != null
              ? Image.file(
                  File(thumb),
                  key: ValueKey(thumb),
                  fit: BoxFit.cover,
                  cacheWidth: (size * dpr).round(),
                  gaplessPlayback: true,
                  errorBuilder: (_, __, ___) => _fallback(),
                )
              : _fallback(),
        ),
      ),
    );
  }
}
