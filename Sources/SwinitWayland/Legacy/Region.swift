import CWayland

public class Region {
    let region: OpaquePointer

    init(region: OpaquePointer) {
        self.region = region
    }

    func add(x: Int32, y: Int32, width: Int32, height: Int32) {
        wl_region_add(region, x, y, width, height)
    }

    func subtract(x: Int32, y: Int32, width: Int32, height: Int32) {
        wl_region_subtract(region, x, y, width, height)
    }

    deinit {
        wl_region_destroy(region)
    }
}
