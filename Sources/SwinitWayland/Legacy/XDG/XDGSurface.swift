import CWayland
import Glibc

// we shuold actually do codegen
public class XDGSurface {
    let surface: OpaquePointer
    private(set) var listener: xdg_surface_listener
    let configure: () -> Void

    public init(
        xdgWmBase: OpaquePointer, surface waylandSurface: Surface,
        configure: @escaping () -> Void = {}
    ) {
        self.configure = configure
        self.surface = xdg_wm_base_get_xdg_surface(xdgWmBase, waylandSurface.surface)

        listener = xdg_surface_listener { data, surface, serial -> Void in
            let this = Unmanaged<XDGSurface>.fromOpaque(data!).takeUnretainedValue()
            this.configure()

            xdg_surface_ack_configure(this.surface, serial)
        }

        let this = Unmanaged.passUnretained(self).toOpaque()
        xdg_surface_add_listener(self.surface, &listener, this)
    }
}
