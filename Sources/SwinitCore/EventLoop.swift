import Foundation

/// Cross-platform event loop protocol.
///
/// Platform notes for `attach()`:
///   - **Wayland** — non-blocking; returns immediately. Caller calls `RunLoop.main.run()`.
///   - **Win32** — blocks the calling thread. The Win32 message pump must stay on the
///     window-creation thread and cannot be integrated into Foundation's `RunLoop`
///     (CoreFoundation is not exported on Swift/Windows). `Watch.cancel()` is a no-op;
///     use `stop()` to exit the loop.
///   - **macOS** — planned; will integrate with `NSRunLoop`.
///   - **iOS / Android** — not supported.
@MainActor
public protocol EventLoopProtocol: AnyObject {
    associatedtype Window: WindowProtocol

    func createWindow(attributes: WindowAttributes) -> Window

    @discardableResult
    func attach<R: Responder>(_ responder: R) -> Watch where R.EventLoop == Self

    func stop()
}

extension EventLoopProtocol {
    public func run<R: Responder>(_ responder: R) where R.EventLoop == Self {
        let watch = attach(responder)
        RunLoop.main.run()
        watch.cancel()
    }
}
