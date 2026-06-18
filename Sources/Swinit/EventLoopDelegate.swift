import SwinitCore

/// Application lifecycle callbacks. All methods run on the main actor.
///
/// Lifecycle order on desktop (Linux / Windows):
///   `canCreateSurfaces` → `appResumed` → [event loop] → `exiting`
///
/// On Android/iOS, `canCreateSurfaces`/`appSuspended` and `appResumed`/`appSuspended`
/// may fire multiple times per session as the native window is created and destroyed by the OS.
@MainActor
public protocol EventLoopDelegate: AnyObject {
    /// The native surface is available. Create all windows here.
    /// On desktop this fires once at startup; on Android it may fire multiple times.
    func canCreateSurfaces(_ eventLoop: EventLoop)

    /// A window event arrived.
    func windowEvent(_ eventLoop: EventLoop, window: Window, event: WindowEvent)

    /// App became logically active (foregrounded). GPU surfaces are valid here.
    func appResumed(_ eventLoop: EventLoop)

    /// App became logically inactive (backgrounded).
    /// Drop all GPU surfaces (wgpu::Surface, EGLSurface, VkSurfaceKHR…) before returning —
    /// the OS may destroy the underlying native window immediately after this returns.
    func appSuspended(_ eventLoop: EventLoop)

    /// Event batch complete; loop is about to sleep. Good place to submit frames in game loops.
    func aboutToWait(_ eventLoop: EventLoop)

    /// Event loop is permanently exiting. Called once at shutdown.
    func exiting(_ eventLoop: EventLoop)

    /// Low-memory warning from the OS (Android / iOS).
    func memoryWarning(_ eventLoop: EventLoop)
}

extension EventLoopDelegate {
    public func appResumed(_ eventLoop: EventLoop) {}
    public func appSuspended(_ eventLoop: EventLoop) {}
    public func aboutToWait(_ eventLoop: EventLoop) {}
    public func exiting(_ eventLoop: EventLoop) {}
    public func memoryWarning(_ eventLoop: EventLoop) {}
}
