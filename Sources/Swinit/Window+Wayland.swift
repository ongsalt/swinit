#if os(Linux)
    import SwinitCore
    import Foundation
    import WaylandClient
    import WaylandClientProtocols
    import SwinitWayland

    extension Window {

        func platformSetTitle(_ title: String) {
            try? toplevel.setTitle(title)
            if let csd, let shm = app?.waylandShm {
                try? csd.update(
                    shm: shm, contentSize: _size, title: title,
                    maximized: isMaximized, activated: isActivated)
                try? surface.commit()
            }
        }

        func platformRequestRedraw() {
            try? surface.damage(x: 0, y: 0, width: Int32(_size.width), height: Int32(_size.height))
            try? surface.commit()
        }

        /// Do nothing - In wayland compositor decides the actual size via configure event.
        func platformRequestResize(to size: Size) {
        }

        func platformFocus() {}

        func platformDestroy() {
            toplevel.onEvent = nil
            xdgSurface.onEvent = nil
            if csd != nil {
                app?.csdRouter.unregister(window: self)
                csd = nil
            }
            try? toplevelDeco?.destroy()
            try? toplevel.destroy()
            try? xdgSurface.destroy()
            try? surface.destroy()
        }

        /// Register a frame callback before presenting on Wayland, so the compositor
        /// can throttle to the display refresh rate.
        public func prePresentNotify() {
            try? surface.frame { _ in }
        }

        func setActivated(_ active: Bool) {
            guard active != isActivated, let csd, let shm = app?.waylandShm else { return }
            isActivated = active
            try? csd.update(
                shm: shm, contentSize: _size, title: _title,
                maximized: isMaximized, activated: active)
            try? surface.commit()
        }

        func handleCSDPress(area: CSDArea, x: Double, y: Double, seat: WlSeat, serial: UInt32) {
            switch area {
            case .titleBar:
                guard let csd else { return }
                let r = csd.buttonRadius
                func hit(_ c: SIMD2<Double>) -> Bool {
                    let dx = x - c.x
                    let dy = y - c.y
                    return dx * dx + dy * dy <= r * r
                }
                if hit(csd.closeCenter) {
                    dispatch(.closeRequested)
                } else if hit(csd.minimizeCenter) {
                    try? toplevel.setMinimized()
                } else if hit(csd.maximizeCenter) {
                    if isMaximized {
                        try? toplevel.unsetMaximized()
                    } else {
                        try? toplevel.setMaximized()
                    }
                } else {
                    try? toplevel.move(seat: seat, serial: serial)
                }
            case .borderTop:
                let grabW = Double(CSDConstants.resizeGrabWidth)
                let cW = Double(_size.width)
                let zone = 20.0
                if x < grabW + zone {
                    try? toplevel.resize(seat: seat, serial: serial, edges: .topLeft)
                } else if x > grabW + cW - zone {
                    try? toplevel.resize(seat: seat, serial: serial, edges: .topRight)
                } else {
                    try? toplevel.resize(seat: seat, serial: serial, edges: .top)
                }
            case .borderLeft:
                try? toplevel.resize(seat: seat, serial: serial, edges: .left)
            case .borderRight:
                try? toplevel.resize(seat: seat, serial: serial, edges: .right)
            case .borderBottom:
                let grabW = Double(CSDConstants.resizeGrabWidth)
                let cW = Double(_size.width)
                let zone = 20.0
                if x < grabW + zone {
                    try? toplevel.resize(seat: seat, serial: serial, edges: .bottomLeft)
                } else if x > grabW + cW - zone {
                    try? toplevel.resize(seat: seat, serial: serial, edges: .bottomRight)
                } else {
                    try? toplevel.resize(seat: seat, serial: serial, edges: .bottom)
                }
            }
        }

        func setupCallbacks() {
            toplevel.onEvent = { [weak self] event in
                guard let self else { return }
                switch event {
                case .configure(let width, let height, let states):
                    let newMax = csdParseStates(states).contains(1)
                    if width > 0 && height > 0 {
                        if csd != nil {
                            // Compositor sends window-geometry size (content + CSD frame).
                            // Subtract the frame to recover the content size.
                            let bW = newMax ? Int32(0) : CSDConstants.borderWidth
                            let tH = CSDConstants.titleBarHeight
                            let bot = newMax ? Int32(0) : CSDConstants.borderWidth
                            pendingToplevelSize = Size(
                                width: UInt32(max(1, Int(width) - 2 * Int(bW))),
                                height: UInt32(max(1, Int(height) - Int(tH) - Int(bot)))
                            )
                        } else {
                            pendingToplevelSize = Size(width: UInt32(width), height: UInt32(height))
                        }
                    } else {
                        pendingToplevelSize = .zero
                    }
                    pendingIsMaximized = newMax
                case .close:
                    dispatch(.closeRequested)
                default: break
                }
            }

            xdgSurface.onEvent = { [weak self] event in
                guard let self, case .configure(let serial) = event else { return }

                let prevMaximized = isMaximized
                isMaximized = pendingIsMaximized
                let newSize = pendingToplevelSize == .zero ? _size : pendingToplevelSize
                let isInitial = !configured
                configured = true

                if let mode = pendingDecoMode {
                    pendingDecoMode = nil
                    if mode == .clientSide { ensureCSD() } else { destroyCSD() }
                }

                if let csd, let shm = app?.waylandShm,
                    newSize != _size || isMaximized != prevMaximized || isInitial
                {
                    try? csd.update(
                        shm: shm, contentSize: newSize, title: _title,
                        maximized: isMaximized, activated: isActivated)
                }

                if csd != nil {
                    let bW = isMaximized ? Int32(0) : CSDConstants.borderWidth
                    let tH = CSDConstants.titleBarHeight
                    let bot = isMaximized ? Int32(0) : CSDConstants.borderWidth
                    try? xdgSurface.setWindowGeometry(
                        x: -bW, y: -tH,
                        width: Int32(newSize.width) + 2 * bW,
                        height: Int32(newSize.height) + tH + bot)
                }

                try? xdgSurface.ackConfigure(serial: serial)

                let sizeChanged = newSize != _size || isInitial
                if sizeChanged { _size = newSize }

                if isMaximized != prevMaximized {
                    dispatch(.stateChanged(isMaximized ? .maximized : .normal))
                }
                if sizeChanged {
                    dispatch(.resized(size: _size, isFinal: true))
                }

                try? surface.commit()
            }
        }

        func setupDecorations() {
            switch decoMode {
            case .none:
                return
            case .clientSide:
                ensureCSD()
            case .auto:
                if let decoManager = app?.waylandDecoManager {
                    guard let deco = try? decoManager.getToplevelDecoration(toplevel: toplevel)
                    else {
                        ensureCSD()
                        return
                    }
                    toplevelDeco = deco
                    deco.onEvent = { [weak self] event in
                        guard let self, case .configure(let mode) = event else { return }
                        if configured {
                            // xdg_surface.configure already fired — apply the decoration mode
                            // immediately and commit so the change takes effect this frame.
                            if mode == .clientSide { ensureCSD() } else { destroyCSD() }
                            try? surface.commit()
                        } else {
                            pendingDecoMode = mode
                        }
                    }
                    try? deco.setMode(.serverSide)
                } else {
                    ensureCSD()
                }
            }
        }

        func ensureCSD() {
            guard csd == nil,
                let subcompositor = app?.waylandSubcompositor,
                let shm = app?.waylandShm,
                let compositor = app?.waylandCompositor
            else { return }

            guard
                let layer = try? CSDLayer(
                    compositor: compositor, subcompositor: subcompositor,
                    shm: shm, parentSurface: surface, contentSize: _size,
                    title: _title, activated: isActivated)
            else { return }

            csd = layer
            app?.csdRouter.register(window: self, csd: layer)

            let bW = CSDConstants.borderWidth
            let tH = CSDConstants.titleBarHeight
            try? xdgSurface.setWindowGeometry(
                x: -bW, y: -tH,
                width: Int32(_size.width) + 2 * bW,
                height: Int32(_size.height) + tH + bW)
        }

        func destroyCSD() {
            guard csd != nil else { return }
            app?.csdRouter.unregister(window: self)
            csd = nil
            try? xdgSurface.setWindowGeometry(
                x: 0, y: 0,
                width: Int32(_size.width), height: Int32(_size.height))
        }
    }

    private func csdParseStates(_ data: UnsafeRawBufferPointer) -> Set<UInt32> {
        var result = Set<UInt32>()
        let count = data.count / MemoryLayout<UInt32>.size
        for i in 0..<count {
            result.insert(data.load(fromByteOffset: i * 4, as: UInt32.self))
        }
        return result
    }

#endif
