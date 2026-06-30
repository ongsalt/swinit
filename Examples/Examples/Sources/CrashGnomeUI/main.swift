import Swinit
import WaylandClient
import WaylandClientProtocols

@MainActor
final class App: EventLoopDelegate {
    var window: Window?
    var renderer: ButtonRenderer?
    var hovered = false

    func canCreateSurfaces(_ loop: EventLoop) {
        window = loop.openWindow(.init(
            title: "Crash Gnome",
            size: .init(width: 400, height: 240)))
        if let shm = loop.shm {
            renderer = ButtonRenderer(shm: shm)
        }
        window?.requestRedraw()
    }

    func windowEvent(_ loop: EventLoop, window: Window, event: WindowEvent) {
        switch event {
        case .closeRequested:
            window.close()
            loop.quit()

        case .cursorMoved(_, let pos):
            let newHovered = isOverButton(
                x: pos.x, y: pos.y,
                winW: Int(window.size.width), winH: Int(window.size.height))
            if newHovered != hovered {
                hovered = newHovered
                window.requestRedraw()
            }

        case .cursorLeft:
            if hovered { hovered = false; window.requestRedraw() }

        case .mouseInput(_, .pressed, .left) where hovered:
            crashGnome()

        case .redrawRequested:
            renderer?.draw(
                surface: window.surface,
                w: Int(window.size.width), h: Int(window.size.height),
                hovered: hovered)

        case .resized(let size, isFinal: true):
            renderer?.draw(
                surface: window.surface,
                w: Int(size.width), h: Int(size.height),
                hovered: hovered)

        default: break
        }
    }

    private func crashGnome() {
        // Open a second Wayland connection and call wl_seat_get_touch without
        // checking capabilities — protocol error since wl_seat v5.
        // On GNOME/mutter this kills the compositor and takes the session down.
        let conn = Connection()
        guard let globals = try? Globals(connection: conn),
              let seat = try? globals.bind(to: WlSeat.self, version: 5...9)
        else { return }
        conn.roundtrip()          // seat.capabilities fires — we ignore it
        _ = try? seat.getTouch()  // protocol error if no touch capability
        conn.roundtrip()          // compositor processes the bad request
    }
}

EventLoop().run(App())
