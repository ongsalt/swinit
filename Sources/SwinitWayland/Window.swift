import SwiftWayland
import WaylandProtocols
import SwinitCore

/// NO CSD support yet — surfaces stay unmapped until a renderer (Vulkan/EGL/wgpu)
/// attaches a buffer via the exposed `surface` property.
@MainActor
public final class Window: SwinitCore.WindowProtocol {
    public private(set) var surface: WlSurface
    public private(set) var display: WlDisplay

    private var xdgSurface: XdgSurface
    private var toplevel: XdgToplevel
    private unowned let eventLoop: EventLoop

    private var _size: SIMD2<UInt>
    private var _title: String
    private var pendingToplevelSize: SIMD2<UInt> = .zero
    private var configured = false

    init(
        eventLoop: EventLoop,
        attributes: WindowAttributes,
        surface: WlSurface,
        xdgSurface: XdgSurface,
        toplevel: XdgToplevel
    ) {
        self.eventLoop = eventLoop
        self.surface = surface
        self.display = eventLoop.connection.display
        self.xdgSurface = xdgSurface
        self.toplevel = toplevel
        self._size = attributes.size
        self._title = attributes.title

        try? toplevel.setTitle(attributes.title)
        setupCallbacks()
        try? surface.commit()
    }

    public var size: SIMD2<UInt> {
        get { _size }
        set { _size = newValue }
    }

    public var title: String {
        get { _title }
        set {
            _title = newValue
            try? toplevel.setTitle(newValue)
        }
    }

    private func setupCallbacks() {
        toplevel.onEvent = { [weak self] event in
            guard let self else { return }
            switch event {
            case .configure(let width, let height, _):
                pendingToplevelSize = width > 0 && height > 0
                    ? SIMD2<UInt>(UInt(width), UInt(height)) : .zero
            case .close:
                eventLoop.dispatch(.closeRequested, from: self)
            default: break
            }
        }

        xdgSurface.onEvent = { [weak self] event in
            guard let self, case .configure(let serial) = event else { return }
            try? xdgSurface.ackConfigure(serial: serial)

            let newSize = pendingToplevelSize == .zero ? _size : pendingToplevelSize
            let isInitial = !configured
            configured = true

            if newSize != _size || isInitial {
                _size = newSize
                let physSize = PhysicalSize(width: UInt32(newSize.x), height: UInt32(newSize.y))
                eventLoop.dispatch(.resized(size: physSize, isFinal: true), from: self)
            }

            try? surface.commit()
        }
    }

    deinit {
        eventLoop.unregisterWindow(surface.id)
        try? toplevel.destroy()
        try? xdgSurface.destroy()
        try? surface.destroy()
    }
}

extension Window {
    public func requestRedraw() {
        try? surface.damage(x: 0, y: 0, width: Int32(_size.x), height: Int32(_size.y))
        try? surface.commit()
    }

    public func focus() {}

    public func prePresentNotify() {
        try? surface.frame { _ in }
    }
}
