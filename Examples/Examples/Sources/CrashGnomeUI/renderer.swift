import WaylandClient
import WaylandClientProtocols
import CairoLib
import Glibc
import Foundation

// Button layout — fixed size, centered in whatever window size we have.
let buttonW = 200.0
let buttonH = 56.0
let cornerR  = 10.0

func buttonRect(w: Int, h: Int) -> (x: Double, y: Double, w: Double, h: Double) {
    (x: (Double(w) - buttonW) / 2,
     y: (Double(h) - buttonH) / 2,
     w: buttonW, h: buttonH)
}

func isOverButton(x: Double, y: Double, winW: Int, winH: Int) -> Bool {
    let r = buttonRect(w: winW, h: winH)
    return x >= r.x && x <= r.x + r.w && y >= r.y && y <= r.y + r.h
}

// Rounded rectangle path.
private func roundedRect(_ cr: OpaquePointer!, x: Double, y: Double,
                          w: Double, h: Double, r: Double) {
    cairo_new_sub_path(cr)
    cairo_arc(cr, x + w - r, y + r,     r, -.pi / 2, 0)
    cairo_arc(cr, x + w - r, y + h - r, r, 0,        .pi / 2)
    cairo_arc(cr, x + r,     y + h - r, r, .pi / 2,  .pi)
    cairo_arc(cr, x + r,     y + r,     r, .pi,      1.5 * .pi)
    cairo_close_path(cr)
}

@MainActor
final class ButtonRenderer {
    private let shm: WlShm
    nonisolated(unsafe) private var pool: WlShmPool?
    nonisolated(unsafe) private var buffer: WlBuffer?
    nonisolated(unsafe) private var pixels: UnsafeMutableRawPointer?
    private var mappedSize = 0

    init(shm: WlShm) { self.shm = shm }

    deinit {
        if let pixels, mappedSize > 0 { munmap(pixels, mappedSize) }
        try? buffer?.destroy()
        try? pool?.destroy()
    }

    func draw(surface: WlSurface, w: Int, h: Int, hovered: Bool) {
        guard w > 0, h > 0 else { return }
        let stride = w * 4
        let needed = stride * h
        if needed != mappedSize { reallocate(w: w, h: h, stride: stride, size: needed) }
        guard let pixels, let buffer else { return }

        paint(pixels: pixels, w: w, h: h, stride: stride, hovered: hovered)

        try? surface.attach(buffer: buffer, x: 0, y: 0)
        try? surface.damage(x: 0, y: 0, width: Int32(w), height: Int32(h))
        try? surface.commit()
    }

    private func paint(pixels: UnsafeMutableRawPointer, w: Int, h: Int,
                       stride: Int, hovered: Bool) {
        // CAIRO_FORMAT_ARGB32 and WL_SHM_FORMAT_XRGB8888 share memory layout
        // for opaque content on little-endian (both 0xXXRRGGBB stored as BGRX).
        let cs = cairo_image_surface_create_for_data(
            pixels.bindMemory(to: UInt8.self, capacity: stride * h),
            CAIRO_FORMAT_ARGB32, Int32(w), Int32(h), Int32(stride))
        let cr = cairo_create(cs)
        defer { cairo_destroy(cr); cairo_surface_destroy(cs) }

        // Background
        cairo_set_source_rgb(cr, 0.11, 0.11, 0.16)
        cairo_paint(cr)

        // Button fill
        let b = buttonRect(w: w, h: h)
        roundedRect(cr, x: b.x, y: b.y, w: b.w, h: b.h, r: cornerR)
        if hovered {
            cairo_set_source_rgb(cr, 0.92, 0.22, 0.22)
        } else {
            cairo_set_source_rgb(cr, 0.72, 0.10, 0.10)
        }
        cairo_fill_preserve(cr)

        // Button border
        cairo_set_source_rgba(cr, 1, 1, 1, 0.15)
        cairo_set_line_width(cr, 1.5)
        cairo_stroke(cr)

        // Label
        cairo_set_source_rgb(cr, 1, 1, 1)
        cairo_select_font_face(cr, "Sans", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD)
        cairo_set_font_size(cr, 17)
        var ext = cairo_text_extents_t()
        cairo_text_extents(cr, "Crash Gnome", &ext)
        let tx = b.x + (b.w - ext.width)  / 2 - ext.x_bearing
        let ty = b.y + (b.h - ext.height) / 2 - ext.y_bearing
        cairo_move_to(cr, tx, ty)
        cairo_show_text(cr, "Crash Gnome")
    }

    private func reallocate(w: Int, h: Int, stride: Int, size: Int) {
        if let pixels, mappedSize > 0 { munmap(pixels, mappedSize) }
        try? buffer?.destroy(); try? pool?.destroy()
        pixels = nil; buffer = nil; pool = nil; mappedSize = 0

        let name = "/crashgnome-\(UInt64.random(in: .min ... .max))"
        let fd = shm_open(name, O_RDWR | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
        guard fd != -1 else { return }
        _ = shm_unlink(name)
        guard ftruncate(fd, off_t(size)) == 0 else { close(fd); return }
        let fh = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        let p = try? shm.createPool(fd: fh, size: Int32(size))
        let b = try? p?.createBuffer(offset: 0, width: Int32(w), height: Int32(h),
                                      stride: Int32(stride), format: .xrgb8888)
        let mapped = mmap(nil, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0)
        pool = p; buffer = b; mappedSize = size
        self.pixels = (mapped != MAP_FAILED) ? mapped : nil
    }
}
