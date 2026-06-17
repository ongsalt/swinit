#if WaylandCSD
import CCairo
import Foundation
import Glibc
import SwinitCore
import WaylandClient
import WaylandClientProtocols

// MARK: - Hit-test area

package enum CSDArea {
    case titleBar
    case borderTop
    case borderLeft
    case borderRight
    case borderBottom
}

// MARK: - Layout constants

package enum CSDConstants {
    package static let titleBarHeight: Int32 = 30
    package static let borderWidth: Int32 = 0
    package static let resizeGrabWidth: Int32 = 8
    package static let shadowMargin: Int32 = 12
    package static let cornerRadius: Double = 8.0

    package static let buttonRadius: Double = 7.0
    package static let buttonSpacing: Double = 5.0
    package static let buttonMarginLeft: Double = 12.0

    static let titleBarRGBA = (r: 0.169, g: 0.169, b: 0.169, a: 1.0)
    static let titleBarInactiveRGBA = (r: 0.239, g: 0.239, b: 0.239, a: 1.0)
    static let borderRGBA = (r: 0.118, g: 0.118, b: 0.118, a: 1.0)
    static let titleTextRGBA = (r: 1.0, g: 1.0, b: 1.0, a: 0.85)
    static let titleTextInactiveRGBA = (r: 1.0, g: 1.0, b: 1.0, a: 0.4)

    static let closeRGBA = (r: 1.0, g: 0.373, b: 0.341, a: 1.0)
    static let minimizeRGBA = (r: 1.0, g: 0.741, b: 0.180, a: 1.0)
    static let maximizeRGBA = (r: 0.157, g: 0.792, b: 0.255, a: 1.0)
    static let buttonInactiveRGBA = (r: 0.427, g: 0.427, b: 0.427, a: 1.0)
}

// MARK: - Reusable SHM buffer

final class SHMLayer {
    private var pool: WlShmPool?
    private var buffer: WlBuffer?
    private var mappedData: UnsafeMutableRawPointer?
    private(set) var mappedSize: Int = 0
    private(set) var width: Int = 0
    private(set) var height: Int = 0

    deinit {
        if let d = mappedData, mappedSize > 0 { munmap(d, mappedSize) }
    }

    func prepare(shm: WlShm, width w: Int, height h: Int) -> (UnsafeMutableRawPointer, WlBuffer)? {
        guard w > 0, h > 0 else { return nil }
        let stride = cairo_format_stride_for_width(CAIRO_FORMAT_ARGB32, Int32(w))
        let needed = Int(stride) * h
        if needed != mappedSize {
            if let d = mappedData, mappedSize > 0 { munmap(d, mappedSize) }
            try? buffer?.destroy()
            try? pool?.destroy()
            mappedData = nil
            buffer = nil
            pool = nil
            mappedSize = 0

            let name = "/swinit-csd-\(UInt64.random(in: .min ... .max))"
            let fd = shm_open(name, O_RDWR | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
            guard fd != -1 else { return nil }
            _ = shm_unlink(name)
            guard ftruncate(fd, off_t(needed)) == 0 else {
                close(fd)
                return nil
            }
            let fh = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
            guard let p = try? shm.createPool(fd: fh, size: Int32(needed)),
                let b = try? p.createBuffer(
                    offset: 0, width: Int32(w), height: Int32(h),
                    stride: stride, format: .argb8888)
            else { return nil }
            let mapped = mmap(nil, needed, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0)
            pool = p
            buffer = b
            mappedSize = needed
            self.width = w
            self.height = h
            mappedData = (mapped != MAP_FAILED) ? mapped : nil
        }
        guard let ptr = mappedData, let buf = buffer else { return nil }
        return (ptr, buf)
    }
}

// MARK: - Subsurface

@MainActor
final class CSDSubsurface {
    // nonisolated(unsafe): deinit is nonisolated in Swift 6, but we only ever destroy these
    // from the main actor — safe in practice.
    nonisolated(unsafe) let surface: WlSurface
    nonisolated(unsafe) private let sub: WlSubsurface
    private let shmLayer = SHMLayer()

    init(compositor: WlCompositor, subcompositor: WlSubcompositor, parent: WlSurface) throws {
        surface = try compositor.createSurface()
        sub = try subcompositor.getSubsurface(surface: surface, parent: parent)
        try sub.setSync()
    }

    deinit {
        try? sub.destroy()
        try? surface.destroy()
    }

    func render(
        shm: WlShm, x: Int32, y: Int32, width: Int, height: Int,
        _ draw: (UnsafeMutableRawPointer, Int, Int) -> Void
    ) throws {
        try sub.setPosition(x: x, y: y)
        guard let (ptr, buf) = shmLayer.prepare(shm: shm, width: width, height: height) else {
            return
        }
        draw(ptr, width, height)
        try surface.attach(buffer: buf, x: 0, y: 0)
        try surface.damage(x: 0, y: 0, width: Int32(width), height: Int32(height))
        try surface.commit()
    }

    func detach() throws {
        try surface.attach(x: 0, y: 0)
        try surface.commit()
    }

    func placeBelow(sibling: WlSurface) throws { try sub.placeBelow(sibling: sibling) }
}

// MARK: - CSD Layer

@MainActor
package final class CSDLayer {
    private let titleBar: CSDSubsurface
    private let top: CSDSubsurface
    private let left: CSDSubsurface
    private let right: CSDSubsurface
    private let bottom: CSDSubsurface
    private let shadow: CSDSubsurface

    package let buttonRadius: Double = CSDConstants.buttonRadius
    package let closeCenter: SIMD2<Double>
    package let minimizeCenter: SIMD2<Double>
    package let maximizeCenter: SIMD2<Double>

    package var titleBarSurfaceId: UInt32 { titleBar.surface.id }
    package var topSurfaceId: UInt32 { top.surface.id }
    package var leftSurfaceId: UInt32 { left.surface.id }
    package var rightSurfaceId: UInt32 { right.surface.id }
    package var bottomSurfaceId: UInt32 { bottom.surface.id }

    private var cache: (size: Size, title: String, maximized: Bool, activated: Bool)?

    package init(
        compositor: WlCompositor, subcompositor: WlSubcompositor, shm: WlShm,
        parentSurface: WlSurface, contentSize: Size,
        title: String, activated: Bool
    ) throws {
        titleBar = try CSDSubsurface(
            compositor: compositor, subcompositor: subcompositor, parent: parentSurface)
        top = try CSDSubsurface(
            compositor: compositor, subcompositor: subcompositor, parent: parentSurface)
        left = try CSDSubsurface(
            compositor: compositor, subcompositor: subcompositor, parent: parentSurface)
        right = try CSDSubsurface(
            compositor: compositor, subcompositor: subcompositor, parent: parentSurface)
        bottom = try CSDSubsurface(
            compositor: compositor, subcompositor: subcompositor, parent: parentSurface)
        shadow = try CSDSubsurface(
            compositor: compositor, subcompositor: subcompositor, parent: parentSurface)

        try shadow.placeBelow(sibling: parentSurface)
        let emptyRegion = try compositor.createRegion()
        try shadow.surface.setInputRegion(region: emptyRegion)
        try emptyRegion.destroy()

        let cy = Double(CSDConstants.titleBarHeight) / 2.0
        let bR = CSDConstants.buttonRadius
        let bSp = CSDConstants.buttonSpacing
        let bML = CSDConstants.buttonMarginLeft
        let cx0 = bML + bR
        closeCenter = SIMD2(cx0, cy)
        minimizeCenter = SIMD2(cx0 + 2 * bR + bSp, cy)
        maximizeCenter = SIMD2(cx0 + 4 * bR + 2 * bSp, cy)

        try update(
            shm: shm, contentSize: contentSize, title: title,
            maximized: false, activated: activated)
    }

    package func update(
        shm: WlShm, contentSize: Size, title: String,
        maximized: Bool, activated: Bool
    ) throws {
        let prev = cache
        cache = (contentSize, title, maximized, activated)

        let sizeChanged = prev?.size != contentSize
        let titleBarDirty =
            sizeChanged
            || prev?.title != title
            || prev?.activated != activated
            || prev?.maximized != maximized
        let bordersDirty = sizeChanged || prev?.maximized != maximized
        guard titleBarDirty || bordersDirty else { return }

        let cW = max(Int(contentSize.width), 1)
        let cH = max(Int(contentSize.height), 1)
        let gW = Int(CSDConstants.resizeGrabWidth)
        let tH = Int(CSDConstants.titleBarHeight)
        let sM = Int(CSDConstants.shadowMargin)

        if titleBarDirty {
            try titleBar.render(
                shm: shm,
                x: 0, y: -Int32(tH),
                width: cW, height: tH
            ) { ptr, w, h in
                cairoDrawTitleBar(
                    ptr, width: w, height: h,
                    title: title, activated: activated,
                    roundTopCorners: !maximized)
            }
        }

        if bordersDirty {
            if maximized {
                try top.detach()
                try left.detach()
                try right.detach()
                try bottom.detach()
                try shadow.detach()
            } else {
                // Invisible grab zones: transparent pixels so the compositor routes
                // pointer events here, but nothing is drawn on screen.
                let edgeW = cW + 2 * gW
                try top.render(
                    shm: shm, x: -Int32(gW), y: -Int32(tH + gW),
                    width: edgeW, height: gW
                ) { ptr, w, h in
                    cairoSolidFill(ptr, width: w, height: h, rgba: (r: 0, g: 0, b: 0, a: 0))
                }
                try left.render(shm: shm, x: -Int32(gW), y: 0, width: gW, height: cH) { ptr, w, h in
                    cairoSolidFill(ptr, width: w, height: h, rgba: (r: 0, g: 0, b: 0, a: 0))
                }
                try right.render(shm: shm, x: Int32(cW), y: 0, width: gW, height: cH) { ptr, w, h in
                    cairoSolidFill(ptr, width: w, height: h, rgba: (r: 0, g: 0, b: 0, a: 0))
                }
                try bottom.render(
                    shm: shm, x: -Int32(gW), y: Int32(cH),
                    width: edgeW, height: gW
                ) { ptr, w, h in
                    cairoSolidFill(ptr, width: w, height: h, rgba: (r: 0, g: 0, b: 0, a: 0))
                }
                let shW = cW + 2 * sM
                let shH = cH + tH + 2 * sM
                try shadow.render(
                    shm: shm,
                    x: -Int32(sM), y: -Int32(tH + sM),
                    width: shW, height: shH
                ) { ptr, w, h in
                    cairoDrawShadow(
                        ptr, width: w, height: h,
                        innerX: sM, innerY: sM,
                        innerW: cW, innerH: cH + tH,
                        blur: sM, cornerR: CSDConstants.cornerRadius)
                }
            }
        }
    }
}

// MARK: - Cairo helpers

private func withCairo(
    _ ptr: UnsafeMutableRawPointer, width: Int, height: Int,
    _ draw: (OpaquePointer) -> Void
) {
    let stride = cairo_format_stride_for_width(CAIRO_FORMAT_ARGB32, Int32(width))
    guard
        let cs = cairo_image_surface_create_for_data(
            ptr.assumingMemoryBound(to: UInt8.self),
            CAIRO_FORMAT_ARGB32, Int32(width), Int32(height), stride)
    else { return }
    defer { cairo_surface_destroy(cs) }
    guard let cr = cairo_create(cs) else { return }
    defer { cairo_destroy(cr) }
    draw(cr)
    cairo_surface_flush(cs)
}

private func cairoRoundedRect(
    _ cr: OpaquePointer,
    x: Double, y: Double, w: Double, h: Double, r: Double
) {
    let r = min(r, w / 2, h / 2)
    cairo_new_path(cr)
    cairo_arc(cr, x + w - r, y + r, r, -Double.pi / 2, 0)
    cairo_arc(cr, x + w - r, y + h - r, r, 0, Double.pi / 2)
    cairo_arc(cr, x + r, y + h - r, r, Double.pi / 2, Double.pi)
    cairo_arc(cr, x + r, y + r, r, Double.pi, -Double.pi / 2)
    cairo_close_path(cr)
}

private func cairoTopRounded(
    _ cr: OpaquePointer,
    x: Double, y: Double, w: Double, h: Double, r: Double
) {
    let r = min(r, w / 2, h)
    cairo_new_path(cr)
    cairo_move_to(cr, x, y + h)
    cairo_line_to(cr, x, y + r)
    cairo_arc(cr, x + r, y + r, r, Double.pi, -Double.pi / 2)
    cairo_arc(cr, x + w - r, y + r, r, -Double.pi / 2, 0)
    cairo_line_to(cr, x + w, y + h)
    cairo_close_path(cr)
}

private func cairoSet(_ cr: OpaquePointer, r: Double, g: Double, b: Double, a: Double) {
    cairo_set_source_rgba(cr, r, g, b, a)
}

private func cairoDrawTitleBar(
    _ ptr: UnsafeMutableRawPointer,
    width: Int, height: Int,
    title: String, activated: Bool, roundTopCorners: Bool
) {
    withCairo(ptr, width: width, height: height) { cr in
        cairo_set_operator(cr, CAIRO_OPERATOR_CLEAR)
        cairo_paint(cr)
        cairo_set_operator(cr, CAIRO_OPERATOR_OVER)

        let bg = activated ? CSDConstants.titleBarRGBA : CSDConstants.titleBarInactiveRGBA
        cairoSet(cr, r: bg.r, g: bg.g, b: bg.b, a: bg.a)
        if roundTopCorners {
            cairoTopRounded(
                cr, x: 0, y: 0, w: Double(width), h: Double(height),
                r: CSDConstants.cornerRadius)
        } else {
            cairo_rectangle(cr, 0, 0, Double(width), Double(height))
        }
        cairo_fill(cr)

        let bR = CSDConstants.buttonRadius
        let bSp = CSDConstants.buttonSpacing
        let bML = CSDConstants.buttonMarginLeft
        let cy = Double(height) / 2.0
        let closeX = bML + bR
        let minX = closeX + 2 * bR + bSp
        let maxX = minX + 2 * bR + bSp

        func drawButton(cx: Double, rgba: (r: Double, g: Double, b: Double, a: Double)) {
            let c = activated ? rgba : CSDConstants.buttonInactiveRGBA
            cairoSet(cr, r: c.r, g: c.g, b: c.b, a: c.a)
            cairo_new_path(cr)
            cairo_arc(cr, cx, cy, bR, 0, 2 * Double.pi)
            cairo_fill(cr)
        }
        drawButton(cx: closeX, rgba: CSDConstants.closeRGBA)
        drawButton(cx: minX, rgba: CSDConstants.minimizeRGBA)
        drawButton(cx: maxX, rgba: CSDConstants.maximizeRGBA)

        if !title.isEmpty {
            let text = activated ? CSDConstants.titleTextRGBA : CSDConstants.titleTextInactiveRGBA
            cairoSet(cr, r: text.r, g: text.g, b: text.b, a: text.a)
            cairo_select_font_face(
                cr, "sans-serif", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD)
            cairo_set_font_size(cr, 13.0)
            var ext = cairo_text_extents_t()
            cairo_text_extents(cr, title, &ext)
            let tx = (Double(width) - ext.width) / 2.0 - ext.x_bearing
            let ty = (Double(height) - ext.height) / 2.0 - ext.y_bearing
            cairo_move_to(cr, tx, ty)
            cairo_show_text(cr, title)
        }
    }
}

private func cairoSolidFill(
    _ ptr: UnsafeMutableRawPointer, width: Int, height: Int,
    rgba: (r: Double, g: Double, b: Double, a: Double)
) {
    withCairo(ptr, width: width, height: height) { cr in
        cairo_set_operator(cr, CAIRO_OPERATOR_SOURCE)
        cairo_set_source_rgba(cr, rgba.r, rgba.g, rgba.b, rgba.a)
        cairo_paint(cr)
    }
}

private func cairoDrawShadow(
    _ ptr: UnsafeMutableRawPointer,
    width: Int, height: Int,
    innerX: Int, innerY: Int,
    innerW: Int, innerH: Int,
    blur: Int, cornerR: Double
) {
    withCairo(ptr, width: width, height: height) { cr in
        cairo_set_operator(cr, CAIRO_OPERATOR_CLEAR)
        cairo_paint(cr)
        cairo_set_operator(cr, CAIRO_OPERATOR_OVER)

        let steps = blur
        let iX = Double(innerX)
        let iY = Double(innerY)
        let iW = Double(innerW)
        let iH = Double(innerH)

        for i in 0..<steps {
            // t=0 → outermost ring, t→1 → innermost ring.
            // t² weighting makes inner rings stronger, producing a cubic
            // accumulated falloff (~50% at edge → 0% at blur distance).
            let t = Double(i) / Double(steps)
            let alpha = pow(t * (1.5 / Double(steps)), 1.4)
            let expand = Double(steps - i)
            cairo_set_source_rgba(cr, 0, 0, 0, alpha)
            cairoTopRounded(
                cr,
                x: iX - expand, y: iY - expand,
                w: iW + 2 * expand, h: iH + 2 * expand,
                r: cornerR + expand)
            cairo_fill(cr)
        }

        cairo_set_operator(cr, CAIRO_OPERATOR_CLEAR)
        cairoTopRounded(cr, x: iX, y: iY, w: iW, h: iH, r: cornerR)
        cairo_fill(cr)
    }
}
#endif
