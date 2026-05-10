public struct WindowAttributes {
  public var title: String
  public var transparency: Bool

  #if os(Windows)
  public var noRedirectionBitmap: Bool

  public init(title: String = "swinit_window", noRedirectionBitmap: Bool = false, transparency: Bool = false) {
    self.title = title
    self.noRedirectionBitmap = noRedirectionBitmap
    self.transparency = transparency
  }
  #else
  public init(title: String = "swinit_window", transparency: Bool = false) {
    self.title = title
    self.transparency = transparency
  }
  #endif
}