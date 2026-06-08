import SwiftWayland
import WaylandProtocols
import SwinitCommon

/// NO GNOME SUPPORT. CSD is not yet implemented.
///
/// The surface is not mapped until the user's rendering API (Vulkan, EGL, etc.)
/// attaches a buffer via the exposed `surface`.
public final class WaylandWindow: Identifiable {
    public typealias ID = WindowId
    public let id: WindowId = WindowId()

    public private(set) var surface: WlSurface
    public private(set) var display: WlDisplay

    private var xdgSurface: XdgSurface
    private var toplevel: XdgToplevel
    private unowned let eventLoop: WaylandEventLoop

    private var _size: SIMD2<UInt>
    private var pendingToplevelSize: SIMD2<UInt> = .zero
    private var configured: Bool = false

    init(
        eventLoop: WaylandEventLoop,
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

        try? toplevel.setTitle(attributes.title)
        setupCallbacks()
        try? surface.commit()
    }

    private func setupCallbacks() {
        toplevel.onEvent = { [weak self] event in
            guard let self else { return }
            switch event {
            case .configure(let width, let height, _):
                pendingToplevelSize = width > 0 && height > 0
                    ? SIMD2<UInt>(UInt(width), UInt(height))
                    : .zero
            case .close:
                eventLoop.sendWindowEvent(.closeRequested, to: id)
            default:
                break
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
                eventLoop.sendWindowEvent(.resized(size: physSize, isFinal: true), to: id)
            }

            // Commit without a buffer — surface stays unmapped until the
            // renderer (Vulkan/EGL/wgpu) attaches its own buffer.
            try? surface.commit()
        }
    }

    deinit {
        try? toplevel.destroy()
        try? xdgSurface.destroy()
        try? surface.destroy()
    }
}

extension WaylandWindow: IWindow {
    public var size: SIMD2<UInt> {
        get { _size }
        set { _size = newValue }
    }

    public func requestRedraw() {
        try? surface.damage(x: 0, y: 0, width: Int32(_size.x), height: Int32(_size.y))
        try? surface.commit()
    }

    public func focus() {
        // Wayland does not expose a client-side focus request
    }

    public func prePresentNotify() {
        try? surface.frame { _ in }
    }
}
