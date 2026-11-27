import Foundation
import UIKit

final class ShareViewController: UIViewController {
  private let appGroup = "group.com.yalkhodary.shaghal"
  private let sharedKey = "pending_shared_url"
  private var handled = false

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .clear
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    guard !handled else { return }
    handled = true
    extractSharedUrl { [weak self] urlString in
      guard let self = self else { return }
      if let urlString = urlString, !urlString.isEmpty {
        if let defaults = UserDefaults(suiteName: self.appGroup) {
          defaults.set(urlString, forKey: self.sharedKey)
          defaults.synchronize()
        }
        self.openMainApp(with: urlString)
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

    var responder: UIResponder? = self
    let sel = sel_registerName("openURL:")
    var openedViaResponder = false
    while let r = responder {
      if r.responds(to: sel) {
        r.perform(sel, with: appUrl)
        openedViaResponder = true
        break
      }
      responder = r.next
    }
    if openedViaResponder {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
        self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
      }
    } else {
      extensionContext?.open(appUrl) { [weak self] _ in
        self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
      }
    }
  }
}
