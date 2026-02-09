public enum ControlFlow {
  case poll  // window (for now)
  case wait  // wayland, TODO: checkout winui
  // case waitUntil(ContinuousClock.Instant)
}

protocol IEventLoop {
  func sendWindowEvent(_ event: WindowEvent, to: WindowId)
  // func createProxy() -> IEventLoopProxy
  func run(_ handler: some Responder)
}

// The window is closed when dropped.
public protocol IWindow {
  func requestRedraw()
  func focus()
  func prePresentNotify()  // wayland only

  // func drag()
}

extension IWindow {
  public func prePresentNotify() {}
}
