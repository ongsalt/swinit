public struct WindowAttributes {
  public var title: String
  public var transparency: Bool
  public var size: SIMD2<UInt>

  #if os(Windows)
  public var noRedirectionBitmap: Bool

  public init(title: String = "swinit_window", noRedirectionBitmap: Bool = false, transparency: Bool = false, size: SIMD2<UInt> = [800, 600]) {
    self.title = title
    self.noRedirectionBitmap = noRedirectionBitmap
    self.transparency = transparency
    self.size = size
  }
  #else
  public init(title: String = "swinit_window", transparency: Bool = false, size: SIMD2<UInt> = [800, 600]) {
    self.title = title
    self.transparency = transparency
    self.size = size
  }
  #endif
}