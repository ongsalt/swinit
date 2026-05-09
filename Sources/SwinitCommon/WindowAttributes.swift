public struct WindowAttributes {
  public var title: String

  #if os(Windows)
  public var windowClass: String
  public var noRedirectionBitmap: Bool

  public init(title: String = "swinit_window", windowClass: String = "swinit_window", noRedirectionBitmap: Bool = true) {
    self.title = title
    self.windowClass = windowClass
    self.noRedirectionBitmap = noRedirectionBitmap
  }
  #else
  public init(title: String = "swinit_window") {
    self.title = title
  }
  #endif
}