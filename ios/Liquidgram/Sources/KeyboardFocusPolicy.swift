import os
import WebKit

private let logger = Logger(subsystem: "org.liquidgram.messenger", category: "Keyboard")

/// Lets the keyboard come up for a field that the page focuses right after a native action, such as the chat search
/// after the Search quick action. WebKit shows the keyboard for a focused field only while the user touches the page,
/// so the field would get the focus without a keyboard. Before it shows the keyboard, WebKit asks the web view's
/// input delegate, which is private API (`_WKInputDelegate`, iOS 12 and later): this one allows the first focus
/// within a short time after such an action and leaves every other focus to WebKit. Without that API, every focus
/// keeps WebKit's behavior. Used on the main queue only.
final class KeyboardFocusPolicy: NSObject {
  /// Values of WebKit's `_WKFocusStartsInputSessionPolicy`: WebKit decides, or the keyboard comes up
  private static let automaticPolicy = 0
  private static let allowPolicy = 1
  private static let setInputDelegateSelector = NSSelectorFromString("_setInputDelegate:")

  private var allowsKeyboardUntil: ContinuousClock.Instant?

  /// Becomes the input delegate of `webView`, which keeps it weakly, so the caller keeps the policy
  func install(in webView: WKWebView) {
    guard webView.responds(to: Self.setInputDelegateSelector) else {
      logger.error("WebKit has no input delegate; fields that native actions focus show no keyboard")
      return
    }
    _ = webView.perform(Self.setInputDelegateSelector, with: self)
  }

  /// The first field that the page focuses within `duration` brings up the keyboard
  func allowKeyboard(for duration: Duration) {
    allowsKeyboardUntil = .now + duration
  }

  /// `_webView:decidePolicyForFocusedElement:` of `_WKInputDelegate`, which WebKit calls whenever the page focuses
  /// a field
  @objc(_webView:decidePolicyForFocusedElement:)
  func decidePolicy(webView: WKWebView, focusedElement: AnyObject) -> Int {
    guard let allowsKeyboardUntil, ContinuousClock.Instant.now < allowsKeyboardUntil else {
      return Self.automaticPolicy
    }
    self.allowsKeyboardUntil = nil
    return Self.allowPolicy
  }
}
