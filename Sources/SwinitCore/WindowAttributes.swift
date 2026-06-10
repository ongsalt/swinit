/// Whether and how to decorate a window. Wayland only — Win32 always uses
/// system chrome (DWM). The default is `.auto`.
public enum DecorationMode: Sendable {
    /// Try server-side decorations; fall back to client-side if the compositor
    /// does not support the xdg-decoration protocol.
    case auto
    /// Always draw client-side decorations regardless of compositor support.
    case clientSide
    /// Create a borderless window with no decorations or shadow.
    case none
}

public struct WindowAttributes {
    public var title: String
    public var transparency: Bool
    public var size: SIMD2<UInt>
    /// Decoration mode (Wayland only; ignored on other platforms).
    public var decorations: DecorationMode

    #if os(Windows)
    public var noRedirectionBitmap: Bool

    public init(title: String = "swinit_window", noRedirectionBitmap: Bool = false, transparency: Bool = false, size: SIMD2<UInt> = [800, 600], decorations: DecorationMode = .auto) {
        self.title = title
        self.noRedirectionBitmap = noRedirectionBitmap
        self.transparency = transparency
        self.size = size
        self.decorations = decorations
    }
    #else
    public init(title: String = "swinit_window", transparency: Bool = false, size: SIMD2<UInt> = [800, 600], decorations: DecorationMode = .auto) {
        self.title = title
        self.transparency = transparency
        self.size = size
        self.decorations = decorations
    }
    #endif
}