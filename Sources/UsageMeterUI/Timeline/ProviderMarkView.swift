import AppKit
import SwiftUI
import UsageMeterCore

extension Provider {
  fileprivate var markResourceName: String? {
    switch self {
    case .claude:
      "claude"
    case .codex:
      nil
    case .kimi:
      "kimi"
    case .minimax:
      "minimax"
    case .githubCopilot:
      "github-copilot"
    case .antigravity:
      "google"
    case .factory:
      "factory"
    case .openCodeGo, .openCodeZen:
      "opencode"
    case .superGrok:
      "grok"
    case .zai:
      nil
    case .mimo:
      nil
    }
  }

  fileprivate var markUsesOriginalRendering: Bool {
    self == .factory || self == .superGrok
  }
}

enum ProviderMarkImageLoader {
  private static let resourceBundleName =
    "AgenticUsageMeter_UsageMeterUI.bundle"

  static func image(for provider: Provider) -> NSImage? {
    guard
      let resourceName = provider.markResourceName,
      let url = providerMarkBundle.url(
        forResource: resourceName,
        withExtension: "svg",
      )
    else {
      return nil
    }
    return NSImage(contentsOf: url)
  }

  private static var providerMarkBundle: Bundle {
    guard
      let resourceURL = Bundle.main.resourceURL,
      let applicationBundle = Bundle(
        url: resourceURL.appending(
          path: resourceBundleName,
        ),
      )
    else {
      return Bundle.module
    }
    return applicationBundle
  }
}

struct ProviderMarkView: View {
  let provider: Provider

  var body: some View {
    if let image = ProviderMarkImageLoader.image(for: provider) {
      if provider.markUsesOriginalRendering {
        Image(nsImage: image)
          .resizable()
          .renderingMode(.original)
          .scaledToFit()
      } else {
        Image(nsImage: image)
          .resizable()
          .renderingMode(.template)
          .scaledToFit()
          .foregroundStyle(provider.timelineColor)
      }
    } else if let definition =
      ProviderCatalog.live.definition(for: provider)
    {
      Image(systemName: definition.systemImage)
        .resizable()
        .scaledToFit()
        .foregroundStyle(provider.timelineColor)
    } else {
      Text(String(provider.rawValue.prefix(1)).uppercased())
        .font(.caption2.weight(.bold))
        .foregroundStyle(provider.timelineColor)
    }
  }
}
