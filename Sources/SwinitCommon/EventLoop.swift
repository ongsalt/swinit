// The window is closed when dropped.

public protocol IEventLoop {
  associatedtype Window: IWindow

  func sendWindowEvent(_ event: WindowEvent, to: WindowId)
  // func createProxy() -> IEventLoopProxy
  func run<R>(_ handler: R) where R: Responder, R.EventLoop == Self

  func stop()

  func createWindow(attributes: WindowAttributes) -> Window
}
public protocol IWindow {
  var size: SIMD2<UInt> { get set }
  func requestRedraw()
  func focus()
  func prePresentNotify()  // wayland only
  // func show()
  // func drag()
}

extension IWindow {
  public func prePresentNotify() {}
}

