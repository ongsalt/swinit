/// Cross-platform window protocol.
///
/// Windows are RAII: the underlying platform window is destroyed when the last
/// Swift reference is dropped (`deinit`). Close by nilling your stored reference.
@MainActor
public protocol WindowProtocol: AnyObject {
    var size: SIMD2<UInt> { get set }
    var title: String { get set }
    func requestRedraw()
    func focus()
    /// Wayland only: register a frame callback before presenting. No-op on other platforms.
    func prePresentNotify()
}

extension WindowProtocol {
    public func prePresentNotify() {}
}
