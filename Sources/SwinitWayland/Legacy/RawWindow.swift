import Glibc
import SwinitCommon

// not actually a window
public class RawWindow {
    // override for window event
    public let display: Display
    public let surface: Surface
    public let xdgSurface: XDGSurface
    public let xdgTopLevel: XDGTopLevel

    public var title: String {
        get {
            xdgTopLevel.title
        }
        set {
            xdgTopLevel.title = newValue
        }
    }

    public init(display: Display, title: String = "Raw window") {
        self.display = display
        let registry = display.registry

        surface = Surface(compositor: registry.compositor)

        let this = Box<RawWindow?>(nil)

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
        xdgTopLevel.title = title

        this.value = self
        surface.commit()
        display.dispatch()
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
