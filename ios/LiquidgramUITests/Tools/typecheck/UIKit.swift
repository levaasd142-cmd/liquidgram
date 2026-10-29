// Stand-in for the parts of UIKit and CoreGraphics that the UI tests use, with the SDK's signatures, so the tests
// type-check on Linux with `typecheck.sh`. Foundation on Linux has CGFloat, CGPoint, CGSize and CGRect; the bodies do
// nothing.
@_exported import Foundation

public struct CGVector: Equatable {
  public var dx: CGFloat
  public var dy: CGFloat
  public init(dx: CGFloat, dy: CGFloat) {
    self.dx = dx
    self.dy = dy
  }
  public init(dx: Double, dy: Double) {
    self.dx = CGFloat(dx)
    self.dy = CGFloat(dy)
  }
  public static var zero: CGVector { CGVector(dx: CGFloat(0), dy: CGFloat(0)) }
}

public final class CGImage {
  public var width: Int { 0 }
  public var height: Int { 0 }
  public func cropping(to rect: CGRect) -> CGImage? { nil }
}

public final class CGColorSpace {
  public static let sRGB = "kCGColorSpaceSRGB"
  public init?(name: String) {}
}

public enum CGImageAlphaInfo: UInt32 {
  case none = 0
  case premultipliedLast = 1
  case premultipliedFirst = 2
  case last = 3
  case first = 4
  case noneSkipLast = 5
  case noneSkipFirst = 6
  case alphaOnly = 7
}

public final class CGContext {
  public init?(
    data: UnsafeMutableRawPointer?,
    width: Int,
    height: Int,
    bitsPerComponent: Int,
    bytesPerRow: Int,
    space: CGColorSpace,
    bitmapInfo: UInt32
  ) {}
  public func draw(_ image: CGImage, in rect: CGRect, byTiling: Bool = false) {}
}

open class UIImage: NSObject {
  open var cgImage: CGImage? { nil }
  open var scale: CGFloat { 1 }
  open var size: CGSize { .zero }
}

public enum UIDeviceOrientation: Int {
  case unknown = 0
  case portrait = 1
  case portraitUpsideDown = 2
  case landscapeLeft = 3
  case landscapeRight = 4
  case faceUp = 5
  case faceDown = 6
}

public enum UIUserInterfaceIdiom: Int {
  case unspecified = -1
  case phone = 0
  case pad = 1
  case tv = 2
  case carPlay = 3
  case mac = 5
  case vision = 6
}

@MainActor
open class UIDevice: NSObject {
  open class var current: UIDevice { UIDevice() }
  open var userInterfaceIdiom: UIUserInterfaceIdiom { .phone }
  open var orientation: UIDeviceOrientation { .portrait }
  open var systemVersion: String { "" }
}
