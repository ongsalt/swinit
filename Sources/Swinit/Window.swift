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
    weak var eventLoop: EventLoop?
    var _title: String
    var _size: Size
    var _scaleFactor: Double = 1.0

    // MARK: Platform stored properties — implementations in Window+<Platform>.swift

#if os(Linux)
    public internal(set) var surface: WlSurface
    public internal(set) var display: WlDisplay
    var xdgSurface: XdgSurface
    var toplevel: XdgToplevel
    let decoMode: DecorationMode
    var toplevelDeco: ZxdgToplevelDecorationV1?
    var pendingDecoMode: ZxdgToplevelDecorationV1.Mode?
    var pendingToplevelSize: Size = .zero
    var pendingIsMaximized = false
    var pendingIsActivated = true
    var configured = false
    var isMaximized = false
    var isActivated = true
    var pendingFrameCallback = false
    var fractionalScale: WpFractionalScaleV1?
    var opaqueRegion: Bool
    var inputRegion: Bool
    #if WaylandCSD
    var csd: CSDLayer?
    #endif

    init(id: WindowId, eventLoop: EventLoop, attributes: WindowAttributes,
         surface: WlSurface, xdgSurface: XdgSurface, toplevel: XdgToplevel) {
        self.id         = id
        self.eventLoop  = eventLoop
        self.surface    = surface
        self.display    = eventLoop.waylandDisplay
        self.xdgSurface = xdgSurface
        self.toplevel   = toplevel
        self._title       = attributes.title
        self._size        = attributes.size
        self.decoMode     = attributes.decorations
        self.opaqueRegion = attributes.opaqueRegion
        self.inputRegion  = attributes.inputRegion
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
    var _pendingRedraw = false
    var dmanip: OpaquePointer?  // CDManipController* (touchpad gestures)

    init(id: WindowId, eventLoop: EventLoop, attributes: WindowAttributes) {
        self.id        = id
        self.eventLoop = eventLoop
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
    public var scaleFactor: Double { _scaleFactor }

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
        eventLoop?.removeWindow(id: id)
    }

    func dispatch(_ event: WindowEvent) {
        if let eventLoop { eventLoop.delegate?.windowEvent(eventLoop, window: self, event: event) }
    }

    deinit {
        guard !isClosed else { return }
        MainActor.assumeIsolated { platformDestroy() }
    }
}
