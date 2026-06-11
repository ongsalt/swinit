import Foundation
import Swinit

@MainActor
final class App: Responder {
    typealias EventLoop = Swinit.EventLoop

    var window: Window?

    #if canImport(SwiftWayland)
    var renderer: ShmRenderer?
    #endif

    func resumed(eventLoop: EventLoop) {
        window = eventLoop.createWindow(attributes: .init(title: "swinit example"))

        #if canImport(SwiftWayland)
        if let shm = eventLoop.shm {
            renderer = ShmRenderer(shm: shm)
        }
        #endif

        #if canImport(SwinitWin32)
        // titleBarAppearance follows the system theme automatically — no override needed.
        // Opt into Mica: requires extending the DWM frame into the client area.
        // window?.drawUnderTitleBar = true
        // window?.backdropStyle = .mica
        #endif
    }

    func windowEvent(eventLoop: EventLoop, window: Window, event: WindowEvent) {
        switch event {
        case .resized(let size, _):
            #if canImport(SwiftWayland)
            renderer?.render(to: window.surface,
                             width: Int(size.width), height: Int(size.height))
            #endif

        case .stateChanged(let state):
            print("state →", state)

        case .focused(let focused):
            print(focused ? "focused" : "unfocused")

        case .closeRequested:
            self.window = nil
            eventLoop.stop()

        default:
            print(event)
        }
    }
}

let eventLoop = EventLoop()!
let app = App()
eventLoop.run(app)
