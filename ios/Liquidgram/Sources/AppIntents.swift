import AppIntents
import os
import UIKit

private let logger = Logger(subsystem: "org.liquidgram.messenger", category: "AppIntents")

// Siri and Shortcuts actions. Each one opens the app and performs a native action the way a home-screen quick
// action does, so it reaches the page once the page is ready and the app is unlocked.

struct OpenSavedMessagesIntent: AppIntent {
  static let title: LocalizedStringResource = "Open Saved Messages"
  static let description: IntentDescription? = IntentDescription("Opens your Saved Messages in Liquidgram.")
  static let openAppWhenRun = true

  @MainActor
  func perform() async throws -> some IntentResult {
    performNativeAction(.openSavedMessages)
    return .result()
  }
}

struct SearchChatsIntent: AppIntent {
  static let title: LocalizedStringResource = "Search Chats"
  static let description: IntentDescription? = IntentDescription("Opens the chat search in Liquidgram.")
  static let openAppWhenRun = true

  @MainActor
  func perform() async throws -> some IntentResult {
    performNativeAction(.openSearch)
    return .result()
  }
}

struct NewMessageIntent: AppIntent {
  static let title: LocalizedStringResource = "New Message"
  static let description: IntentDescription? = IntentDescription("Opens your contacts in Liquidgram to start a chat.")
  static let openAppWhenRun = true

  @MainActor
  func perform() async throws -> some IntentResult {
    performNativeAction(.newMessage)
    return .result()
  }
}

struct ToggleGhostModeIntent: AppIntent {
  static let title: LocalizedStringResource = "Toggle Ghost Mode"
  static let description: IntentDescription? = IntentDescription(
    "Turns ghost mode in Liquidgram on or off. Liquidgram shows the new state."
  )
  static let openAppWhenRun = true

  @MainActor
  func perform() async throws -> some IntentResult {
    performNativeAction(.toggleGhostMode)
    return .result()
  }
}

struct OpenChatIntent: AppIntent {
  static let title: LocalizedStringResource = "Open Chat"
  static let description: IntentDescription? = IntentDescription(
    "Opens a chat, a group or a channel in Liquidgram by its username."
  )
  static let openAppWhenRun = true

  @Parameter(title: "Username", requestValueDialog: "Which username?")
  var username: String

  static var parameterSummary: some ParameterSummary {
    Summary("Open chat with \(\.$username)")
  }

  @MainActor
  func perform() async throws -> some IntentResult {
    guard let link = NativeAction.makeResolveLink(username: username) else {
      throw $username.needsValueError("That is not a Telegram username. Which username?")
    }
    performNativeAction(.openLink(link))
    return .result()
  }
}

/// The phrases that work with Siri and the actions that the Shortcuts app and Spotlight offer without any setup
struct LiquidgramShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: OpenSavedMessagesIntent(),
      phrases: [
        "Open Saved Messages in \(.applicationName)",
        "Show my \(.applicationName) Saved Messages",
      ],
      shortTitle: "Saved Messages",
      systemImageName: "bookmark.fill"
    )
    AppShortcut(
      intent: SearchChatsIntent(),
      phrases: [
        "Search in \(.applicationName)",
        "Find a chat in \(.applicationName)",
      ],
      shortTitle: "Search",
      systemImageName: "magnifyingglass"
    )
    AppShortcut(
      intent: NewMessageIntent(),
      phrases: [
        "New message in \(.applicationName)",
        "Write a message in \(.applicationName)",
      ],
      shortTitle: "New Message",
      systemImageName: "square.and.pencil"
    )
    AppShortcut(
      intent: ToggleGhostModeIntent(),
      phrases: [
        "Toggle ghost mode in \(.applicationName)",
        "\(.applicationName) ghost mode",
      ],
      shortTitle: "Ghost Mode",
      systemImageName: "eye.slash"
    )
    AppShortcut(
      intent: OpenChatIntent(),
      phrases: [
        "Open a chat in \(.applicationName)",
        "Open a \(.applicationName) chat",
      ],
      shortTitle: "Open Chat",
      systemImageName: "bubble.left.and.bubble.right"
    )
  }

  static var shortcutTileColor: ShortcutTileColor {
    .purple
  }
}

/// Hands an intent's action to the bridge, which runs it like a quick action
@MainActor
private func performNativeAction(_ action: NativeAction) {
  guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else {
    logger.error("No app delegate to perform \(action.type, privacy: .public)")
    return
  }
  appDelegate.bridge.perform(action)
}
