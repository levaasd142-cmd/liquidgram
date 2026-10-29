// Stand-in for the XCTest and XCUIAutomation API of the Xcode 26 SDK, so the UI tests type-check on Linux with
// `typecheck.sh`. Signatures follow the SDK; the XCUI classes are `@MainActor`, as `NS_SWIFT_UI_ACTOR` makes them.
// The bodies do nothing. Add what a test needs with the SDK's signature.
@_exported import UIKit

open class XCTAttachment: NSObject {
  public enum Lifetime: Int {
    case keepAlways = 0
    case deleteOnSuccess = 1
  }

  public init(data payload: Data, uniformTypeIdentifier identifier: String) {}
  public init(data payload: Data) {}
  public init(string: String) {}
  public init(screenshot: XCUIScreenshot) {}
  open var name: String?
  open var lifetime: Lifetime = .deleteOnSuccess
}

open class XCTestExpectation: NSObject {
  public init(description expectationDescription: String) {}
  open func fulfill() {}
  open var isInverted = false
  open var expectedFulfillmentCount = 1
}

open class XCTNSPredicateExpectation: XCTestExpectation {
  public init(predicate: NSPredicate, object: Any?) {
    super.init(description: "")
  }
}

open class XCTWaiter: NSObject {
  public enum Result: Int {
    case completed = 1
    case timedOut = 2
    case incorrectOrder = 3
    case invertedFulfillment = 4
    case interrupted = 5
  }

  open class func wait(for expectations: [XCTestExpectation], timeout seconds: TimeInterval) -> Result { .completed }
}

public struct XCTIssue {
  public enum IssueType: Int {
    case assertionFailure = 0
    case thrownError = 1
    case uncaughtException = 2
    case performanceRegression = 3
    case system = 4
    case unmatchedExpectedFailure = 5
  }

  public var type: IssueType
  public var compactDescription: String
  public var attachments: [XCTAttachment]
  public mutating func add(_ attachment: XCTAttachment) {}
}

open class XCTestCase: NSObject {
  open var continueAfterFailure: Bool = true
  open var name: String { "" }
  open func setUp() {}
  open func tearDown() {}
  open func setUpWithError() throws {}
  open func tearDownWithError() throws {}
  open func add(_ attachment: XCTAttachment) {}
  open func record(_ issue: XCTIssue) {}
  open func addTeardownBlock(_ block: @escaping () -> Void) {}
  open func expectation(description: String) -> XCTestExpectation { XCTestExpectation(description: description) }
  open func wait(for expectations: [XCTestExpectation], timeout seconds: TimeInterval) {}
  open func addUIInterruptionMonitor(
    withDescription handlerDescription: String,
    handler: @escaping (XCUIElement) -> Bool
  ) -> NSObjectProtocol { NSObject() }
  open func removeUIInterruptionMonitor(_ monitor: NSObjectProtocol) {}
}

public struct XCTSkip: Error {
  public init(_ message: String? = nil, file: StaticString = #filePath, line: UInt = #line) {}
}

public func XCTFail(_ message: String = "", file: StaticString = #filePath, line: UInt = #line) {}
public func XCTAssert(
  _ expression: @autoclosure () throws -> Bool,
  _ message: @autoclosure () -> String = "",
  file: StaticString = #filePath,
  line: UInt = #line
) {}
public func XCTAssertTrue(
  _ expression: @autoclosure () throws -> Bool,
  _ message: @autoclosure () -> String = "",
  file: StaticString = #filePath,
  line: UInt = #line
) {}
public func XCTAssertFalse(
  _ expression: @autoclosure () throws -> Bool,
  _ message: @autoclosure () -> String = "",
  file: StaticString = #filePath,
  line: UInt = #line
) {}
public func XCTAssertNil(
  _ expression: @autoclosure () throws -> Any?,
  _ message: @autoclosure () -> String = "",
  file: StaticString = #filePath,
  line: UInt = #line
) {}
public func XCTAssertNotNil(
  _ expression: @autoclosure () throws -> Any?,
  _ message: @autoclosure () -> String = "",
  file: StaticString = #filePath,
  line: UInt = #line
) {}
public func XCTAssertEqual<T: Equatable>(
  _ expression1: @autoclosure () throws -> T,
  _ expression2: @autoclosure () throws -> T,
  _ message: @autoclosure () -> String = "",
  file: StaticString = #filePath,
  line: UInt = #line
) {}
public func XCTAssertEqual<T: FloatingPoint>(
  _ expression1: @autoclosure () throws -> T,
  _ expression2: @autoclosure () throws -> T,
  accuracy: T,
  _ message: @autoclosure () -> String = "",
  file: StaticString = #filePath,
  line: UInt = #line
) {}
public func XCTAssertNotEqual<T: Equatable>(
  _ expression1: @autoclosure () throws -> T,
  _ expression2: @autoclosure () throws -> T,
  _ message: @autoclosure () -> String = "",
  file: StaticString = #filePath,
  line: UInt = #line
) {}
public func XCTAssertGreaterThan<T: Comparable>(
  _ expression1: @autoclosure () throws -> T,
  _ expression2: @autoclosure () throws -> T,
  _ message: @autoclosure () -> String = "",
  file: StaticString = #filePath,
  line: UInt = #line
) {}
public func XCTAssertGreaterThanOrEqual<T: Comparable>(
  _ expression1: @autoclosure () throws -> T,
  _ expression2: @autoclosure () throws -> T,
  _ message: @autoclosure () -> String = "",
  file: StaticString = #filePath,
  line: UInt = #line
) {}
public func XCTAssertLessThan<T: Comparable>(
  _ expression1: @autoclosure () throws -> T,
  _ expression2: @autoclosure () throws -> T,
  _ message: @autoclosure () -> String = "",
  file: StaticString = #filePath,
  line: UInt = #line
) {}
public func XCTAssertLessThanOrEqual<T: Comparable>(
  _ expression1: @autoclosure () throws -> T,
  _ expression2: @autoclosure () throws -> T,
  _ message: @autoclosure () -> String = "",
  file: StaticString = #filePath,
  line: UInt = #line
) {}
public func XCTUnwrap<T>(
  _ expression: @autoclosure () throws -> T?,
  _ message: @autoclosure () -> String = "",
  file: StaticString = #filePath,
  line: UInt = #line
) throws -> T {
  guard let value = try expression() else {
    throw XCTSkip()
  }
  return value
}

public enum XCTContext {
  public static func runActivity<Result>(named name: String, block: (Any) throws -> Result) rethrows -> Result {
    try block(name)
  }
}

public struct XCUIGestureVelocity: ExpressibleByFloatLiteral, ExpressibleByIntegerLiteral {
  public init(floatLiteral value: Double) {}
  public init(integerLiteral value: Int) {}
  public static let `default`: XCUIGestureVelocity = 0
  public static let slow: XCUIGestureVelocity = 300
  public static let fast: XCUIGestureVelocity = 3000
}

@MainActor
open class XCUICoordinate: NSObject {
  open var referencedElement: XCUIElement { XCUIElement() }
  open var screenPoint: CGPoint { .zero }
  open func withOffset(_ offsetVector: CGVector) -> XCUICoordinate { self }
  open func tap() {}
  open func doubleTap() {}
  open func press(forDuration duration: TimeInterval) {}
  open func press(forDuration duration: TimeInterval, thenDragTo otherCoordinate: XCUICoordinate) {}
  open func press(
    forDuration duration: TimeInterval,
    thenDragTo otherCoordinate: XCUICoordinate,
    withVelocity velocity: XCUIGestureVelocity,
    thenHoldForDuration holdDuration: TimeInterval
  ) {}
}

@MainActor
open class XCUIScreenshot: NSObject {
  open var image: UIImage { UIImage() }
  open var pngRepresentation: Data { Data() }
}

@MainActor
open class XCUIScreen: NSObject {
  open class var main: XCUIScreen { XCUIScreen() }
  open class var screens: [XCUIScreen] { [] }
  open func screenshot() -> XCUIScreenshot { XCUIScreenshot() }
}

@MainActor
open class XCUIDevice: NSObject {
  public enum Button: Int {
    case home = 1
    case volumeUp = 2
    case volumeDown = 3
  }

  open class var shared: XCUIDevice { XCUIDevice() }
  open var orientation: UIDeviceOrientation = .portrait
  open func press(_ button: XCUIDevice.Button) {}
}

@MainActor
open class XCUIElement: NSObject {
  public enum ElementType: UInt {
    case any = 0
    case other = 1
    case application = 2
    case group = 3
    case window = 4
    case sheet = 5
    case drawer = 6
    case alert = 7
    case dialog = 8
    case button = 9
    case radioButton = 10
    case radioGroup = 11
    case checkBox = 12
    case disclosureTriangle = 13
    case popUpButton = 14
    case comboBox = 15
    case menuButton = 16
    case toolbarButton = 17
    case popover = 18
    case keyboard = 19
    case key = 20
    case navigationBar = 21
    case tabBar = 22
    case tabGroup = 23
    case toolbar = 24
    case statusBar = 25
    case table = 26
    case tableRow = 27
    case tableColumn = 28
    case outline = 29
    case outlineRow = 30
    case browser = 31
    case collectionView = 32
    case slider = 33
    case pageIndicator = 34
    case progressIndicator = 35
    case activityIndicator = 36
    case segmentedControl = 37
    case picker = 38
    case pickerWheel = 39
    case `switch` = 40
    case toggle = 41
    case link = 42
    case image = 43
    case icon = 44
    case searchField = 45
    case scrollView = 46
    case scrollBar = 47
    case staticText = 48
    case textField = 49
    case secureTextField = 50
    case datePicker = 51
    case textView = 52
    case menu = 53
    case menuItem = 54
    case menuBar = 55
    case menuBarItem = 56
    case map = 57
    case webView = 58
    case incrementArrow = 59
    case decrementArrow = 60
    case timeline = 61
    case ratingIndicator = 62
    case valueIndicator = 63
    case splitGroup = 64
    case splitter = 65
    case relevanceIndicator = 66
    case colorWell = 67
    case helpTag = 68
    case matte = 69
    case dockItem = 70
    case ruler = 71
    case rulerMarker = 72
    case grid = 73
    case levelIndicator = 74
    case cell = 75
    case layoutArea = 76
    case layoutItem = 77
    case handle = 78
    case stepper = 79
    case tab = 80
    case touchBar = 81
    case statusItem = 82
  }

  open var exists: Bool { false }
  open var isHittable: Bool { false }
  open var isEnabled: Bool { false }
  open var isSelected: Bool { false }
  open var frame: CGRect { .zero }
  // `nonisolated` only so that key paths such as `\.label` type-check, as they do against the SDK in Swift 5 mode
  nonisolated open var label: String { "" }
  open var identifier: String { "" }
  open var title: String { "" }
  open var value: Any? { nil }
  open var placeholderValue: String? { nil }
  open var elementType: ElementType { .any }
  open var firstMatch: XCUIElement { self }
  open override var debugDescription: String { "" }

  open func waitForExistence(timeout: TimeInterval) -> Bool { false }
  open func waitForNonExistence(withTimeout timeout: TimeInterval) -> Bool { false }
  open func screenshot() -> XCUIScreenshot { XCUIScreenshot() }
  open func tap() {}
  open func doubleTap() {}
  open func twoFingerTap() {}
  open func press(forDuration duration: TimeInterval) {}
  open func press(forDuration duration: TimeInterval, thenDragTo otherElement: XCUIElement) {}
  open func press(
    forDuration duration: TimeInterval,
    thenDragTo otherElement: XCUIElement,
    withVelocity velocity: XCUIGestureVelocity,
    thenHoldForDuration holdDuration: TimeInterval
  ) {}
  open func swipeUp() {}
  open func swipeDown() {}
  open func swipeLeft() {}
  open func swipeRight() {}
  open func swipeUp(velocity: XCUIGestureVelocity) {}
  open func swipeDown(velocity: XCUIGestureVelocity) {}
  open func swipeLeft(velocity: XCUIGestureVelocity) {}
  open func swipeRight(velocity: XCUIGestureVelocity) {}
  open func pinch(withScale scale: CGFloat, velocity: CGFloat) {}
  open func rotate(_ rotation: CGFloat, withVelocity velocity: CGFloat) {}
  open func typeText(_ text: String) {}
  open func coordinate(withNormalizedOffset normalizedOffset: CGVector) -> XCUICoordinate { XCUICoordinate() }
  open func descendants(matching type: ElementType) -> XCUIElementQuery { XCUIElementQuery() }
  open func children(matching type: ElementType) -> XCUIElementQuery { XCUIElementQuery() }

  open var alerts: XCUIElementQuery { XCUIElementQuery() }
  open var buttons: XCUIElementQuery { XCUIElementQuery() }
  open var cells: XCUIElementQuery { XCUIElementQuery() }
  open var collectionViews: XCUIElementQuery { XCUIElementQuery() }
  open var images: XCUIElementQuery { XCUIElementQuery() }
  open var keyboards: XCUIElementQuery { XCUIElementQuery() }
  open var keys: XCUIElementQuery { XCUIElementQuery() }
  open var links: XCUIElementQuery { XCUIElementQuery() }
  open var menuItems: XCUIElementQuery { XCUIElementQuery() }
  open var navigationBars: XCUIElementQuery { XCUIElementQuery() }
  open var otherElements: XCUIElementQuery { XCUIElementQuery() }
  open var scrollViews: XCUIElementQuery { XCUIElementQuery() }
  open var searchFields: XCUIElementQuery { XCUIElementQuery() }
  open var secureTextFields: XCUIElementQuery { XCUIElementQuery() }
  open var sheets: XCUIElementQuery { XCUIElementQuery() }
  open var sliders: XCUIElementQuery { XCUIElementQuery() }
  open var staticTexts: XCUIElementQuery { XCUIElementQuery() }
  open var statusBars: XCUIElementQuery { XCUIElementQuery() }
  open var switches: XCUIElementQuery { XCUIElementQuery() }
  open var tables: XCUIElementQuery { XCUIElementQuery() }
  open var textFields: XCUIElementQuery { XCUIElementQuery() }
  open var textViews: XCUIElementQuery { XCUIElementQuery() }
  open var toolbars: XCUIElementQuery { XCUIElementQuery() }
  open var webViews: XCUIElementQuery { XCUIElementQuery() }
  open var windows: XCUIElementQuery { XCUIElementQuery() }
}

@MainActor
open class XCUIElementQuery: NSObject {
  open var element: XCUIElement { XCUIElement() }
  open var count: Int { 0 }
  open var firstMatch: XCUIElement { XCUIElement() }
  open var allElementsBoundByIndex: [XCUIElement] { [] }
  open var allElementsBoundByAccessibilityElement: [XCUIElement] { [] }
  open override var debugDescription: String { "" }
  open func element(boundBy index: Int) -> XCUIElement { XCUIElement() }
  open func element(matching predicate: NSPredicate) -> XCUIElement { XCUIElement() }
  open func element(matching elementType: XCUIElement.ElementType, identifier: String?) -> XCUIElement {
    XCUIElement()
  }
  open subscript(key: String) -> XCUIElement { XCUIElement() }
  open func matching(_ predicate: NSPredicate) -> XCUIElementQuery { self }
  open func matching(_ elementType: XCUIElement.ElementType, identifier: String?) -> XCUIElementQuery { self }
  open func matching(identifier: String) -> XCUIElementQuery { self }
  open func containing(_ predicate: NSPredicate) -> XCUIElementQuery { self }
  open func containing(_ elementType: XCUIElement.ElementType, identifier: String?) -> XCUIElementQuery { self }
  open func descendants(matching type: XCUIElement.ElementType) -> XCUIElementQuery { self }
  open func children(matching type: XCUIElement.ElementType) -> XCUIElementQuery { self }

  open var alerts: XCUIElementQuery { self }
  open var buttons: XCUIElementQuery { self }
  open var cells: XCUIElementQuery { self }
  open var images: XCUIElementQuery { self }
  open var keys: XCUIElementQuery { self }
  open var links: XCUIElementQuery { self }
  open var menuItems: XCUIElementQuery { self }
  open var otherElements: XCUIElementQuery { self }
  open var staticTexts: XCUIElementQuery { self }
  open var textFields: XCUIElementQuery { self }
  open var textViews: XCUIElementQuery { self }
}

@MainActor
open class XCUIApplication: XCUIElement {
  public enum State: UInt {
    case unknown = 0
    case notRunning = 1
    case runningBackgroundSuspended = 2
    case runningBackground = 3
    case runningForeground = 4
  }

  public override init() {}
  public init(bundleIdentifier: String) {}
  open var launchArguments: [String] = []
  open var launchEnvironment: [String: String] = [:]
  open var state: State { .notRunning }
  open func launch() {}
  open func activate() {}
  open func terminate() {}
  open func wait(for state: State, timeout: TimeInterval) -> Bool { false }
  open func open(_ url: URL) {}
}

/// NSPredicate(format:) is unavailable in swift-corelibs-foundation; `typecheck.sh` renames the calls to this function
public func StubPredicate(format predicateFormat: String, _ args: Any...) -> NSPredicate {
  NSPredicate(value: true)
}
