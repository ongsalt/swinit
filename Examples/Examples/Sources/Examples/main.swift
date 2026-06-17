import Swinit

// MARK: - Demo app

@MainActor
final class Demo: AppDelegate {

    // Hold windows by ID so close() from inside onEvent is safe —
    // removeValue happens after the event returns.
    var windows: [WindowId: Window] = [:]

    #if os(Linux)
    var renderers: [WindowId: ShmRenderer] = [:]
    #endif

    // MARK: Lifecycle

    func canCreateSurfaces(_ app: App) {
        // This is the ONLY safe place to create windows. On Android this fires
        // multiple times (each time the native surface becomes available again);
        // on desktop it fires once at startup.
        openMainWindow(app)
    }

    func destroySurfaces(_ app: App) {
        // Drop GPU resources here. On Android the native window is destroyed
        // immediately after this returns; on desktop it fires at quit.
        #if os(Linux)
        renderers.removeAll()
        #endif
    }

    func appResumed(_ app: App)   { print("app resumed")   }
    func appSuspended(_ app: App) { print("app suspended") }

    func windowEvent(_ app: App, window: Window, event: WindowEvent) {
        // Global handler — fires after the per-window onEvent closure.
        // Useful for app-level logic that spans all windows.
        if case .destroyed = event, windows.isEmpty {
            app.quit()
        }
    }

    // MARK: Window setup

    private func openMainWindow(_ app: App) {
        let win = app.openWindow(.init(
            title: "example",
            size: .init(width: 1280, height: 720)
        ))

        #if os(Linux)
        // Wayland: create a SHM software renderer using the window's surface.
        // Real apps would pass win.surface / win.display to wgpu, EGL, or Vulkan.
        if let shm = app.shm {
            renderers[win.id] = ShmRenderer(shm: shm)
        }
        #endif

        #if os(Windows)
        // Follow the system dark/light mode. Uncomment to opt into Mica:
        // win.drawUnderTitleBar = true
        // win.backdropStyle = .mica
        #endif

        windows[win.id] = win

        win.onEvent = { [weak self, weak win] event in
            guard let self, let win else { return }
            self.handle(event: event, window: win, app: app)
        }
    }

    private func handle(event: WindowEvent, window win: Window, app: App) {
        switch event {

        case .resized(let size, let isFinal):
            guard isFinal else { return }
            #if os(Linux)
            // Register a frame callback before presenting so the compositor
            // can throttle us to the display refresh rate.
            renderers[win.id]?.render(
                to: win.surface,
                width: Int(size.width),
                height: Int(size.height))
            #endif

        case .redrawRequested:
            #if os(Linux)
            renderers[win.id]?.render(
                to: win.surface,
                width: Int(win.size.width),
                height: Int(win.size.height))
            #endif

        case .stateChanged(let state):
            print(win.title, "→ state:", state)

        case .focused(let gained):
            print(win.title, gained ? "focused" : "unfocused")

        case .closeRequested:
            windows.removeValue(forKey: win.id)
            #if os(Linux)
            renderers.removeValue(forKey: win.id)
            #endif
            win.close()   // fires .destroyed → windowEvent checks if windows is now empty

        case .keyboardInput(_, let key, _) where key.state == .pressed:
            // Press N to open a second window, demonstrating multi-window support.
            if key.logicalKey == 0x6E /* 'n' */ {
                openMainWindow(app)
            }

        default:
            break
        }
    }
}

// MARK: - Entry point

App().run(Demo())
