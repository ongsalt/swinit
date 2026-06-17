import SwinitCore

#if os(Linux)
import WaylandClient
import WaylandClientProtocols
import SwinitWayland
#elseif os(Windows)
import WinSDK
import SwinitWin32
#endif

@MainActor
public final class Window {
    public let id: WindowId
    public private(set) var isClosed = false
    weak var app: App?
    public var onEvent: (@MainActor (WindowEvent) -> Void)?
    var _title: String
    var _size: Size

    // MARK: Platform stored properties — implementations in Window+<Platform>.swift

#if os(Linux)
    public internal(set) var surface: WlSurface
    public internal(set) var display: WlDisplay
    var xdgSurface: XdgSurface
    var toplevel: XdgToplevel
    let decoMode: DecorationMode
    var toplevelDeco: ZxdgToplevelDecorationV1?
    var pendingDecoMode: ZxdgToplevelDecorationV1.Mode?
    var csd: CSDLayer?
    var pendingToplevelSize: Size = .zero
    var pendingIsMaximized = false
    var configured = false
    var isMaximized = false
    var isActivated = true

    init(id: WindowId, app: App, attributes: WindowAttributes,
         surface: WlSurface, xdgSurface: XdgSurface, toplevel: XdgToplevel) {
        self.id         = id
        self.app        = app
        self.surface    = surface
        self.display    = app.waylandDisplay
        self.xdgSurface = xdgSurface
        self.toplevel   = toplevel
        self._title     = attributes.title
        self._size      = attributes.size
        self.decoMode   = attributes.decorations
        try? toplevel.setTitle(attributes.title)
        setupCallbacks()
        setupDecorations()
        try? surface.commit()
    }

#elseif os(Windows)
    public nonisolated(unsafe) internal(set) var handle: HWND!
    public nonisolated(unsafe) internal(set) var hInstance: HINSTANCE!
    var _drawUnderTitleBar: Bool = false
    var _backdropStyle: WindowsBackdropStyle = .auto
    var _titleBarAppearance: TitleBarAppearance = .system
    var isResizing = false
    var currentHeartbeatTimer: UInt64?

    init(id: WindowId, app: App, attributes: WindowAttributes) {
        self.id    = id
        self.app   = app
        self._title = attributes.title
        self._size  = attributes.size
        setupWin32Platform(attributes: attributes)
    }

#endif

    // MARK: Common interface

    public var title: String {
        get { _title }
        set {
            _title = newValue
            guard !isClosed else { return }
            platformSetTitle(newValue)
        }
    }

    public var size: Size { _size }

    public func requestRedraw() {
        guard !isClosed else { return }
        platformRequestRedraw()
    }

    public func requestResize(to size: Size) {
        guard !isClosed else { return }
        platformRequestResize(to: size)
    }

    public func focus() {
        guard !isClosed else { return }
        platformFocus()
    }

    public func close() {
        guard !isClosed else { return }
        isClosed = true
        dispatch(.destroyed)
        platformDestroy()
        app?.removeWindow(id: id)
    }

    func dispatch(_ event: WindowEvent) {
        onEvent?(event)
        if let app { app.delegate?.windowEvent(app, window: self, event: event) }
    }

    deinit {
        guard !isClosed else { return }
        MainActor.assumeIsolated { platformDestroy() }
    }
}
