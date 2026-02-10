public enum ControlFlow {
  case poll  // window (for now)
  case wait  // wayland, TODO: checkout winui
  // case waitUntil(ContinuousClock.Instant)
}

public protocol IEventLoop {
  associatedtype Window: IWindow

  func sendWindowEvent(_ event: WindowEvent, to: WindowId)
  // func createProxy() -> IEventLoopProxy
  func run<R>(_ handler: R) where R: Responder, R.EventLoop == Self

  func createWindow(title: String) -> Window
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
