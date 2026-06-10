import Foundation
import Dispatch

/// Controls how the event loop drives execution.
public enum ControlFlow {
    /// Game-loop style: poll for events continuously (PeekMessage / busy-loop).
    case poll

    /// Platform-native wait: sleep until an event arrives (GetMessage / wl_display_dispatch).
    case platform

    /// Defaults to `.platform`.
    case `default`

    // `.swift` has been removed: `attach()` is now the canonical way for callers
    // that want to own the RunLoop. On Win32 this is still blocking (see EventLoop docs).
}
