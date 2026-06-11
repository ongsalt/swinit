import SwiftWayland
import WaylandProtocols
import SwinitCore

@MainActor
public final class Window: SwinitCore.WindowProtocol {
    // Raw surface exposed for third-party renderers (Vulkan/EGL/wgpu)
    public private(set) var surface: WlSurface
    public private(set) var display: WlDisplay

    private var xdgSurface: XdgSurface
    private var toplevel: XdgToplevel
    private unowned let eventLoop: EventLoop

    private var _size: SIMD2<UInt>
    private var _title: String
    private var pendingToplevelSize: SIMD2<UInt> = .zero
    private var pendingIsMaximized = false
    private var configured = false

    // Decoration state
    private let decoMode: DecorationMode
    private var toplevelDeco: ZxdgToplevelDecorationV1? = nil
    // Deferred: set by the decoration.configure event, consumed in xdgSurface.configure
    private var pendingDecoMode: ZxdgToplevelDecorationV1.Mode? = nil
    private var csd: CSDLayer? = nil
    private var isMaximized = false
    private var isActivated = true

    init(
        eventLoop: EventLoop,
        attributes: WindowAttributes,
        surface: WlSurface,
        xdgSurface: XdgSurface,
        toplevel: XdgToplevel
    ) {
        self.eventLoop  = eventLoop
        self.surface    = surface
        self.display    = eventLoop.connection.display
        self.xdgSurface = xdgSurface
        self.toplevel   = toplevel
        self._size      = attributes.size
        self._title     = attributes.title
        self.decoMode   = attributes.decorations

        try? toplevel.setTitle(attributes.title)
        setupCallbacks()
        setupDecorations()
        try? surface.commit()
    }

    // MARK: - WindowProtocol

    public var size: SIMD2<UInt> {
        get { _size }
        set { _size = newValue }
    }

    public var title: String {
        get { _title }
        set {
            _title = newValue
            try? toplevel.setTitle(newValue)
            if let csd, let shm = eventLoop.shm {
                try? csd.update(shm: shm, contentSize: _size, title: newValue,
                                maximized: isMaximized, activated: isActivated)
                try? surface.commit()
            }
        }
    }

    public func requestRedraw() {
        try? surface.damage(x: 0, y: 0, width: Int32(_size.x), height: Int32(_size.y))
        try? surface.commit()
    }

    public func focus() {}

    public func prePresentNotify() {
        try? surface.frame { _ in }
    }

    // MARK: - Internal API

    /// Called by EventLoop's keyboard focus tracking to redraw inactive decorations.
    func setActivated(_ active: Bool) {
        guard active != isActivated, let csd, let shm = eventLoop.shm else { return }
        isActivated = active
        try? csd.update(shm: shm, contentSize: _size, title: _title, maximized: isMaximized, activated: active)
        try? surface.commit()
    }

    /// Dispatch a CSD pointer-press interaction (move, resize, button click).
    func handleCSDPress(area: CSDArea, x: Double, y: Double, seat: WlSeat, serial: UInt32) {
        switch area {
        case .titleBar:
            guard let csd else { return }
            let r = csd.buttonRadius
            func hit(_ c: SIMD2<Double>) -> Bool { let dx = x-c.x; let dy = y-c.y; return dx*dx+dy*dy <= r*r }
            if      hit(csd.closeCenter)    { eventLoop.dispatch(.closeRequested, from: self) }
            else if hit(csd.minimizeCenter) { try? toplevel.setMinimized() }
            else if hit(csd.maximizeCenter) {
                if isMaximized { try? toplevel.unsetMaximized() }
                else           { try? toplevel.setMaximized()   }
            } else {
                try? toplevel.move(seat: seat, serial: serial)
            }

        case .borderLeft:
            try? toplevel.resize(seat: seat, serial: serial, edges: .left)
        case .borderRight:
            try? toplevel.resize(seat: seat, serial: serial, edges: .right)
        case .borderBottom:
            let bW = Double(CSDConstants.borderWidth)
            let cW = Double(_size.x)
            let zone = 20.0
            if      x < bW + zone       { try? toplevel.resize(seat: seat, serial: serial, edges: .bottomLeft)  }
            else if x > bW + cW - zone  { try? toplevel.resize(seat: seat, serial: serial, edges: .bottomRight) }
            else                        { try? toplevel.resize(seat: seat, serial: serial, edges: .bottom)       }
        }
    }

    // MARK: - Private: callbacks

    private func setupCallbacks() {
        toplevel.onEvent = { [weak self] event in
            guard let self else { return }
            switch event {
            case .configure(let width, let height, let states):
                let newMax = csdParseStates(states).contains(1)   // xdg_toplevel_state.maximized = 1
                pendingToplevelSize = (width > 0 && height > 0)
                    ? SIMD2<UInt>(UInt(width), UInt(height)) : .zero
                pendingIsMaximized = newMax
            case .close:
                eventLoop.dispatch(.closeRequested, from: self)
            default: break
            }
        }

        xdgSurface.onEvent = { [weak self] event in
            guard let self, case .configure(let serial) = event else { return }

            let prevMaximized = isMaximized
            isMaximized = pendingIsMaximized
            let newSize   = pendingToplevelSize == .zero ? _size : pendingToplevelSize
            let isInitial = !configured
            configured = true

            // Handle decoration mode decided by compositor in this configure round-trip
            if let mode = pendingDecoMode {
                pendingDecoMode = nil
                if mode == .clientSide { ensureCSD() }
                else                  { destroyCSD() }
            }

            // Update CSD subsurfaces (before ack so they're queued with the parent commit)
            if let csd, let shm = eventLoop.shm,
               newSize != _size || isMaximized != prevMaximized || isInitial {
                try? csd.update(shm: shm, contentSize: newSize, title: _title,
                                maximized: isMaximized, activated: isActivated)
            }

            // Tell the compositor the "window" bounds (excludes shadow, includes decorations)
            if csd != nil {
                let bW = isMaximized ? Int32(0) : CSDConstants.borderWidth
                let tH = CSDConstants.titleBarHeight
                let bot = isMaximized ? Int32(0) : CSDConstants.borderWidth
                try? xdgSurface.setWindowGeometry(
                    x: -bW, y: -tH,
                    width:  Int32(newSize.x) + 2 * bW,
                    height: Int32(newSize.y) + tH + bot)
            }

            try? xdgSurface.ackConfigure(serial: serial)

            let sizeChanged = newSize != _size || isInitial
            if sizeChanged { _size = newSize }

            if isMaximized != prevMaximized {
                eventLoop.dispatch(.stateChanged(isMaximized ? .maximized : .normal), from: self)
            }
            if sizeChanged {
                let phys = PhysicalSize(width: UInt32(newSize.x), height: UInt32(newSize.y))
                eventLoop.dispatch(.resized(size: phys, isFinal: true), from: self)
            }

            try? surface.commit()
        }
    }

    // MARK: - Private: decoration negotiation

    private func setupDecorations() {
        guard decoMode != .none else { return }

        if let decoManager = eventLoop.decoManager {
            guard let deco = try? decoManager.getToplevelDecoration(toplevel: toplevel) else { return }
            toplevelDeco = deco

            // Store the mode in pendingDecoMode; actual CSD setup is deferred to
            // xdgSurface.configure so both events land before we ack.
            deco.onEvent = { [weak self] event in
                guard let self, case .configure(let mode) = event else { return }
                self.pendingDecoMode = mode
            }

            try? deco.setMode(decoMode == .clientSide ? .clientSide : .serverSide)
        } else {
            // Compositor has no xdg-decoration support — create CSD immediately.
            // The subsurface commits are queued in sync mode; the final commit at
            // the bottom of init() flushes them together with the initial surface commit.
            ensureCSD()
        }
    }

    /// Creates the CSD layer and registers its surfaces for pointer routing.
    /// Does NOT commit the parent surface — callers are responsible.
    private func ensureCSD() {
        guard csd == nil,
              let subcompositor = eventLoop.subcompositor,
              let shm = eventLoop.shm,
              let compositor = eventLoop.compositor
        else { return }

        guard let layer = try? CSDLayer(
            compositor: compositor, subcompositor: subcompositor,
            shm: shm, parentSurface: surface, contentSize: _size)
        else { return }

        csd = layer
        eventLoop.csdRouter.register(window: self, csd: layer)

        // Set initial geometry (takes effect on next parent commit)
        let bW = CSDConstants.borderWidth
        let tH = CSDConstants.titleBarHeight
        try? xdgSurface.setWindowGeometry(
            x: -bW, y: -tH,
            width:  Int32(_size.x) + 2 * bW,
            height: Int32(_size.y) + tH + bW)
    }

    private func destroyCSD() {
        guard csd != nil else { return }
        eventLoop.csdRouter.unregister(window: self)
        csd = nil
        // Reset geometry to content-only bounds
        try? xdgSurface.setWindowGeometry(
            x: 0, y: 0,
            width: Int32(_size.x), height: Int32(_size.y))
    }

    deinit {
        eventLoop.unregisterWindow(surface.id)
        eventLoop.csdRouter.unregister(window: self)
        try? toplevelDeco?.destroy()
        try? toplevel.destroy()
        try? xdgSurface.destroy()
        try? surface.destroy()
    }
}

// MARK: - Helpers

/// Parses the xdg_toplevel_state array from a configure event payload.
/// States are packed uint32 values in native byte order.
private func csdParseStates(_ data: Data) -> Set<UInt32> {
    var result = Set<UInt32>()
    data.withUnsafeBytes { raw in
        let count = raw.count / MemoryLayout<UInt32>.size
        for i in 0..<count {
            result.insert(raw.load(fromByteOffset: i * 4, as: UInt32.self))
        }
    }
    return result
}
