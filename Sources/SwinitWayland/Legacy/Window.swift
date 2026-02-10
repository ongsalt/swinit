import Glibc
import SwinitCommon

// not actually a window
open class Window {
    // override for window event
    public let display: Display
    public let surface: Surface
    public let xdgSurface: XDGSurface
    public let xdgTopLevel: XDGTopLevel

    public let width: Int32
    public let height: Int32

    private let pool: SHMPool
    // TODO: fix buffer size
    // TODO: move wayland display init out of this
    private var buffer: Buffer!

    public var currentBuffer: Buffer {
        buffer
    }


    public init(display: Display, pool: SHMPool, width: Int32 = 640, height: Int32 = 480) {
        self.display = display
        self.pool = pool
        self.width = width
        self.height = height

        let registry = display.registry

        surface = Surface(compositor: registry.compositor)

        let this = Box<Window?>(nil)

        xdgSurface = XDGSurface(
            xdgWmBase: registry.xdgWmBase,
            surface: surface,
            configure: { [this] in
                let this = this.value!
                // this api is shit, TODO: fix it

                // rendering
            }
        )
        
        xdgTopLevel = XDGTopLevel(surface: xdgSurface)
        xdgTopLevel.title = "Asd"

        // surface.opaqueRegion = Region(region: compos)
        initBuffer()

        this.value = self
        surface.commit()
        display.dispatch()
    }

    private func initBuffer() {
        if buffer != nil { return }

        buffer = pool.createBuffer(
            offset: 0, width: width, height: height, stride: 4 * width)

        pool.poolData.initializeMemory(
            as: UInt32.self, repeating: 0xf298_6bff,
            count: Int(width * height * 4 / 2))

        surface.attach(buffer: buffer)
        surface.damage()
        surface.commit()
    }

    public func show() {
        requestRedraw()
        display.flush()
    }

    public func requestRedraw() {
        // surface.attach(buffer: buffer)
        surface.damage()
        surface.commit()
    }

}
