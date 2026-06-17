public final class Watch {
    private var cancelled = false
    private let onCancel: () -> Void

    public init(_ cancel: @escaping () -> Void) { onCancel = cancel }
    deinit { performCancel() }
    public func cancel() { performCancel() }

    private func performCancel() {
        guard !cancelled else { return }
        cancelled = true
        onCancel()
    }
}
