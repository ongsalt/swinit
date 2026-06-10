/// A handle to a running event loop integration.
///
/// Keep this value alive for as long as you want the event loop to run.
/// Drop it (or call `cancel()`) to stop platform integration.
///
/// On Win32, `cancel()` is a no-op because the message pump is blocking.
public final class Watch {
    private let onCancel: () -> Void
    public init(_ cancel: @escaping () -> Void) { onCancel = cancel }
    deinit { onCancel() }
    public func cancel() { onCancel() }
}
