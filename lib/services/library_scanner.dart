import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/media_formats.dart';
import '../models/media_item.dart';

/// بتتنادى جوّه compute() عشان المسح ميعطّلش الـ UI.
List<MediaItem> scanDirectory(String root) {
  final items = <MediaItem>[];
  final pending = <Directory>[Directory(root)];

  while (pending.isNotEmpty) {
    final dir = pending.removeLast();
    List<FileSystemEntity> entries;
    try {
      entries = dir.listSync(followLinks: false);
    } on FileSystemException {
      continue; // فولدر مش مقروء، كمّل في الباقي
    }
    for (final e in entries) {
      if (p.basename(e.path).startsWith('.')) continue;
      if (e is Directory) {
        pending.add(e);
      } else if (e is File) {
        final video = MediaFormats.isVideo(e.path);
        if (video == null) continue;
        try {
          final st = e.statSync();
          final rel = p.relative(p.dirname(e.path), from: root);
          items.add(MediaItem(
            path: e.path,
            folder: rel == '.' ? '' : rel,
            modified: st.modified,
            size: st.size,
            isVideo: video,
          ));
        } on FileSystemException {
          continue;
        }
      }
    }
  }
  return items;
}
