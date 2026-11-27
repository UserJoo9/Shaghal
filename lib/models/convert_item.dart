enum ConvertKind { audio, video }

enum VideoQualityPreset { original, p1080, p720, p480, p360 }

class ConvertFormat {
  const ConvertFormat({
    required this.id,
    required this.ext,
    required this.label,
    required this.isVideo,
    this.isLossless = false,
  });

  final String id;
  final String ext;
  final String label;
  final bool isVideo;
  final bool isLossless;

  static const audioFormats = <ConvertFormat>[
    ConvertFormat(id: 'mp3', ext: 'mp3', label: 'MP3', isVideo: false),
    ConvertFormat(id: 'm4a', ext: 'm4a', label: 'M4A (AAC)', isVideo: false),
    ConvertFormat(id: 'opus', ext: 'opus', label: 'OPUS', isVideo: false),
    ConvertFormat(id: 'ogg', ext: 'ogg', label: 'OGG (Vorbis)', isVideo: false),
    ConvertFormat(
      id: 'flac',
      ext: 'flac',
      label: 'FLAC',
      isVideo: false,
      isLossless: true,
    ),
    ConvertFormat(
      id: 'wav',
      ext: 'wav',
      label: 'WAV',
      isVideo: false,
      isLossless: true,
    ),
    ConvertFormat(id: 'aac', ext: 'aac', label: 'AAC', isVideo: false),
    ConvertFormat(
      id: 'alac',
      ext: 'm4a',
      label: 'ALAC (M4A)',
      isVideo: false,
      isLossless: true,
    ),
    ConvertFormat(
      id: 'aiff',
      ext: 'aiff',
      label: 'AIFF',
      isVideo: false,
      isLossless: true,
    ),
    ConvertFormat(id: 'wma', ext: 'wma', label: 'WMA', isVideo: false),
    ConvertFormat(id: 'ac3', ext: 'ac3', label: 'AC3', isVideo: false),
  ];

  static const videoFormats = <ConvertFormat>[
    ConvertFormat(id: 'mp4', ext: 'mp4', label: 'MP4 (H.264)', isVideo: true),
    ConvertFormat(id: 'mkv', ext: 'mkv', label: 'MKV', isVideo: true),
    ConvertFormat(id: 'mov', ext: 'mov', label: 'MOV', isVideo: true),
    ConvertFormat(id: 'm4v', ext: 'm4v', label: 'M4V', isVideo: true),
    ConvertFormat(id: 'webm', ext: 'webm', label: 'WEBM (VP8/Opus)', isVideo: true),
    ConvertFormat(id: 'avi', ext: 'avi', label: 'AVI', isVideo: true),
    ConvertFormat(id: 'ts', ext: 'ts', label: 'TS (MPEG-TS)', isVideo: true),
    ConvertFormat(id: 'flv', ext: 'flv', label: 'FLV', isVideo: true),
    ConvertFormat(id: '3gp', ext: '3gp', label: '3GP', isVideo: true),
  ];
}

enum ConvertTaskStatus {
  queued,
  converting,
  completed,
  failed,
  cancelled,
}

class ConvertJobRequest {
  const ConvertJobRequest({
    required this.sourcePath,
    required this.title,
    required this.targetRelFolder,
    required this.format,
    this.audioBitrateKbps = 192,
    this.videoQuality = VideoQualityPreset.original,
  });

  final String sourcePath;
  final String title;
  final String targetRelFolder;
  final ConvertFormat format;
  final int audioBitrateKbps;
  final VideoQualityPreset videoQuality;
}

class ConvertTask {
  const ConvertTask({
    required this.id,
    required this.sourcePath,
    required this.title,
    required this.targetRelFolder,
    required this.format,
    required this.audioBitrateKbps,
    required this.videoQuality,
    required this.status,
    required this.createdAt,
    this.progress = 0,
    this.outputPath,
    this.errorMessage,
  });

  final String id;
  final String sourcePath;
  final String title;
  final String targetRelFolder;
  final ConvertFormat format;
  final int audioBitrateKbps;
  final VideoQualityPreset videoQuality;
  final ConvertTaskStatus status;
  final DateTime createdAt;
  final double progress;
  final String? outputPath;
  final String? errorMessage;

  ConvertTask copyWith({
    ConvertTaskStatus? status,
    double? progress,
    String? outputPath,
    String? errorMessage,
  }) {
    return ConvertTask(
      id: id,
      sourcePath: sourcePath,
      title: title,
      targetRelFolder: targetRelFolder,
      format: format,
      audioBitrateKbps: audioBitrateKbps,
      videoQuality: videoQuality,
      status: status ?? this.status,
      createdAt: createdAt,
      progress: progress ?? this.progress,
      outputPath: outputPath ?? this.outputPath,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
