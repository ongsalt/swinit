import Swinit

// MARK: - Demo app

@MainActor
final class Demo: EventLoopDelegate {

    // Hold windows by ID
    // removeValue happens after the event returns.
    var windows: [WindowId: Window] = [:]

    #if os(Linux)
    var renderers: [WindowId: ShmRenderer] = [:]
    #endif

    // MARK: Lifecycle

    func canCreateSurfaces(_ eventLoop: EventLoop) {
        // This is the ONLY safe place to create windows. On Android this fires
        // multiple times (each time the native surface becomes available again);
        // on desktop it fires once at startup.
        openMainWindow(eventLoop)
    }

    func appSuspended(_ eventLoop: EventLoop) {
        #if os(Linux)
        renderers.removeAll()
        #endif
    }

    func windowEvent(_ eventLoop: EventLoop, window: Window, event: WindowEvent) {
        switch event {
        case .resized(let size, let isFinal):
            guard isFinal else { return }
            #if os(Linux)
            // Register a frame callback before presenting so the compositor
            // can throttle us to the display refresh rate.
            renderers[window.id]?.render(
                to: window.surface,
                width: Int(size.width),
                height: Int(size.height))
            #endif

        case .redrawRequested:
            #if os(Linux)
            renderers[window.id]?.render(
                to: window.surface,
                width: Int(window.size.width),
                height: Int(window.size.height))
            #endif

        case .stateChanged(let state):
            print(window.title, "→ state:", state)

        case .focused(let gained):
            print(window.title, gained ? "focused" : "unfocused")

        case .closeRequested:
            windows.removeValue(forKey: window.id)
            #if os(Linux)
            renderers.removeValue(forKey: window.id)
            #endif
            window.close()   // fires .destroyed → windowEvent checks if windows is now empty
            if windows.isEmpty {
                eventLoop.quit()
            }

        case .keyboardInput(_, let key, _) where key.state == .pressed:
            // Press N to open a second window, demonstrating multi-window support.
            if key.physicalKey == 49 /* 'n' */ {
                openMainWindow(eventLoop)
            }

        default:
            break
        }
    }

    // MARK: Window setup

    private func openMainWindow(_ eventLoop: EventLoop) {
        let window = eventLoop.openWindow(.init(
            title: "example",
            size: .init(width: 1280, height: 720)
        ))

        #if os(Linux)
        // Wayland: create a SHM software renderer using the window's surface.
        // Real apps would pass window.surface / window.display to wgpu, EGL, or Vulkan.
        if let shm = eventLoop.shm {
            renderers[window.id] = ShmRenderer(shm: shm)
        }
        #endif

        #if os(Windows)
        // Follow the system dark/light mode. Uncomment to opt into Mica:
        // window.drawUnderTitleBar = true
        // window.backdropStyle = .mica
        #endif

        windows[window.id] = window
    }
}

// MARK: - Entry point

Task {
    var i = 1
    while !Task.isCancelled {
        print(i)
        try await Task.sleep(for: .milliseconds(300))
        i += 1
    }
}

EventLoop().run(Demo())
