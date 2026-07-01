/// Whether and how to decorate a window. Wayland only — Win32 always uses system chrome.
public enum DecorationMode: Sendable {
    /// Try server-side decorations; fall back to client-side if the compositor doesn't support
    /// xdg-decoration. This is the default.
    case auto
    /// Always draw client-side decorations.
    case clientSide
    /// Borderless window, no decorations.
    case none
}

public struct WindowAttributes: Sendable {
    public var title: String
    public var size: Size
    public var transparency: Bool
    /// Decoration mode. Wayland only; ignored on Win32 (system chrome always used).
    public var decorations: DecorationMode
    /// Win32 only: WS_EX_NOREDIRECTIONBITMAP. Ignored on other platforms.
    public var noRedirectionBitmap: Bool
    /// Wayland only: tell the compositor that the entire surface is opaque. Lets the
    /// compositor skip blending content underneath. Default false.
    public var opaqueRegion: Bool
    /// Wayland only: restrict pointer/touch input to the window rect. Default false.
    public var inputRegion: Bool

    public init(
        title: String = "swinit",
        size: Size = .init(width: 800, height: 600),
        transparency: Bool = false,
        decorations: DecorationMode = .auto,
        noRedirectionBitmap: Bool = false,
        opaqueRegion: Bool = false,
        inputRegion: Bool = true
    ) {
        self.title = title
        self.size = size
        self.transparency = transparency
        self.decorations = decorations
        self.noRedirectionBitmap = noRedirectionBitmap
        self.opaqueRegion = opaqueRegion
        self.inputRegion = inputRegion
    }
}
