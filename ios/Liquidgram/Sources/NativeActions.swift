import Foundation

/// An action that the native side asks the web app to perform through
/// `window.__liquidgramNative.dispatchAction(action)`. Home-screen quick actions, `liquidgram:` and `tg:` links,
/// Siri and the status bar create them.
enum NativeAction: Equatable {
  case openSavedMessages
  /// Focuses the chat search
  case openSearch
  /// Opens the picker for a new private chat
  case newMessage
  /// Toggles ghost mode, and the page shows a short toast with the new state
  case toggleGhostMode
  /// A `tg:` or `https://t.me/` link for the web app's `openTelegramLink`
  case openLink(String)
  /// The status bar was tapped: the visible chat list scrolls to the top
  case scrollToTop

  private static let shortcutTypePrefix = "org.liquidgram.messenger."
  private static let telegramScheme = "tg"
  private static let appScheme = "liquidgram"
  private static let webSchemes: Set<String> = ["http", "https"]
  private static let telegramHosts: Set<String> = ["t.me", "telegram.me", "telegram.dog"]
  private static let telegramSubdomainSuffix = ".t.me"
  /// `liquidgram://open?url=<link>` passes a URL-encoded Telegram link on
  private static let openLinkHost = "open"
  private static let openLinkQueryName = "url"
  private static let resolveHost = "resolve"
  private static let resolveQueryName = "domain"
  private static let usernamePrefixes = ["https://t.me/", "http://t.me/", "t.me/", "@"]
  private static let minUsernameLength = 4
  private static let maxUsernameLength = 32
  private static let maxLinkLength = 4096

  /// The `type` the page receives, which test hooks also use to name an action
  var type: String {
    switch self {
    case .openSavedMessages:
      return "openSavedMessages"
    case .openSearch:
      return "openSearch"
    case .newMessage:
      return "newMessage"
    case .toggleGhostMode:
      return "toggleGhostMode"
    case .openLink:
      return "openLink"
    case .scrollToTop:
      return "scrollToTop"
    }
  }

  /// The object passed to `dispatchAction`
  var message: [String: Any] {
    switch self {
    case .openLink(let url):
      return ["type": type, "url": url]
    default:
      return ["type": type]
    }
  }

  /// A status bar tap only makes sense right away, so it is dropped rather than queued for a page that is not ready
  var isTransient: Bool {
    self == .scrollToTop
  }

  /// The page focuses a text field for this action, and the keyboard should come up with it
  var focusesTextField: Bool {
    self == .openSearch
  }

  /// The action of a home-screen quick action declared in `UIApplicationShortcutItems`
  init?(shortcutItemType: String) {
    guard shortcutItemType.hasPrefix(Self.shortcutTypePrefix) else {
      return nil
    }
    switch shortcutItemType.dropFirst(Self.shortcutTypePrefix.count) {
    case "savedMessages":
      self = .openSavedMessages
    case "search":
      self = .openSearch
    case "newMessage":
      self = .newMessage
    case "ghostMode":
      self = .toggleGhostMode
    default:
      return nil
    }
  }

  /// An action without parameters by its `type`, as `-LiquidgramTestAction` names it
  init?(type: String) {
    let actions: [NativeAction] = [.openSavedMessages, .openSearch, .newMessage, .toggleGhostMode, .scrollToTop]
    guard let action = actions.first(where: { $0.type == type }) else {
      return nil
    }
    self = action
  }

  /// The action for a link that opened the app: `tg:X` passes on as is, `liquidgram:X` becomes `tg:X`, and
  /// `liquidgram://open?url=<link>` passes a URL-encoded `https://t.me/` or `tg:` link on
  init?(url: URL) {
    guard let link = Self.makeTelegramLink(from: url), link.count <= Self.maxLinkLength else {
      return nil
    }
    self = .openLink(link)
  }

  /// `tg://resolve?domain=<username>` for a Telegram username, typed with or without `@` or a t.me link in front
  static func makeResolveLink(username: String) -> String? {
    var name = username.trimmingCharacters(in: .whitespacesAndNewlines)
    if let prefix = usernamePrefixes.first(where: { name.lowercased().hasPrefix($0) }) {
      name = String(name.dropFirst(prefix.count))
    }
    let isUsernameCharacter: (Character) -> Bool = { character in
      character.isASCII && (character.isLetter || character.isNumber || character == "_")
    }
    guard (minUsernameLength...maxUsernameLength).contains(name.count),
          name.first?.isLetter == true,
          name.allSatisfy(isUsernameCharacter) else {
      return nil
    }

    var components = URLComponents()
    components.scheme = telegramScheme
    components.host = resolveHost
    components.queryItems = [URLQueryItem(name: resolveQueryName, value: name)]
    return components.string
  }

  private static func makeTelegramLink(from url: URL) -> String? {
    guard let scheme = url.scheme?.lowercased() else {
      return nil
    }
    switch scheme {
    case telegramScheme:
      return url.absoluteString
    case appScheme:
      guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
        return nil
      }
      if components.host?.lowercased() == openLinkHost {
        guard let value = components.queryItems?.first(where: { $0.name == openLinkQueryName })?.value,
              let link = URL(string: value), isTelegramLink(link) else {
          return nil
        }
        return link.absoluteString
      }
      // `liquidgram://` alone only opens the app
      guard components.host?.isEmpty == false || !components.path.isEmpty else {
        return nil
      }
      components.scheme = telegramScheme
      return components.string
    default:
      return nil
    }
  }

  private static func isTelegramLink(_ url: URL) -> Bool {
    guard let scheme = url.scheme?.lowercased() else {
      return false
    }
    if scheme == telegramScheme {
      return true
    }
    guard webSchemes.contains(scheme), let host = url.host?.lowercased() else {
      return false
    }
    return telegramHosts.contains(host) || host.hasSuffix(telegramSubdomainSuffix)
  }
}
