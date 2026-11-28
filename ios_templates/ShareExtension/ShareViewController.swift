import Foundation
import UIKit

final class ShareViewController: UIViewController {
  private let appGroup = "group.com.yalkhodary.shaghal"
  private let sharedKey = "pending_shared_url"
  private let sharedQueueKey = "pending_shared_urls"
  private var handled = false
  private var queuedCount = 1

  private var statusLabel: UILabel?

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .clear

    let card = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterialDark))
    card.layer.cornerRadius = 24
    card.clipsToBounds = true
    card.translatesAutoresizingMaskIntoConstraints = false

    let label = UILabel()
    label.textColor = .white
    label.font = .systemFont(ofSize: 15, weight: .semibold)
    label.numberOfLines = 2
    label.textAlignment = .center
    label.text = "جاري الإرسال إلى شغال..."
    label.translatesAutoresizingMaskIntoConstraints = false
    statusLabel = label

    card.contentView.addSubview(label)
    view.addSubview(card)

    NSLayoutConstraint.activate([
      card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      card.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      card.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -48),
      label.topAnchor.constraint(equalTo: card.contentView.topAnchor, constant: 18),
      label.bottomAnchor.constraint(equalTo: card.contentView.bottomAnchor, constant: -18),
      label.leadingAnchor.constraint(equalTo: card.contentView.leadingAnchor, constant: 24),
      label.trailingAnchor.constraint(equalTo: card.contentView.trailingAnchor, constant: -24),
    ])
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    guard !handled else { return }
    handled = true
    extractSharedUrl { [weak self] urlString in
      guard let self = self else { return }
      if let urlString = urlString, !urlString.isEmpty {
        let clean = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if let defaults = UserDefaults(suiteName: self.appGroup) {
          var queue = defaults.stringArray(forKey: self.sharedQueueKey) ?? []
          if let legacy = defaults.string(forKey: self.sharedKey),
             !legacy.isEmpty,
             !queue.contains(legacy) {
            queue.append(legacy)
          }
          defaults.removeObject(forKey: self.sharedKey)
          if !queue.contains(clean) {
            queue.append(clean)
          }
          defaults.set(queue, forKey: self.sharedQueueKey)
          defaults.synchronize()
          self.queuedCount = queue.count
        }
        self.openMainApp(with: clean)
      } else {
        self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
      }
    }
  }

  private func extractSharedUrl(completion: @escaping (String?) -> Void) {
    guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
      completion(nil)
      return
    }
    for item in items {
      guard let providers = item.attachments else { continue }
      for provider in providers {
        if provider.hasItemConformingToTypeIdentifier("public.url") {
          provider.loadItem(forTypeIdentifier: "public.url", options: nil) { data, _ in
            let url = (data as? URL)?.absoluteString
              ?? (data as? NSURL)?.absoluteString
              ?? (data as? Data).flatMap { String(data: $0, encoding: .utf8) }
            DispatchQueue.main.async { completion(url) }
          }
          return
        }
        if provider.hasItemConformingToTypeIdentifier("public.plain-text") {
          provider.loadItem(forTypeIdentifier: "public.plain-text", options: nil) { data, _ in
            let text = data as? String
            let found = text.flatMap { Self.firstUrl(in: $0) }
            DispatchQueue.main.async { completion(found) }
          }
          return
        }
      }
    }
    completion(nil)
  }

  private static func firstUrl(in text: String) -> String? {
    let pattern = #"https?://[^\s<>"'\)]+"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
      return nil
    }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    guard let match = regex.firstMatch(in: text, options: [], range: range),
          let r = Range(match.range, in: text) else {
      return nil
    }
    return String(text[r])
  }

  private func openMainApp(with urlString: String) {
    var comps = URLComponents()
    comps.scheme = "shaghal"
    comps.host = "download"
    comps.queryItems = [URLQueryItem(name: "url", value: urlString)]
    guard let appUrl = comps.url else {
      extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
      return
    }

    var finished = false
    func finishExtension() {
      DispatchQueue.main.async { [weak self] in
        guard !finished else { return }
        finished = true
        self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
      }
    }

    // iOS 18+ blocks Share Extensions from foregrounding host apps via responder openURL.
    // Still attempt extensionContext?.open, and show confirmation before closing.
    extensionContext?.open(appUrl) { [weak self] opened in
      DispatchQueue.main.async {
        if opened {
          finishExtension()
        } else {
          let count = self?.queuedCount ?? 1
          self?.statusLabel?.text = count > 1
            ? "تمت إضافة الرابط لقائمة الانتظار (\(count)) ✓\nافتح «شغال» لاختيار الجودات"
            : "تم حفظ الرابط في «شغال» ✓\nافتح التطبيق للتحميل"
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
            finishExtension()
          }
        }
      }
    }
  }
}
