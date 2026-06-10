import SwiftWayland
import WaylandProtocols
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
    static let cornerRadius: Int32 = 8

    static let buttonRadius: Double = 7.0
    static let buttonSpacing: Double = 5.0
    static let buttonMarginLeft: Double = 12.0

    // Active state colors
    static let titleBarColor: UInt32 = 0xFF2B2B2B
    static let borderColor: UInt32 = 0xFF1E1E1E
    static let closeButtonColor: UInt32 = 0xFFFF5F57
    static let minimizeButtonColor: UInt32 = 0xFFFFBD2E
    static let maximizeButtonColor: UInt32 = 0xFF28CA41

    // Inactive state colors
    static let titleBarInactiveColor: UInt32 = 0xFF3D3D3D
    static let buttonInactiveColor: UInt32 = 0xFF6D6D6D
}

// MARK: - Reusable SHM buffer

final class SHMLayer {
    private var pool: WlShmPool?
    private var buffer: WlBuffer?
    private var mappedData: UnsafeMutableRawPointer?
    private var mappedSize: Int = 0
    private var cachedWidth: Int = 0
    private var cachedHeight: Int = 0

    deinit {
        if let d = mappedData, mappedSize > 0 { munmap(d, mappedSize) }
        try? buffer?.destroy()
        try? pool?.destroy()
    }

    /// Returns a pixel pointer and matching WlBuffer, resizing SHM as needed.
    func prepare(shm: WlShm, width: Int, height: Int) -> (UnsafeMutablePointer<UInt32>, WlBuffer)? {
        guard width > 0, height > 0 else { return nil }
        let needed = width * 4 * height
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
                  let b = try? p.createBuffer(offset: 0, width: Int32(width), height: Int32(height),
                                              stride: Int32(width * 4), format: .argb8888)
            else { return nil }
            let mapped = mmap(nil, needed, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0)
            pool = p; buffer = b; mappedSize = needed
            cachedWidth = width; cachedHeight = height
            mappedData = (mapped != MAP_FAILED) ? mapped : nil
        }
        guard let ptr = mappedData, let buf = buffer else { return nil }
        return (ptr.bindMemory(to: UInt32.self, capacity: width * height), buf)
    }
}

// MARK: - CSD Layer

/// Manages all client-side decoration subsurfaces (title bar, borders, shadow).
@MainActor
final class CSDLayer {
    // Surfaces + subsurfaces
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

    // SHM layers (one per surface)
    private let titleBarLayer = SHMLayer()
    private let leftLayer = SHMLayer()
    private let rightLayer = SHMLayer()
    private let bottomLayer = SHMLayer()
    private let shadowLayer = SHMLayer()

    // Button hit-test positions (in title-bar surface-local coords)
    private(set) var closeCenter = SIMD2<Double>.zero
    private(set) var minimizeCenter = SIMD2<Double>.zero
    private(set) var maximizeCenter = SIMD2<Double>.zero
    let buttonRadius: Double = CSDConstants.buttonRadius

    // Surface IDs for EventLoop routing
    var titleBarSurfaceId: UInt32 { titleBarSurface.id }
    var leftSurfaceId: UInt32 { leftSurface.id }
    var rightSurfaceId: UInt32 { rightSurface.id }
    var bottomSurfaceId: UInt32 { bottomSurface.id }

    init(compositor: WlCompositor, subcompositor: WlSubcompositor, shm: WlShm,
         parentSurface: WlSurface, contentSize: SIMD2<UInt>) throws {
        titleBarSurface = try compositor.createSurface()
        leftSurface    = try compositor.createSurface()
        rightSurface   = try compositor.createSurface()
        bottomSurface  = try compositor.createSurface()
        shadowSurface  = try compositor.createSurface()

        titleBarSubsurface = try subcompositor.getSubsurface(surface: titleBarSurface, parent: parentSurface)
        leftSubsurface     = try subcompositor.getSubsurface(surface: leftSurface,     parent: parentSurface)
        rightSubsurface    = try subcompositor.getSubsurface(surface: rightSurface,    parent: parentSurface)
        bottomSubsurface   = try subcompositor.getSubsurface(surface: bottomSurface,   parent: parentSurface)
        shadowSubsurface   = try subcompositor.getSubsurface(surface: shadowSurface,   parent: parentSurface)

        // Shadow lives below the content surface in Z order
        try shadowSubsurface.placeBelow(sibling: parentSurface)

        // Shadow must never eat pointer events
        let emptyRegion = try compositor.createRegion()
        try shadowSurface.setInputRegion(region: emptyRegion)
        try emptyRegion.destroy()

        // Sync mode: all decoration commits are batched with the parent commit
        try titleBarSubsurface.setSync()
        try leftSubsurface.setSync()
        try rightSubsurface.setSync()
        try bottomSubsurface.setSync()
        try shadowSubsurface.setSync()

        try update(shm: shm, contentSize: contentSize, maximized: false, activated: true)
    }

    /// Redraws and repositions all decoration surfaces.
    /// Must be called before the parent surface commits.
    func update(shm: WlShm, contentSize: SIMD2<UInt>, maximized: Bool, activated: Bool) throws {
        let cW = max(Int(contentSize.x), 1)
        let cH = max(Int(contentSize.y), 1)
        let bW = Int(CSDConstants.borderWidth)
        let tH = Int(CSDConstants.titleBarHeight)
        let sM = Int(CSDConstants.shadowMargin)
        let cr = Int(CSDConstants.cornerRadius)

        // Title bar — spans full decorated width, above content
        let tbW = cW + (maximized ? 0 : 2 * bW)
        try titleBarSubsurface.setPosition(x: maximized ? 0 : -Int32(bW), y: -Int32(tH))
        if let (pixels, buf) = titleBarLayer.prepare(shm: shm, width: tbW, height: tH) {
            let bgColor = activated ? CSDConstants.titleBarColor : CSDConstants.titleBarInactiveColor
            csdDrawTitleBar(pixels, width: tbW, height: tH, bgColor: bgColor,
                            cornerRadius: maximized ? 0 : cr, activated: activated)
            // Compute button centers in title-bar surface coords
            let bML = CSDConstants.buttonMarginLeft
            let bR  = CSDConstants.buttonRadius
            let bSp = CSDConstants.buttonSpacing
            let cy  = Double(tH) / 2.0
            closeCenter    = SIMD2(bML + bR, cy)
            minimizeCenter = SIMD2(closeCenter.x    + 2 * bR + bSp, cy)
            maximizeCenter = SIMD2(minimizeCenter.x + 2 * bR + bSp, cy)
            try titleBarSurface.attach(buffer: buf, x: 0, y: 0)
            try titleBarSurface.damage(x: 0, y: 0, width: Int32(tbW), height: Int32(tH))
            try titleBarSurface.commit()
        }

        if maximized {
            // Detach borders and shadow — unmap them from the compositor
            for s in [leftSurface, rightSurface, bottomSurface, shadowSurface] {
                try s.attach(x: 0, y: 0)   // attach(buffer: nil)
                try s.commit()
            }
        } else {
            // Left border
            try leftSubsurface.setPosition(x: -Int32(bW), y: 0)
            if let (px, buf) = leftLayer.prepare(shm: shm, width: bW, height: cH) {
                csdFill(px, count: bW * cH, color: CSDConstants.borderColor)
                try leftSurface.attach(buffer: buf, x: 0, y: 0)
                try leftSurface.damage(x: 0, y: 0, width: Int32(bW), height: Int32(cH))
                try leftSurface.commit()
            }

            // Right border
            try rightSubsurface.setPosition(x: Int32(cW), y: 0)
            if let (px, buf) = rightLayer.prepare(shm: shm, width: bW, height: cH) {
                csdFill(px, count: bW * cH, color: CSDConstants.borderColor)
                try rightSurface.attach(buffer: buf, x: 0, y: 0)
                try rightSurface.damage(x: 0, y: 0, width: Int32(bW), height: Int32(cH))
                try rightSurface.commit()
            }

            // Bottom border (full decorated width)
            let botW = cW + 2 * bW
            try bottomSubsurface.setPosition(x: -Int32(bW), y: Int32(cH))
            if let (px, buf) = bottomLayer.prepare(shm: shm, width: botW, height: bW) {
                csdFill(px, count: botW * bW, color: CSDConstants.borderColor)
                try bottomSurface.attach(buffer: buf, x: 0, y: 0)
                try bottomSurface.damage(x: 0, y: 0, width: Int32(botW), height: Int32(bW))
                try bottomSurface.commit()
            }

            // Shadow — surrounds the entire decorated area
            let shW = cW + 2 * (bW + sM)
            let shH = cH + tH + bW + 2 * sM
            try shadowSubsurface.setPosition(x: -Int32(bW + sM), y: -Int32(tH + sM))
            if let (px, buf) = shadowLayer.prepare(shm: shm, width: shW, height: shH) {
                // Inner rect (opaque window area) in shadow surface coordinates
                csdDrawShadow(px, width: shW, height: shH,
                              innerLeft: sM, innerTop: sM,
                              innerRight: sM + cW + 2 * bW,
                              innerBottom: sM + tH + cH + bW,
                              blur: sM)
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

// MARK: - Drawing helpers

private func csdFill(_ pixels: UnsafeMutablePointer<UInt32>, count: Int, color: UInt32) {
    for i in 0..<count { pixels[i] = color }
}

private func csdDrawCircle(_ pixels: UnsafeMutablePointer<UInt32>,
                           width: Int, height: Int,
                           cx: Double, cy: Double, r: Double, color: UInt32) {
    let x0 = max(0, Int(cx - r) - 1)
    let x1 = min(width - 1, Int(cx + r) + 1)
    let y0 = max(0, Int(cy - r) - 1)
    let y1 = min(height - 1, Int(cy + r) + 1)
    guard x0 <= x1, y0 <= y1 else { return }
    for y in y0...y1 {
        for x in x0...x1 {
            let dx = Double(x) + 0.5 - cx
            let dy = Double(y) + 0.5 - cy
            if dx * dx + dy * dy <= r * r {
                pixels[y * width + x] = color
            }
        }
    }
}

private func csdDrawTitleBar(_ pixels: UnsafeMutablePointer<UInt32>,
                             width: Int, height: Int,
                             bgColor: UInt32, cornerRadius: Int, activated: Bool) {
    let cr = cornerRadius
    for y in 0..<height {
        for x in 0..<width {
            if cr > 0 {
                // Top-left rounded corner
                if x < cr && y < cr {
                    let dx = Double(cr - x) - 0.5
                    let dy = Double(cr - y) - 0.5
                    if dx * dx + dy * dy > Double(cr * cr) { pixels[y * width + x] = 0; continue }
                }
                // Top-right rounded corner
                if x >= width - cr && y < cr {
                    let dx = Double(x - (width - cr)) + 0.5
                    let dy = Double(cr - y) - 0.5
                    if dx * dx + dy * dy > Double(cr * cr) { pixels[y * width + x] = 0; continue }
                }
            }
            pixels[y * width + x] = bgColor
        }
    }

    let bR  = CSDConstants.buttonRadius
    let bSp = CSDConstants.buttonSpacing
    let bML = CSDConstants.buttonMarginLeft
    let cy  = Double(height) / 2.0
    let closeX = bML + bR
    let minX   = closeX + 2 * bR + bSp
    let maxX   = minX   + 2 * bR + bSp

    let closeColor    = activated ? CSDConstants.closeButtonColor    : CSDConstants.buttonInactiveColor
    let minimizeColor = activated ? CSDConstants.minimizeButtonColor : CSDConstants.buttonInactiveColor
    let maximizeColor = activated ? CSDConstants.maximizeButtonColor : CSDConstants.buttonInactiveColor

    csdDrawCircle(pixels, width: width, height: height, cx: closeX, cy: cy, r: bR, color: closeColor)
    csdDrawCircle(pixels, width: width, height: height, cx: minX,   cy: cy, r: bR, color: minimizeColor)
    csdDrawCircle(pixels, width: width, height: height, cx: maxX,   cy: cy, r: bR, color: maximizeColor)
}

private func csdDrawShadow(_ pixels: UnsafeMutablePointer<UInt32>,
                           width: Int, height: Int,
                           innerLeft: Int, innerTop: Int,
                           innerRight: Int, innerBottom: Int,
                           blur: Int) {
    let blurF = Double(blur)
    for y in 0..<height {
        for x in 0..<width {
            let inside = x >= innerLeft && x < innerRight && y >= innerTop && y < innerBottom
            if inside { pixels[y * width + x] = 0; continue }
            let dx = max(innerLeft - x, 0, x - innerRight + 1)
            let dy = max(innerTop  - y, 0, y - innerBottom + 1)
            let dist = (dx == 0) ? Double(dy) : (dy == 0) ? Double(dx) : sqrt(Double(dx * dx + dy * dy))
            if dist >= blurF {
                pixels[y * width + x] = 0
            } else {
                let t = 1.0 - dist / blurF
                // Cubic falloff, black color, straight alpha
                let alpha = UInt32(160.0 * t * t * t)
                pixels[y * width + x] = (alpha << 24)
            }
        }
    }
}
