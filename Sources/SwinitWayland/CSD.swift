import SwiftWayland
import WaylandProtocols
import CCairo
import Glibc
import Foundation

// MARK: - Hit-test area

enum CSDArea {
    case titleBar
    case borderLeft
    case borderRight
    case borderBottom
}

// MARK: - Layout constants

enum CSDConstants {
    static let titleBarHeight: Int32 = 30
    static let borderWidth: Int32 = 6
    static let shadowMargin: Int32 = 24
    static let cornerRadius: Double = 8.0

    static let buttonRadius: Double = 7.0
    static let buttonSpacing: Double = 5.0
    static let buttonMarginLeft: Double = 12.0

    // Title bar colors (RGBA tuples)
    static let titleBarRGBA = (r: 0.169, g: 0.169, b: 0.169, a: 1.0)           // #2B2B2B
    static let titleBarInactiveRGBA = (r: 0.239, g: 0.239, b: 0.239, a: 1.0)   // #3D3D3D
    static let borderRGBA = (r: 0.118, g: 0.118, b: 0.118, a: 1.0)             // #1E1E1E
    static let titleTextRGBA = (r: 1.0, g: 1.0, b: 1.0, a: 0.85)
    static let titleTextInactiveRGBA = (r: 1.0, g: 1.0, b: 1.0, a: 0.4)

    // Button colors (RGBA)
    static let closeRGBA     = (r: 1.0,   g: 0.373, b: 0.341, a: 1.0)   // #FF5F57
    static let minimizeRGBA  = (r: 1.0,   g: 0.741, b: 0.180, a: 1.0)   // #FFBD2E
    static let maximizeRGBA  = (r: 0.157, g: 0.792, b: 0.255, a: 1.0)   // #28CA41
    static let buttonInactiveRGBA = (r: 0.427, g: 0.427, b: 0.427, a: 1.0)  // #6D6D6D
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
        try? buffer?.destroy()
        try? pool?.destroy()
    }

    /// Returns a raw pointer to the ARGB8888 pixel data plus the matching WlBuffer.
    /// Reallocates the SHM pool only when the dimensions change.
    func prepare(shm: WlShm, width w: Int, height h: Int) -> (UnsafeMutableRawPointer, WlBuffer)? {
        guard w > 0, h > 0 else { return nil }
        let stride = cairo_format_stride_for_width(CAIRO_FORMAT_ARGB32, Int32(w))
        let needed = Int(stride) * h
        if needed != mappedSize {
            if let d = mappedData, mappedSize > 0 { munmap(d, mappedSize) }
            try? buffer?.destroy(); try? pool?.destroy()
            mappedData = nil; buffer = nil; pool = nil; mappedSize = 0

            let name = "/swinit-csd-\(UInt64.random(in: .min ... .max))"
            let fd = shm_open(name, O_RDWR | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
            guard fd != -1 else { return nil }
            _ = shm_unlink(name)
            guard ftruncate(fd, off_t(needed)) == 0 else { close(fd); return nil }
            let fh = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
            guard let p = try? shm.createPool(fd: fh, size: Int32(needed)),
                  let b = try? p.createBuffer(offset: 0, width: Int32(w), height: Int32(h),
                                              stride: stride, format: .argb8888)
            else { return nil }
            let mapped = mmap(nil, needed, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0)
            pool = p; buffer = b; mappedSize = needed; self.width = w; self.height = h
            mappedData = (mapped != MAP_FAILED) ? mapped : nil
        }
        guard let ptr = mappedData, let buf = buffer else { return nil }
        return (ptr, buf)
    }
}

// MARK: - CSD Layer

/// Manages all client-side decoration subsurfaces (title bar, borders, shadow).
@MainActor
final class CSDLayer {
    let titleBarSurface: WlSurface
    private let titleBarSubsurface: WlSubsurface
    private let leftSurface: WlSurface
    private let leftSubsurface: WlSubsurface
    private let rightSurface: WlSurface
    private let rightSubsurface: WlSubsurface
    private let bottomSurface: WlSurface
    private let bottomSubsurface: WlSubsurface
    private let shadowSurface: WlSurface
    private let shadowSubsurface: WlSubsurface

    private let titleBarLayer = SHMLayer()
    private let leftLayer = SHMLayer()
    private let rightLayer = SHMLayer()
    private let bottomLayer = SHMLayer()
    private let shadowLayer = SHMLayer()

    // Button centers in title-bar surface-local coords (for hit-testing)
    private(set) var closeCenter    = SIMD2<Double>.zero
    private(set) var minimizeCenter = SIMD2<Double>.zero
    private(set) var maximizeCenter = SIMD2<Double>.zero
    let buttonRadius: Double = CSDConstants.buttonRadius

    var titleBarSurfaceId: UInt32 { titleBarSurface.id }
    var leftSurfaceId:    UInt32 { leftSurface.id }
    var rightSurfaceId:   UInt32 { rightSurface.id }
    var bottomSurfaceId:  UInt32 { bottomSurface.id }

    init(compositor: WlCompositor, subcompositor: WlSubcompositor, shm: WlShm,
         parentSurface: WlSurface, contentSize: SIMD2<UInt>) throws {
        titleBarSurface = try compositor.createSurface()
        leftSurface     = try compositor.createSurface()
        rightSurface    = try compositor.createSurface()
        bottomSurface   = try compositor.createSurface()
        shadowSurface   = try compositor.createSurface()

        titleBarSubsurface = try subcompositor.getSubsurface(surface: titleBarSurface, parent: parentSurface)
        leftSubsurface     = try subcompositor.getSubsurface(surface: leftSurface,     parent: parentSurface)
        rightSubsurface    = try subcompositor.getSubsurface(surface: rightSurface,    parent: parentSurface)
        bottomSubsurface   = try subcompositor.getSubsurface(surface: bottomSurface,   parent: parentSurface)
        shadowSubsurface   = try subcompositor.getSubsurface(surface: shadowSurface,   parent: parentSurface)

        try shadowSubsurface.placeBelow(sibling: parentSurface)

        let emptyRegion = try compositor.createRegion()
        try shadowSurface.setInputRegion(region: emptyRegion)
        try emptyRegion.destroy()

        try titleBarSubsurface.setSync()
        try leftSubsurface.setSync()
        try rightSubsurface.setSync()
        try bottomSubsurface.setSync()
        try shadowSubsurface.setSync()

        try update(shm: shm, contentSize: contentSize, title: "", maximized: false, activated: true)
    }

    func update(shm: WlShm, contentSize: SIMD2<UInt>, title: String,
                maximized: Bool, activated: Bool) throws {
        let cW = max(Int(contentSize.x), 1)
        let cH = max(Int(contentSize.y), 1)
        let bW = Int(CSDConstants.borderWidth)
        let tH = Int(CSDConstants.titleBarHeight)
        let sM = Int(CSDConstants.shadowMargin)

        // Title bar (always visible with CSD)
        let tbW = cW + (maximized ? 0 : 2 * bW)
        try titleBarSubsurface.setPosition(x: maximized ? 0 : -Int32(bW), y: -Int32(tH))
        if let (ptr, buf) = titleBarLayer.prepare(shm: shm, width: tbW, height: tH) {
            cairoDrawTitleBar(ptr, width: tbW, height: tH,
                              title: title, activated: activated,
                              roundTopCorners: !maximized)
            let cy = Double(tH) / 2.0
            let bR  = CSDConstants.buttonRadius
            let bSp = CSDConstants.buttonSpacing
            let bML = CSDConstants.buttonMarginLeft
            closeCenter    = SIMD2(bML + bR, cy)
            minimizeCenter = SIMD2(closeCenter.x    + 2 * bR + bSp, cy)
            maximizeCenter = SIMD2(minimizeCenter.x + 2 * bR + bSp, cy)
            try titleBarSurface.attach(buffer: buf, x: 0, y: 0)
            try titleBarSurface.damage(x: 0, y: 0, width: Int32(tbW), height: Int32(tH))
            try titleBarSurface.commit()
        }

        if maximized {
            for s in [leftSurface, rightSurface, bottomSurface, shadowSurface] {
                try s.attach(x: 0, y: 0)
                try s.commit()
            }
        } else {
            // Left border
            try leftSubsurface.setPosition(x: -Int32(bW), y: 0)
            if let (ptr, buf) = leftLayer.prepare(shm: shm, width: bW, height: cH) {
                cairoSolidFill(ptr, width: bW, height: cH, rgba: CSDConstants.borderRGBA)
                try leftSurface.attach(buffer: buf, x: 0, y: 0)
                try leftSurface.damage(x: 0, y: 0, width: Int32(bW), height: Int32(cH))
                try leftSurface.commit()
            }

            // Right border
            try rightSubsurface.setPosition(x: Int32(cW), y: 0)
            if let (ptr, buf) = rightLayer.prepare(shm: shm, width: bW, height: cH) {
                cairoSolidFill(ptr, width: bW, height: cH, rgba: CSDConstants.borderRGBA)
                try rightSurface.attach(buffer: buf, x: 0, y: 0)
                try rightSurface.damage(x: 0, y: 0, width: Int32(bW), height: Int32(cH))
                try rightSurface.commit()
            }

            // Bottom border
            let botW = cW + 2 * bW
            try bottomSubsurface.setPosition(x: -Int32(bW), y: Int32(cH))
            if let (ptr, buf) = bottomLayer.prepare(shm: shm, width: botW, height: bW) {
                cairoSolidFill(ptr, width: botW, height: bW, rgba: CSDConstants.borderRGBA)
                try bottomSurface.attach(buffer: buf, x: 0, y: 0)
                try bottomSurface.damage(x: 0, y: 0, width: Int32(botW), height: Int32(bW))
                try bottomSurface.commit()
            }

            // Shadow
            let shW = cW + 2 * (bW + sM)
            let shH = cH + tH + bW + 2 * sM
            try shadowSubsurface.setPosition(x: -Int32(bW + sM), y: -Int32(tH + sM))
            if let (ptr, buf) = shadowLayer.prepare(shm: shm, width: shW, height: shH) {
                cairoDrawShadow(ptr, width: shW, height: shH,
                                innerX: sM, innerY: sM,
                                innerW: cW + 2 * bW, innerH: cH + tH + bW,
                                blur: sM, cornerR: CSDConstants.cornerRadius)
                try shadowSurface.attach(buffer: buf, x: 0, y: 0)
                try shadowSurface.damage(x: 0, y: 0, width: Int32(shW), height: Int32(shH))
                try shadowSurface.commit()
            }
        }
    }

    deinit {
        try? titleBarSubsurface.destroy(); try? titleBarSurface.destroy()
        try? leftSubsurface.destroy();     try? leftSurface.destroy()
        try? rightSubsurface.destroy();    try? rightSurface.destroy()
        try? bottomSubsurface.destroy();   try? bottomSurface.destroy()
        try? shadowSubsurface.destroy();   try? shadowSurface.destroy()
    }
}

// MARK: - Cairo drawing helpers

/// Run `draw` on a Cairo context backed by the given SHM pixel buffer.
private func withCairo(_ ptr: UnsafeMutableRawPointer, width: Int, height: Int,
                       _ draw: (OpaquePointer) -> Void) {
    let stride = cairo_format_stride_for_width(CAIRO_FORMAT_ARGB32, Int32(width))
    guard let cs = cairo_image_surface_create_for_data(
        ptr.assumingMemoryBound(to: UInt8.self),
        CAIRO_FORMAT_ARGB32, Int32(width), Int32(height), stride)
    else { return }
    defer { cairo_surface_destroy(cs) }
    guard let cr = cairo_create(cs) else { return }
    defer { cairo_destroy(cr) }
    draw(cr)
    cairo_surface_flush(cs)
}

/// Rounded rectangle path (all four corners).
private func cairoRoundedRect(_ cr: OpaquePointer,
                               x: Double, y: Double, w: Double, h: Double, r: Double) {
    let r = min(r, w / 2, h / 2)
    cairo_new_path(cr)
    cairo_arc(cr, x + w - r, y + r,     r, -Double.pi / 2, 0)
    cairo_arc(cr, x + w - r, y + h - r, r, 0,              Double.pi / 2)
    cairo_arc(cr, x + r,     y + h - r, r, Double.pi / 2,  Double.pi)
    cairo_arc(cr, x + r,     y + r,     r, Double.pi,      -Double.pi / 2)
    cairo_close_path(cr)
}

/// Rounded rectangle with only the top corners rounded.
private func cairoTopRounded(_ cr: OpaquePointer,
                              x: Double, y: Double, w: Double, h: Double, r: Double) {
    let r = min(r, w / 2, h)
    cairo_new_path(cr)
    cairo_move_to(cr, x, y + h)
    cairo_line_to(cr, x, y + r)
    cairo_arc(cr, x + r,     y + r, r, Double.pi,      -Double.pi / 2)
    cairo_arc(cr, x + w - r, y + r, r, -Double.pi / 2, 0)
    cairo_line_to(cr, x + w, y + h)
    cairo_close_path(cr)
}

private func cairoSet(_ cr: OpaquePointer, r: Double, g: Double, b: Double, a: Double) {
    cairo_set_source_rgba(cr, r, g, b, a)
}

private func cairoDrawTitleBar(_ ptr: UnsafeMutableRawPointer,
                                width: Int, height: Int,
                                title: String,
                                activated: Bool, roundTopCorners: Bool) {
    withCairo(ptr, width: width, height: height) { cr in
        // Clear to transparent
        cairo_set_operator(cr, CAIRO_OPERATOR_CLEAR)
        cairo_paint(cr)
        cairo_set_operator(cr, CAIRO_OPERATOR_OVER)

        // Background
        let bg = activated ? CSDConstants.titleBarRGBA : CSDConstants.titleBarInactiveRGBA
        cairoSet(cr, r: bg.r, g: bg.g, b: bg.b, a: bg.a)
        if roundTopCorners {
            cairoTopRounded(cr, x: 0, y: 0, w: Double(width), h: Double(height),
                            r: CSDConstants.cornerRadius)
        } else {
            cairo_rectangle(cr, 0, 0, Double(width), Double(height))
        }
        cairo_fill(cr)

        // Buttons (macOS layout: close · minimize · maximize on the left)
        let bR  = CSDConstants.buttonRadius
        let bSp = CSDConstants.buttonSpacing
        let bML = CSDConstants.buttonMarginLeft
        let cy  = Double(height) / 2.0
        let closeX = bML + bR
        let minX   = closeX + 2 * bR + bSp
        let maxX   = minX   + 2 * bR + bSp

        func drawButton(cx: Double, rgba: (r: Double, g: Double, b: Double, a: Double)) {
            let c = activated ? rgba : CSDConstants.buttonInactiveRGBA
            cairoSet(cr, r: c.r, g: c.g, b: c.b, a: c.a)
            cairo_new_path(cr)
            cairo_arc(cr, cx, cy, bR, 0, 2 * Double.pi)
            cairo_fill(cr)
        }
        drawButton(cx: closeX, rgba: CSDConstants.closeRGBA)
        drawButton(cx: minX,   rgba: CSDConstants.minimizeRGBA)
        drawButton(cx: maxX,   rgba: CSDConstants.maximizeRGBA)

        // Title text (centered in the bar)
        if !title.isEmpty {
            let text = activated ? CSDConstants.titleTextRGBA : CSDConstants.titleTextInactiveRGBA
            cairoSet(cr, r: text.r, g: text.g, b: text.b, a: text.a)
            cairo_select_font_face(cr, "sans-serif", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD)
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

private func cairoSolidFill(_ ptr: UnsafeMutableRawPointer, width: Int, height: Int,
                             rgba: (r: Double, g: Double, b: Double, a: Double)) {
    withCairo(ptr, width: width, height: height) { cr in
        cairo_set_operator(cr, CAIRO_OPERATOR_SOURCE)
        cairo_set_source_rgba(cr, rgba.r, rgba.g, rgba.b, rgba.a)
        cairo_paint(cr)
    }
}

private func cairoDrawShadow(_ ptr: UnsafeMutableRawPointer,
                              width: Int, height: Int,
                              innerX: Int, innerY: Int,
                              innerW: Int, innerH: Int,
                              blur: Int, cornerR: Double) {
    withCairo(ptr, width: width, height: height) { cr in
        cairo_set_operator(cr, CAIRO_OPERATOR_CLEAR)
        cairo_paint(cr)
        cairo_set_operator(cr, CAIRO_OPERATOR_OVER)

        // Paint shadow: render the window shape at increasing offsets + alpha,
        // building up a soft glow around the inner rectangle.
        let steps = blur
        let iX = Double(innerX)
        let iY = Double(innerY)
        let iW = Double(innerW)
        let iH = Double(innerH)

        for i in 0..<steps {
            let t = Double(i) / Double(steps)
            // Cubic easing: more alpha close to the window, fades out quickly
            let alpha = (1 - t) * (1 - t) * (1 - t) * (0.55 / Double(steps))
            let expand = Double(steps - i)
            cairo_set_source_rgba(cr, 0, 0, 0, alpha)
            cairoRoundedRect(cr,
                             x: iX - expand, y: iY - expand,
                             w: iW + 2 * expand, h: iH + 2 * expand,
                             r: cornerR + expand)
            cairo_fill(cr)
        }

        // Punch out the window interior so it's fully transparent
        cairo_set_operator(cr, CAIRO_OPERATOR_CLEAR)
        cairoRoundedRect(cr, x: iX, y: iY, w: iW, h: iH, r: cornerR)
        cairo_fill(cr)
    }
}
