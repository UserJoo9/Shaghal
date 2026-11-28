import AVFoundation
import Flutter
import Foundation
import UIKit

final class ShaghalBridge: NSObject {
  private static let channelName = "com.yalkhodary.shaghal/native"
  private static let appGroup = "group.com.yalkhodary.shaghal"
  private static let sharedKey = "pending_shared_url"
  private static let sharedQueueKey = "pending_shared_urls"

  private static var instance: ShaghalBridge?
  private let channel: FlutterMethodChannel
  private var observer: NSObjectProtocol?

  static func register(with registrar: FlutterPluginRegistrar?) {
    guard let registrar = registrar, instance == nil else { return }
    let ch = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
    let bridge = ShaghalBridge(channel: ch)
    instance = bridge
    ch.setMethodCallHandler(bridge.handle)
  }

  private init(channel: FlutterMethodChannel) {
    self.channel = channel
    super.init()
    observer = NotificationCenter.default.addObserver(
      forName: UIApplication.didBecomeActiveNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      let urls = self?.popSharedUrls() ?? []
      if !urls.isEmpty {
        self?.channel.invokeMethod("onSharedUrls", arguments: urls)
      }
    }
  }

  deinit {
    if let obs = observer {
      NotificationCenter.default.removeObserver(obs)
    }
  }

  private func popSharedUrls() -> [String] {
    guard let defaults = UserDefaults(suiteName: Self.appGroup) else { return [] }
    var urls: [String] = []
    if let list = defaults.stringArray(forKey: Self.sharedQueueKey) {
      for item in list {
        let clean = item.trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.isEmpty && !urls.contains(clean) {
          urls.append(clean)
        }
      }
    }
    if let single = defaults.string(forKey: Self.sharedKey) {
      let clean = single.trimmingCharacters(in: .whitespacesAndNewlines)
      if !clean.isEmpty && !urls.contains(clean) {
        urls.append(clean)
      }
    }
    if !urls.isEmpty {
      defaults.removeObject(forKey: Self.sharedQueueKey)
      defaults.removeObject(forKey: Self.sharedKey)
      defaults.synchronize()
    }
    return urls
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "consumePendingSharedUrls":
      result(popSharedUrls())

    case "consumePendingSharedUrl":
      result(popSharedUrls().first)

    case "muxVideoAndAudio":
      guard let args = call.arguments as? [String: Any],
            let videoPath = args["videoPath"] as? String,
            let audioPath = args["audioPath"] as? String,
            let outputPath = args["outputPath"] as? String else {
        result(FlutterError(code: "INVALID_ARGS", message: "Missing mux paths", details: nil))
        return
      }
      DispatchQueue.global(qos: .userInitiated).async {
        self.mux(videoPath: videoPath, audioPath: audioPath, outputPath: outputPath, result: result)
      }

    case "extractAudio":
      guard let args = call.arguments as? [String: Any],
            let inputPath = args["inputPath"] as? String,
            let outputPath = args["outputPath"] as? String else {
        result(FlutterError(code: "INVALID_ARGS", message: "Missing extract paths", details: nil))
        return
      }
      DispatchQueue.global(qos: .userInitiated).async {
        self.extractAudio(inputPath: inputPath, outputPath: outputPath, result: result)
      }

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func mux(
    videoPath: String,
    audioPath: String,
    outputPath: String,
    result: @escaping FlutterResult
  ) {
    let videoAsset = AVURLAsset(url: URL(fileURLWithPath: videoPath))
    let audioAsset = AVURLAsset(url: URL(fileURLWithPath: audioPath))
    let comp = AVMutableComposition()

    guard let videoSrc = videoAsset.tracks(withMediaType: .video).first,
          let videoDst = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
      DispatchQueue.main.async {
        result(FlutterError(code: "NO_VIDEO_TRACK", message: "No video track found", details: nil))
      }
      return
    }

    do {
      try videoDst.insertTimeRange(
        CMTimeRange(start: .zero, duration: videoAsset.duration),
        of: videoSrc,
        at: .zero
      )
      videoDst.preferredTransform = videoSrc.preferredTransform
      if let audioSrc = audioAsset.tracks(withMediaType: .audio).first,
         let audioDst = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
        let dur = CMTimeMinimum(videoAsset.duration, audioAsset.duration)
        try audioDst.insertTimeRange(
          CMTimeRange(start: .zero, duration: dur),
          of: audioSrc,
          at: .zero
        )
      }
    } catch {
      DispatchQueue.main.async {
        result(FlutterError(code: "MUX_PREP_FAILED", message: error.localizedDescription, details: nil))
      }
      return
    }

    export(
      asset: comp,
      outputPath: outputPath,
      presets: [AVAssetExportPresetPassthrough, AVAssetExportPresetHighestQuality],
      fileType: .mp4,
      result: result
    )
  }

  private func extractAudio(
    inputPath: String,
    outputPath: String,
    result: @escaping FlutterResult
  ) {
    let asset = AVURLAsset(url: URL(fileURLWithPath: inputPath))
    export(
      asset: asset,
      outputPath: outputPath,
      presets: [AVAssetExportPresetAppleM4A],
      fileType: .m4a,
      result: result
    )
  }

  private func export(
    asset: AVAsset,
    outputPath: String,
    presets: [String],
    fileType: AVFileType,
    result: @escaping FlutterResult
  ) {
    let outUrl = URL(fileURLWithPath: outputPath)
    try? FileManager.default.removeItem(at: outUrl)

    func attempt(_ idx: Int) {
      if idx >= presets.count {
        DispatchQueue.main.async {
          result(FlutterError(code: "EXPORT_FAILED", message: "All export presets failed", details: nil))
        }
        return
      }
      guard let session = AVAssetExportSession(asset: asset, presetName: presets[idx]) else {
        attempt(idx + 1)
        return
      }
      session.outputURL = outUrl
      session.outputFileType = session.supportedFileTypes.contains(fileType)
        ? fileType
        : session.supportedFileTypes.first
      session.shouldOptimizeForNetworkUse = true
      session.exportAsynchronously {
        if session.status == .completed {
          DispatchQueue.main.async { result(true) }
        } else if idx + 1 < presets.count {
          try? FileManager.default.removeItem(at: outUrl)
          attempt(idx + 1)
        } else {
          let msg = session.error?.localizedDescription ?? "Export failed (\(session.status.rawValue))"
          DispatchQueue.main.async {
            result(FlutterError(code: "EXPORT_FAILED", message: msg, details: nil))
          }
        }
      }
    }

    attempt(0)
  }
}
