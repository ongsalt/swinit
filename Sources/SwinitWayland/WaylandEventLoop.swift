import CoreFoundation
import Foundation
import SwiftWayland
import WaylandProtocols
import SwinitCommon

public final class WaylandEventLoop: IEventLoop {
    public typealias Window = WaylandWindow

    let controlFlow: ControlFlow
    public let connection: Connection

    var responder: (any Responder<WaylandEventLoop>)? = nil

    private var compositor: WlCompositor?
    private var xdgWmBase: XdgWmBase?
    private var seat: WlSeat?
    private var pointer: WlPointer?
    private var keyboard: WlKeyboard?
    public private(set) var globals: Globals?

    // Surface ID → window for input routing
    private var windows: [UInt32: WaylandWindow] = [:]
    private var pointerWindowId: WindowId? = nil
    private var keyboardWindowId: WindowId? = nil
    private var currentModifiers: Modifiers = Modifiers()

    public init?(controlFlow: ControlFlow = .default) {
        self.controlFlow = controlFlow
        self.connection = Connection()
    }

    public func createWindow(attributes: WindowAttributes) -> WaylandWindow {
        guard let compositor, let xdgWmBase else {
            fatalError("createWindow called before event loop globals are ready")
        }
        let surface = try! compositor.createSurface()
        let xdgSurface = try! xdgWmBase.getXdgSurface(surface: surface)
        let toplevel = try! xdgSurface.getToplevel()
        let window = WaylandWindow(
            eventLoop: self,
            attributes: attributes,
            surface: surface,
            xdgSurface: xdgSurface,
            toplevel: toplevel
        )
        windows[surface.id] = window
        connection.roundtrip()
        return window
    }

    public func sendWindowEvent(_ event: WindowEvent, to windowId: WindowId) {
        guard let responder else {
            fatalError("sendWindowEvent called before responder is set: \(event)")
        }
        responder.windowEvent(eventLoop: self, windowId: windowId, event: event)
    }

    public func run<R>(_ responder: R)
    where WaylandEventLoop == R.EventLoop, R: SwinitCommon.Responder {
        self.responder = responder

        do {
            let globals = try Globals(connection: connection)
            try connection.roundtrip()

            compositor = try globals.bind(version: 6...6, type: WlCompositor.self)
            xdgWmBase = try globals.bind(version: 6...7, type: XdgWmBase.self)
            seat = try? globals.bind(version: 1...9, type: WlSeat.self)
            self.globals = globals

            xdgWmBase!.onEvent = { [weak self] event in
                guard let self, case .ping(let serial) = event else { return }
                try? self.xdgWmBase?.pong(serial: serial)
            }

            try connection.roundtrip()
            setupSeatInput()
            try connection.roundtrip()
        } catch {
            fatalError("Failed to initialize Wayland globals: \(error)")
        }

        responder.resumed(eventLoop: self)

        // When the Wayland fd is readable: read events from the socket,
        // dispatch them (running our callbacks which may buffer new requests),
        // then immediately flush those replies back to the compositor.
        let source = connection.makeReadSource()
        source.setEventHandler(qos: .userInteractive) { [weak self] in
            guard let self else { return }
            connection.readEvents()
            try? connection.dispatchPending()
            try? connection.flush()
        }
        source.activate()

        // Before the RunLoop sleeps: drain any already-queued events, then
        // call prepareRead() to announce we are ready for the next read cycle,
        // and flush any requests buffered by user code (e.g. requestRedraw).
        let observer = RunLoopObserver(on: [.beforeWaiting]) { [weak self] _ in
            guard let self else { return }
            while !connection.prepareRead() {
                try? connection.dispatchPending()
                try? connection.flush()
            }
            try? connection.flush()
        }

        try? connection.flush()
        observer.start()
        RunLoop.main.run()
        observer.stop()
        source.suspend()
        connection.cancelRead()
    }

    public func stop() {
        CFRunLoopStop(CFRunLoopGetCurrent())
    }

    // MARK: - Input

    private func setupSeatInput() {
        guard let seat else { return }
        pointer = try? seat.getPointer()
        keyboard = try? seat.getKeyboard()
        setupPointerEvents()
        setupKeyboardEvents()
    }

    private func findWindow(bySurfaceId id: UInt32) -> WaylandWindow? {
        windows[id]
    }

    private func setupPointerEvents() {
        pointer?.onEvent = { [weak self] event in
            guard let self else { return }
            switch event {
            case .enter(_, let surface, let x, let y):
                if let window = findWindow(bySurfaceId: surface.id) {
                    pointerWindowId = window.id
                    sendWindowEvent(.cursorEntered(deviceId: DeviceId()), to: window.id)
                    sendWindowEvent(.cursorMoved(deviceId: DeviceId(), position: PhysicalPosition(x, y)), to: window.id)
                }
            case .leave(_, let surface):
                if let window = findWindow(bySurfaceId: surface.id) {
                    sendWindowEvent(.cursorLeft(deviceId: DeviceId()), to: window.id)
                }
                pointerWindowId = nil
            case .motion(_, let x, let y):
                if let wid = pointerWindowId {
                    sendWindowEvent(.cursorMoved(deviceId: DeviceId(), position: PhysicalPosition(x, y)), to: wid)
                }
            case .button(_, _, let button, let state):
                if let wid = pointerWindowId {
                    sendWindowEvent(.mouseInput(deviceId: DeviceId(), state: state == 1 ? .pressed : .released, button: linuxButtonToMouseButton(button)), to: wid)
                }
            case .axis(_, let axis, let value):
                if let wid = pointerWindowId {
                    let delta: MouseScrollDelta = axis == 0 ? .pixel(x: 0, y: -value) : .pixel(x: -value, y: 0)
                    sendWindowEvent(.mouseWheel(deviceId: DeviceId(), delta: delta, phase: .moved), to: wid)
                }
            default:
                break
            }
        }
    }

    private func setupKeyboardEvents() {
        keyboard?.onEvent = { [weak self] event in
            guard let self else { return }
            switch event {
            case .enter(_, let surface, _):
                if let window = findWindow(bySurfaceId: surface.id) {
                    keyboardWindowId = window.id
                    sendWindowEvent(.focused(true), to: window.id)
                }
            case .leave(_, let surface):
                if let window = findWindow(bySurfaceId: surface.id) {
                    sendWindowEvent(.focused(false), to: window.id)
                }
                keyboardWindowId = nil
            case .key(_, _, let key, let state):
                if let wid = keyboardWindowId {
                    let keyEvent = KeyEvent(physicalKey: key, logicalKey: key, text: nil, state: state == 1 ? .pressed : .released, isRepeat: false)
                    sendWindowEvent(.modifiersChanged(currentModifiers), to: wid)
                    sendWindowEvent(.keyboardInput(deviceId: DeviceId(), event: keyEvent, isSynthetic: false), to: wid)
                }
            case .modifiers(_, let depressed, let latched, let locked, _):
                let combined = depressed | latched | locked
                currentModifiers = Modifiers(shift: combined & 1 != 0, control: combined & 4 != 0, alt: combined & 8 != 0, superKey: combined & 64 != 0)
                if let wid = keyboardWindowId {
                    sendWindowEvent(.modifiersChanged(currentModifiers), to: wid)
                }
            default:
                break
            }
        }
    }

    private func linuxButtonToMouseButton(_ button: UInt32) -> MouseButton {
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
