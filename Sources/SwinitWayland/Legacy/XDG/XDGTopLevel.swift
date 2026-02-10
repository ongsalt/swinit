import CWayland
import Foundation
import Glibc

// we should actually do codegen

public struct XDGToplevelListener {
    let configure: ((SIMD2<Int32>, [Any]) -> Void)?
    let close: (() -> Void)?
    let configureBounds: ((SIMD2<Int32>) -> Void)?
    let wmCapabilities: (([Any]) -> Void)?
}

public class XDGTopLevel {
    let topLevel: OpaquePointer
    private let swiftListener: XDGToplevelListener?
    private var listener: xdg_toplevel_listener?

    public init(
        surface: XDGSurface, title: String = "App", appId: String = UUID().uuidString,
        listener swiftListener: XDGToplevelListener? = nil
    ) {
        self.title = title
        self.appId = appId
        self.topLevel = xdg_surface_get_toplevel(surface.surface)
        self.swiftListener = swiftListener

        if swiftListener != nil {
            listener = xdg_toplevel_listener(
                configure: {
                    (data, topLevel, w: Int32, h: Int32, _: UnsafeMutablePointer<wl_array>?) in
                    let this = Unmanaged<XDGTopLevel>.fromOpaque(data!).takeUnretainedValue()
                    this.swiftListener?.configure?(SIMD2(w, h), [])
                },
                close: { (data, topLevel) in
                    let this = Unmanaged<XDGTopLevel>.fromOpaque(data!).takeUnretainedValue()
                    this.swiftListener?.close?()

                },
                configure_bounds: { (data, topLevel, w: Int32, h: Int32) in
                    let this = Unmanaged<XDGTopLevel>.fromOpaque(data!).takeUnretainedValue()
                    this.swiftListener?.configureBounds?(SIMD2(w, h))
                },
                wm_capabilities: { (data, topLevel, wtf: UnsafeMutablePointer<wl_array>?) -> Void in
                    let this = Unmanaged<XDGTopLevel>.fromOpaque(data!).takeUnretainedValue()
                    this.swiftListener?.wmCapabilities?([])
                }
            )

            let this = Unmanaged.passUnretained(self).toOpaque()
            xdg_toplevel_add_listener(topLevel, &listener!, this)
        }
    }

    public var title: String {
        didSet {
            xdg_toplevel_set_title(topLevel, title)
        }
    }

    public var appId: String {
        didSet {
            xdg_toplevel_set_app_id(topLevel, appId)
        }
    }

}
