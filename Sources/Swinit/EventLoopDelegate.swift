import SwinitCore

/// Application lifecycle callbacks. All methods run on the main actor.
///
/// Lifecycle order on all platforms:
///   `canCreateSurfaces` → `appResumed` → [event loop] → `appSuspended` → `destroySurfaces`
///
/// On Android/iOS, `canCreateSurfaces` and `destroySurfaces` may fire multiple times per session
/// (each time the native surface is created/destroyed by the OS). Design your GPU resource
/// management around these two calls, not around `appResumed`/`appSuspended`.
@MainActor
public protocol EventLoopDelegate: AnyObject {
    /// The native surface is available. Create all windows here.
    /// On desktop this fires once at startup; on Android it may fire multiple times.
    func canCreateSurfaces(_ eventLoop: EventLoop)

    /// A window event arrived. Per-window `onEvent` fires first, then this.
    func windowEvent(_ eventLoop: EventLoop, window: Window, event: WindowEvent)

    /// Drop all GPU surfaces (wgpu::Surface, EGLSurface, VkSurfaceKHR…) before returning.
    /// The OS will destroy the underlying native window immediately after this returns.
    func destroySurfaces(_ eventLoop: EventLoop)

    /// App became logically active (foregrounded). GPU surfaces are still valid here.
    func appResumed(_ eventLoop: EventLoop)

    /// App became logically inactive (backgrounded). GPU surfaces are still valid here.
    func appSuspended(_ eventLoop: EventLoop)

    /// Event batch complete; loop is about to sleep. Good place to submit frames in game loops.
    func aboutToWait(_ eventLoop: EventLoop)

    /// Low-memory warning from the OS (Android / iOS).
    func memoryWarning(_ eventLoop: EventLoop)
}

extension EventLoopDelegate {
    public func destroySurfaces(_ eventLoop: EventLoop) {}
    public func appResumed(_ eventLoop: EventLoop) {}
    public func appSuspended(_ eventLoop: EventLoop) {}
    public func aboutToWait(_ eventLoop: EventLoop) {}
    public func memoryWarning(_ eventLoop: EventLoop) {}
}
