this is like 99% vibecode, except for platform eventloop

## External Dependencies

### Linux
- cairo for csd

## Event Loop Delegate

```swift
public protocol EventLoopDelegate: AnyObject {
    func canCreateSurfaces(_ eventLoop: EventLoop)   // create windows here
    func windowEvent(_ eventLoop: EventLoop, window: Window, event: WindowEvent)
    func appResumed(_ eventLoop: EventLoop)
    func appSuspended(_ eventLoop: EventLoop)
    func aboutToWait(_ eventLoop: EventLoop)         // end of event batch, before sleep — submit frames here
    func exiting(_ eventLoop: EventLoop)
    func memoryWarning(_ eventLoop: EventLoop)
}
```

All methods except `canCreateSurfaces` and `windowEvent` have default no-op implementations.

## Window Events

```swift
enum WindowEvent {
    case resized(size: Size, isFinal: Bool)   // Size is physical pixels
    case moved(PhysicalPosition<Int32>)
    case closeRequested
    case destroyed
    case focused(Bool)
    case stateChanged(WindowState)
    case keyboardInput(deviceId: DeviceId, event: KeyEvent, isSynthetic: Bool)
    case modifiersChanged(Modifiers)
    case cursorMoved(deviceId: DeviceId, position: PhysicalPosition<Double>)
    case cursorEntered(deviceId: DeviceId)
    case cursorLeft(deviceId: DeviceId)
    case mouseWheel(deviceId: DeviceId, delta: MouseScrollDelta, phase: TouchPhase)
    case mouseInput(deviceId: DeviceId, state: ElementState, button: MouseButton)
    case redrawRequested
    case scaleFactorChanged(scaleFactor: Double)
}
```

## DPI / Scale Factor

`Window.scaleFactor` is a `Double` representing physical pixels per logical pixel (e.g. `2.0` on a HiDPI display). All sizes reported by the library are in physical pixels; divide by `scaleFactor` to get logical units.

- **Win32**: set at window creation via `GetDpiForWindow`; updated via `WM_DPICHANGED`. When the scale changes the window is automatically resized to the OS-suggested rect, so `.scaleFactorChanged` fires before the resulting `.resized`.
- **Wayland**: uses `wp_fractional_scale_v1` if the compositor supports it (scale = `preferredScale / 120`), otherwise falls back to `wl_surface.preferredBufferScale` (integer).

## Redraw Model

Call `window.requestRedraw()` to schedule a redraw. The `.redrawRequested` event fires at the end of the current event batch (in `aboutToWait`), after all input events for that cycle have been dispatched.

- **Win32**: uses a per-window pending flag; flushed just after `aboutToWait` fires each poll cycle. `WM_PAINT` still fires for OS-initiated repaints (window uncovered, etc.).
- **Wayland**: uses `wl_surface.frame` callbacks, paced by the compositor. Call `prePresentNotify()` before attaching your buffer to register the next frame callback without an extra commit.

`aboutToWait` fires on both platforms just before the event loop sleeps, making it the right place for game-loop frame submission.
