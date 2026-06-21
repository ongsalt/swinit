#if os(Linux)
    import SwinitCore
    import Foundation
    import CoreFoundation
    import WaylandClient
    import WaylandClientProtocols
    import SwinitWayland

    extension EventLoop {

        func platformRun() {
            let conn = Connection()
            connection = conn

            do {
                let g = try Globals(connection: conn)
                waylandCompositor = try g.bind(to: WlCompositor.self, version: 6...6)
                xdgWmBase = try g.bind(to: XdgWmBase.self, version: 6...7)
                seat = try? g.bind(to: WlSeat.self, version: 1...9)
                waylandDecoManager = try? g.bind(to: ZxdgDecorationManagerV1.self, version: 1...1)
                waylandSubcompositor = try? g.bind(to: WlSubcompositor.self, version: 1...1)
                waylandShm = try? g.bind(to: WlShm.self, version: 1...2)
                waylandFractionalScaleManager = try? g.bind(to: WpFractionalScaleManagerV1.self, version: 1...1)
            } catch {
                fatalError("Failed to bind Wayland globals: \(error)")
            }

            xdgWmBase?.onEvent = { [weak self] event in
                guard let self, case .ping(let serial) = event else { return }
                try? self.xdgWmBase?.pong(serial: serial)
            }

            conn.roundtrip()
            setupInput()
            conn.roundtrip()

            delegate?.canCreateSurfaces(self)
            delegate?.appResumed(self)

            connectionWatch = conn.attach()
            CFRunLoopRun()
            connectionWatch = nil
        }

        func platformOpenWindow(_ attributes: WindowAttributes) -> Window {
            guard let compositor = waylandCompositor, let xdgWmBase else {
                fatalError("openWindow() must be called from canCreateSurfaces(_:)")
            }
            let id = WindowId.generate()
            let surface = try! compositor.createSurface()
            let xdgSurf = try! xdgWmBase.getXdgSurface(surface: surface)
            let toplevel = try! xdgSurf.getToplevel()

            let window = Window(
                id: id, eventLoop: self, attributes: attributes,
                surface: surface, xdgSurface: xdgSurf, toplevel: toplevel)
            if let manager = waylandFractionalScaleManager {
                window.fractionalScale = try? manager.getFractionalScale(surface: surface)
            }
            window.setupScaleCallbacks()
            windows[id] = window
            surfaceToWindow[surface.id] = id
            // No roundtrip — configure fires naturally in the run loop AFTER the caller
            // has set up win.onEvent and any renderers.
            return window
        }

        func platformQuit() {
            CFRunLoopStop(CFRunLoopGetCurrent())
        }

        func platformWindowRemoved(id: WindowId) {
            surfaceToWindow = surfaceToWindow.filter { $0.value != id }
            if pointerWindow?.id == id {
                #if WaylandCSD
                if csdRouter.activeArea == .titleBar { pointerWindow?.clearCSDHover() }
                csdRouter.reset()
                #endif
                pointerWindow = nil
            }
            if keyboardWindow?.id == id { keyboardWindow = nil }
        }

        func findWindow(bySurfaceId surfaceId: UInt32) -> Window? {
            guard let id = surfaceToWindow[surfaceId] else { return nil }
            return windows[id]
        }

        private func setupInput() {
            guard let seat else { return }
            pointer = try? seat.getPointer()
            keyboard = try? seat.getKeyboard()
            setupPointerEvents()
            setupKeyboardEvents()
        }

        private func setupPointerEvents() {
            pointer?.onEvent = { [weak self] event in
                guard let self else { return }
                switch event {
                case .enter(_, let surface, let x, let y):
                    guard let surface else { return }
                    #if WaylandCSD
                    if csdRouter.activeArea == .titleBar { pointerWindow?.clearCSDHover() }
                    csdRouter.reset()
                    if let win = findWindow(bySurfaceId: surface.id) {
                        pointerWindow = win
                        win.dispatch(.cursorEntered(deviceId: .placeholder))
                        win.dispatch(
                            .cursorMoved(deviceId: .placeholder, position: PhysicalPosition(x, y)))
                    } else if let (win, _) = csdRouter.enter(surfaceId: surface.id, x: x, y: y) {
                        pointerWindow = win
                    } else {
                        pointerWindow = nil
                    }
                    #else
                    if let win = findWindow(bySurfaceId: surface.id) {
                        pointerWindow = win
                        win.dispatch(.cursorEntered(deviceId: .placeholder))
                        win.dispatch(
                            .cursorMoved(deviceId: .placeholder, position: PhysicalPosition(x, y)))
                    } else {
                        pointerWindow = nil
                    }
                    #endif

                case .leave(_, let surface):
                    guard let surface else { return }
                    if let win = findWindow(bySurfaceId: surface.id) {
                        win.dispatch(.cursorLeft(deviceId: .placeholder))
                    }
                    #if WaylandCSD
                    if csdRouter.activeArea == .titleBar { pointerWindow?.clearCSDHover() }
                    csdRouter.reset()
                    #endif
                    pointerWindow = nil

                case .motion(_, let x, let y):
                    #if WaylandCSD
                    if csdRouter.activeArea != nil {
                        csdRouter.move(x: x, y: y)
                        if csdRouter.activeArea == .titleBar {
                            pointerWindow?.updateCSDHover(x: x, y: y)
                        }
                    } else if let win = pointerWindow {
                        win.dispatch(
                            .cursorMoved(deviceId: .placeholder, position: PhysicalPosition(x, y)))
                    }
                    #else
                    if let win = pointerWindow {
                        win.dispatch(
                            .cursorMoved(deviceId: .placeholder, position: PhysicalPosition(x, y)))
                    }
                    #endif

                case .button(let serial, _, let button, let state):
                    #if WaylandCSD
                    if let area = csdRouter.activeArea, let win = pointerWindow, state == .pressed {
                        if button == 0x110 {
                            win.handleCSDPress(
                                area: area, x: csdRouter.x, y: csdRouter.y,
                                seat: self.seat!, serial: serial)
                        } else if button == 0x111, area == .titleBar {
                            try? win.toplevel.showWindowMenu(
                                seat: self.seat!, serial: serial,
                                x: Int32(csdRouter.x), y: Int32(csdRouter.y) - CSDConstants.titleBarHeight)
                        }
                    } else if csdRouter.activeArea == nil, let win = pointerWindow {
                        win.dispatch(
                            .mouseInput(
                                deviceId: .placeholder,
                                state: state == .pressed ? .pressed : .released,
                                button: linuxButton(button)))
                    }
                    #else
                    if let win = pointerWindow {
                        win.dispatch(
                            .mouseInput(
                                deviceId: .placeholder,
                                state: state == .pressed ? .pressed : .released,
                                button: linuxButton(button)))
                    }
                    _ = serial
                    #endif

                case .axis(_, let axis, let value):
                    let delta: MouseScrollDelta =
                        axis == .verticalScroll
                        ? .pixel(x: 0, y: -value) : .pixel(x: -value, y: 0)
                    #if WaylandCSD
                    if csdRouter.activeArea == nil, let win = pointerWindow {
                        win.dispatch(.mouseWheel(deviceId: .placeholder, delta: delta, phase: .moved))
                    }
                    #else
                    if let win = pointerWindow {
                        win.dispatch(.mouseWheel(deviceId: .placeholder, delta: delta, phase: .moved))
                    }
                    #endif

                default: break
                }
            }
        }

        private func setupKeyboardEvents() {
            keyboard?.onEvent = { [weak self] event in
                guard let self else { return }
                switch event {
                case .enter(_, let surface, _):
                    guard let surface else { return }
                    if let win = findWindow(bySurfaceId: surface.id) {
                        keyboardWindow = win
                        win.dispatch(.focused(true))
                    }
                case .leave(_, let surface):
                    guard let surface else { return }
                    if let win = findWindow(bySurfaceId: surface.id) {
                        win.dispatch(.focused(false))
                    }
                    keyboardWindow = nil
                case .key(_, _, let key, let state):
                    if let win = keyboardWindow {
                        let ev = KeyEvent(
                            physicalKey: key, logicalKey: key,
                            state: state == .pressed ? .pressed : .released,
                            isRepeat: false)
                        win.dispatch(.modifiersChanged(currentModifiers))
                        win.dispatch(
                            .keyboardInput(deviceId: .placeholder, event: ev, isSynthetic: false))
                    }
                case .modifiers(_, let depressed, let latched, let locked, _):
                    let combined = depressed | latched | locked
                    currentModifiers = Modifiers(
                        shift: combined & 1 != 0,
                        control: combined & 4 != 0,
                        alt: combined & 8 != 0,
                        superKey: combined & 64 != 0)
                    if let win = keyboardWindow {
                        win.dispatch(.modifiersChanged(currentModifiers))
                    }
                default: break
                }
            }
        }

        private func linuxButton(_ button: UInt32) -> MouseButton {
            switch button {
            case 0x110: return .left
            case 0x111: return .right
            case 0x112: return .middle
            case 0x113: return .back
            case 0x114: return .forward
            default: return .other(UInt16(button & 0xFFFF))
            }
        }
    }

    // MARK: - CSD input router

    #if WaylandCSD
    @MainActor
    struct CSDInputRouter: ~Copyable {
        private struct Entry {
            weak var window: Window?
            let area: CSDArea
        }
        private var surfaces: [UInt32: Entry] = [:]
        private(set) weak var activeWindow: Window?
        private(set) var activeArea: CSDArea?
        private(set) var x: Double = 0
        private(set) var y: Double = 0

        mutating func register(window: Window, csd: CSDLayer) {
            surfaces[csd.titleBarSurfaceId] = Entry(window: window, area: .titleBar)
            surfaces[csd.topSurfaceId] = Entry(window: window, area: .borderTop)
            surfaces[csd.leftSurfaceId] = Entry(window: window, area: .borderLeft)
            surfaces[csd.rightSurfaceId] = Entry(window: window, area: .borderRight)
            surfaces[csd.bottomSurfaceId] = Entry(window: window, area: .borderBottom)
        }

        mutating func unregister(window: Window) {
            surfaces = surfaces.filter { $0.value.window !== window }
            if activeWindow === window { reset() }
        }

        mutating func enter(surfaceId: UInt32, x: Double, y: Double) -> (Window, CSDArea)? {
            guard let entry = surfaces[surfaceId], let win = entry.window else { return nil }
            activeWindow = win
            activeArea = entry.area
            self.x = x
            self.y = y
            return (win, entry.area)
        }

        mutating func move(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
        mutating func reset() {
            activeWindow = nil
            activeArea = nil
        }
    }
    #endif

#endif
