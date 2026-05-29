import Foundation
import Swinit

#if canImport(SwiftWayland)
import SwiftWayland
import WaylandProtocols
import Glibc

final class ShmRenderer: @unchecked Sendable {
    private let shm: WlShm
    private var pool: WlShmPool?
    private var buffer: WlBuffer?
    private var bufferData: UnsafeMutableRawPointer?
    private var mappedSize: Int = 0

    init(shm: WlShm) {
        self.shm = shm
    }

    deinit {
        if let bufferData, mappedSize > 0 { munmap(bufferData, mappedSize) }
        try? buffer?.destroy()
        try? pool?.destroy()
    }

    func render(to surface: WlSurface, width: Int, height: Int) {
        let stride = width * 4
        let needed = stride * height

        if needed != mappedSize {
            recreate(width: width, height: height, stride: stride, size: needed)
        }

        if let bufferData {
            fillGradient(bufferData, width: width, height: height)
        }

        guard let buffer else { return }
        try? surface.attach(buffer: buffer, x: 0, y: 0)
        try? surface.damage(x: 0, y: 0, width: Int32(width), height: Int32(height))
        try? surface.commit()
    }

    private func recreate(width: Int, height: Int, stride: Int, size: Int) {
        if let bufferData, mappedSize > 0 { munmap(bufferData, mappedSize) }
        try? buffer?.destroy()
        try? pool?.destroy()
        bufferData = nil; buffer = nil; pool = nil; mappedSize = 0

        let name = "/swinit-\(UInt64.random(in: .min ... .max))"
        let fd = shm_open(name, O_RDWR | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
        guard fd != -1 else { return }
        _ = shm_unlink(name)
        guard ftruncate(fd, off_t(size)) == 0 else { close(fd); return }

        let fh = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        let p = try? shm.createPool(fd: fh, size: Int32(size))
        let b = try? p?.createBuffer(
            offset: 0,
            width: Int32(width), height: Int32(height), stride: Int32(stride),
            format: WlShm.Format.xrgb8888.rawValue
        )
        let mapped = mmap(nil, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0)
        _ = fh  // keep fd alive until after mmap

        pool = p; buffer = b; mappedSize = size
        bufferData = (mapped != MAP_FAILED) ? mapped : nil
    }

    private func fillGradient(_ ptr: UnsafeMutableRawPointer, width: Int, height: Int) {
        let pixels = ptr.bindMemory(to: UInt32.self, capacity: width * height)
        let w = max(width - 1, 1), h = max(height - 1, 1)
        for y in 0..<height {
            for x in 0..<width {
                let r = UInt32(x * 255 / w)
                let g = UInt32(y * 255 / h)
                pixels[y * width + x] = 0xFF00_0000 | (r << 16) | (g << 8) | 64
            }
        }
    }
}
#endif

class AppResponder: Swinit.Responder {
    typealias EventLoop = Swinit.EventLoop

    var window: Window?

    #if canImport(SwiftWayland)
    var renderer: ShmRenderer?
    #endif

    func resumed(eventLoop: EventLoop) {
        window = eventLoop.createWindow(attributes: .init(title: "swinit – shm example"))

        #if canImport(SwiftWayland)
        if let shm = try? eventLoop.globals?.bind(version: 2...2, type: WlShm.self) {
            renderer = ShmRenderer(shm: shm)
        }
        // Synchronously process the initial configure so the window renders
        // before the RunLoop starts (avoids a blank frame on first show).
        #endif

        #if canImport(SwinitWin32)
        window?.drawUnderTitleBar = true
        window?.backdropStyle = .mica
        #endif
    }

    func windowEvent(eventLoop: EventLoop, windowId: WindowId, event: WindowEvent) {
        switch event {
        // Fired after xdg_surface::configure is ack'd — safe to attach a buffer here.
        case .resized(let size, _):
            #if canImport(SwiftWayland)
            if let surface = window?.surface, let renderer {
                renderer.render(to: surface, width: Int(size.width), height: Int(size.height))
            }
            #endif

        case .closeRequested:
            window = nil
            eventLoop.stop()

        default:
            break
        }
    }
}

let eventLoop = EventLoop()!
let responder = AppResponder()
eventLoop.run(responder)
