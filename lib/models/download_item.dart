import 'package:youtube_explode_dart/youtube_explode_dart.dart';

enum MediaOptionKind { video, audio }

class MediaFormatOption {
  const MediaFormatOption({
    required this.id,
    required this.label,
    required this.isVideo,
    required this.ext,
    required this.codecLabel,
    this.height = 0,
    this.fps = 0,
    this.bitrateBps = 0,
    this.sizeBytes,
    this.url,
    this.audioPairUrl,
    this.audioPairExt,
    this.isHls = false,
    this.needsAudioExtract = false,
    this.headers = const {},
    this.ytVideoStream,
    this.ytAudioStream,
    this.ytMuxedFallback,
  });

  final String id;
  final String label;
  final bool isVideo;
  final String ext;
  final String codecLabel;
  final int height;
  final int fps;
  final int bitrateBps;
  final int? sizeBytes;
  final String? url;
  final String? audioPairUrl;
  final String? audioPairExt;
  final bool isHls;
  final bool needsAudioExtract;
  final Map<String, String> headers;
  final StreamInfo? ytVideoStream;
  final AudioOnlyStreamInfo? ytAudioStream;
  final MuxedStreamInfo? ytMuxedFallback;

  bool get needsMux =>
      isVideo &&
      ((ytVideoStream != null && ytAudioStream != null) || audioPairUrl != null);
}

class ExtractedMedia {
  const ExtractedMedia({
    required this.title,
    required this.sourceUrl,
    this.thumbnailUrl,
    this.author,
    this.options = const [],
    this.needsBrowserSniff = false,
  });

  final String title;
  final String sourceUrl;
  final String? thumbnailUrl;
  final String? author;
  final List<MediaFormatOption> options;
  final bool needsBrowserSniff;

  List<MediaFormatOption> get videoOptions =>
      options.where((o) => o.isVideo).toList();

  List<MediaFormatOption> get audioOptions =>
      options.where((o) => !o.isVideo).toList();
}

enum DownloadTaskStatus {
  queued,
  downloading,
  processing,
  completed,
  failed,
  cancelled,
}

class DownloadTask {
  const DownloadTask({
    required this.id,
    required this.title,
    required this.sourceUrl,
    required this.option,
    required this.targetFolder,
    required this.status,
    required this.createdAt,
    this.thumbnailUrl,
    this.author,
    this.progress = 0,
    this.receivedBytes = 0,
    this.totalBytes,
    this.statusDetail,
    this.outputPath,
    this.errorMessage,
  });

  final String id;
  final String title;
  final String sourceUrl;
  final MediaFormatOption option;

  /// مسار نسبي داخل جذر المكتبة (الافتراضي 'Downloads').
  final String targetFolder;
  final DownloadTaskStatus status;
  final DateTime createdAt;
  final String? thumbnailUrl;
  final String? author;
  final double progress;
  final int receivedBytes;
  final int? totalBytes;
  final String? statusDetail;
  final String? outputPath;
  final String? errorMessage;

  DownloadTask copyWith({
    DownloadTaskStatus? status,
    double? progress,
    int? receivedBytes,
    int? totalBytes,
    String? statusDetail,
    String? outputPath,
    String? errorMessage,
  }) {
    return DownloadTask(
      id: id,
      title: title,
      sourceUrl: sourceUrl,
      option: option,
      targetFolder: targetFolder,
      status: status ?? this.status,
      createdAt: createdAt,
      thumbnailUrl: thumbnailUrl,
      author: author,
      progress: progress ?? this.progress,
      receivedBytes: receivedBytes ?? this.receivedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      statusDetail: statusDetail ?? this.statusDetail,
      outputPath: outputPath ?? this.outputPath,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

enum PendingShareStatus { analyzing, ready, failed }

class PendingShareItem {
  const PendingShareItem({
    required this.id,
    required this.url,
    required this.status,
    required this.addedAt,
    this.media,
    this.errorMessage,
  });

  final String id;
  final String url;
  final PendingShareStatus status;
  final DateTime addedAt;
  final ExtractedMedia? media;
  final String? errorMessage;

  PendingShareItem copyWith({
    PendingShareStatus? status,
    ExtractedMedia? media,
    String? errorMessage,
  }) {
    return PendingShareItem(
      id: id,
      url: url,
      status: status ?? this.status,
      addedAt: addedAt,
      media: media ?? this.media,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
