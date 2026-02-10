import CWayland

// TODO: width height
public class Surface: @unchecked Sendable {
    public let surface: OpaquePointer
    // var width: Int32
    private var runLoopObserver: RunLoopObserver? = nil

    public var opaqueRegion: Region? = nil {
        didSet {
            wl_surface_set_opaque_region(surface, opaqueRegion?.region)
        }
    }

    public init(compositor: OpaquePointer, autoCommit: Bool = false) {
        surface = wl_compositor_create_surface(compositor)

        // self.opaqueRegion = Region(region: wl_compositor_create_region(compositor))

        // TODO: remove this
        if autoCommit {
            runLoopObserver = RunLoopObserver(on: [.beforeWaiting]) { [unowned self] actvity in
                print("[before idle] commit")
                wl_surface_commit(self.surface)
            }
        }

        // vsync?
        // vsyncshufygd()
    }

    private var onFrameCallback: (() -> Void)?
    public func onFrame(runImmediately: Bool = false, _ block: @escaping () -> Void) {
        onFrameCallback = block
        if runImmediately {
            block()
        }
        scheduleOnFrameCallback()
    }

    nonisolated(unsafe) static var listener: wl_callback_listener = wl_callback_listener {
        thisPtr, cb, data in
        wl_callback_destroy(cb)
        let this = Unmanaged<Surface>.fromOpaque(thisPtr!).takeUnretainedValue()

        if let onFrameCallback = this.onFrameCallback {
            onFrameCallback()
            this.scheduleOnFrameCallback()
        }

        this.damage()
        this.commit()
    }

    private func scheduleOnFrameCallback() {
        let cb = wl_surface_frame(surface)!
        let this = Unmanaged.passUnretained(self)

        wl_callback_add_listener(cb, &Surface.listener, this.toOpaque())
    }

    public func attach(buffer: Buffer, x: Int32 = 0, y: Int32 = 0) {
        wl_surface_attach(surface, buffer.buffer, x, y)
    }

    public func damage() {
        damage(x: 0, y: 0, width: Int32.max, height: Int32.max)
    }

    public func damage(x: Int32, y: Int32, width: Int32, height: Int32) {
        wl_surface_damage_buffer(surface, x, y, width, height)
    }

    public func commit() {
        wl_surface_commit(surface)
    }
}
