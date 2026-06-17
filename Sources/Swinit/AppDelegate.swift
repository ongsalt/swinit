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
public protocol AppDelegate: AnyObject {
    /// The native surface is available. Create all windows here.
    /// On desktop this fires once at startup; on Android it may fire multiple times.
    func canCreateSurfaces(_ app: App)

    /// A window event arrived. Per-window `onEvent` fires first, then this.
    func windowEvent(_ app: App, window: Window, event: WindowEvent)

    /// Drop all GPU surfaces (wgpu::Surface, EGLSurface, VkSurfaceKHR…) before returning.
    /// The OS will destroy the underlying native window immediately after this returns.
    func destroySurfaces(_ app: App)

    /// App became logically active (foregrounded). GPU surfaces are still valid here.
    func appResumed(_ app: App)

    /// App became logically inactive (backgrounded). GPU surfaces are still valid here.
    func appSuspended(_ app: App)

    /// Event batch complete; loop is about to sleep. Good place to submit frames in game loops.
    func aboutToWait(_ app: App)

    /// Low-memory warning from the OS (Android / iOS).
    func memoryWarning(_ app: App)
}

extension AppDelegate {
    public func destroySurfaces(_ app: App) {}
    public func appResumed(_ app: App) {}
    public func appSuspended(_ app: App) {}
    public func aboutToWait(_ app: App) {}
    public func memoryWarning(_ app: App) {}
}
