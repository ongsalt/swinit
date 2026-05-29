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

    // Globals bound after roundtrip
    private var compositor: WlCompositor?
    private var xdgWmBase: XdgWmBase?
    private var seat: WlSeat?
    private var pointer: WlPointer?
    private var keyboard: WlKeyboard?

    // Surface ID → window, for routing input events
    private var windows: [UInt32: WaylandWindow] = [:]
    // Surface currently under pointer / holding keyboard focus
    private var pointerWindowId: WindowId? = nil
    private var keyboardWindowId: WindowId? = nil
    // Serial of the last seat event (for interactive ops)
    private var lastPointerSerial: UInt32 = 0
    private var lastKeyboardSerial: UInt32 = 0
    // Accumulated modifiers
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
            seat = try globals.bind(version: 1...9, type: WlSeat.self)

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

        let observer = RunLoopObserver(on: [.beforeWaiting, .afterWaiting]) { [weak self] activity in
            guard let self else { return }
            if activity == CFRunLoopActivity.afterWaiting {
                try? self.connection.dispatchPending()
            } else {
                try? self.connection.flush()
            }
        }

        let source = connection.makeReadSource()
        source.setEventHandler(qos: .userInteractive) { [weak self] in
            try? self?.connection.dispatchPending()
        }
        source.activate()

        try? connection.flush()

        observer.start()
        RunLoop.main.run()
        observer.stop()
        source.suspend()
    }

    public func stop() {
        CFRunLoopStop(CFRunLoopGetCurrent())
    }

    // MARK: - Input setup

    private func setupSeatInput() {
        guard let seat else { return }

        pointer = try? seat.getPointer()
        keyboard = try? seat.getKeyboard()

        setupPointerEvents()
        setupKeyboardEvents()
    }

    private func findWindow(bySurfaceId surfaceId: UInt32) -> WaylandWindow? {
        windows[surfaceId]
    }

    private func setupPointerEvents() {
        pointer?.onEvent = { [weak self] event in
            guard let self else { return }
            switch event {
            case .enter(let serial, let surface, let x, let y):
                lastPointerSerial = serial
                if let window = findWindow(bySurfaceId: surface.id) {
                    pointerWindowId = window.id
                    sendWindowEvent(.cursorEntered(deviceId: DeviceId()), to: window.id)
                    let pos = PhysicalPosition(x, y)
                    sendWindowEvent(.cursorMoved(deviceId: DeviceId(), position: pos), to: window.id)
                }

            case .leave(let serial, let surface):
                lastPointerSerial = serial
                if let window = findWindow(bySurfaceId: surface.id) {
                    sendWindowEvent(.cursorLeft(deviceId: DeviceId()), to: window.id)
                }
                pointerWindowId = nil

            case .motion(_, let x, let y):
                if let windowId = pointerWindowId {
                    let pos = PhysicalPosition(x, y)
                    sendWindowEvent(.cursorMoved(deviceId: DeviceId(), position: pos), to: windowId)
                }

            case .button(let serial, _, let button, let state):
                lastPointerSerial = serial
                guard let windowId = pointerWindowId else { return }
                let mouseButton = linuxButtonToMouseButton(button)
                let elementState: ElementState = state == 1 ? .pressed : .released
                sendWindowEvent(
                    .mouseInput(deviceId: DeviceId(), state: elementState, button: mouseButton),
                    to: windowId)

            case .axis(_, let axis, let value):
                guard let windowId = pointerWindowId else { return }
                // axis 0 = vertical scroll, axis 1 = horizontal scroll
                let delta: MouseScrollDelta = axis == 0
                    ? .pixel(x: 0, y: -value)
                    : .pixel(x: -value, y: 0)
                sendWindowEvent(
                    .mouseWheel(deviceId: DeviceId(), delta: delta, phase: .moved),
                    to: windowId)

            default:
                break
            }
        }
    }

    private func setupKeyboardEvents() {
        keyboard?.onEvent = { [weak self] event in
            guard let self else { return }
            switch event {
            case .enter(let serial, let surface, _):
                lastKeyboardSerial = serial
                if let window = findWindow(bySurfaceId: surface.id) {
                    keyboardWindowId = window.id
                    sendWindowEvent(.focused(true), to: window.id)
                }

            case .leave(let serial, let surface):
                lastKeyboardSerial = serial
                if let window = findWindow(bySurfaceId: surface.id) {
                    sendWindowEvent(.focused(false), to: window.id)
                }
                keyboardWindowId = nil

            case .key(let serial, _, let key, let state):
                lastKeyboardSerial = serial
                guard let windowId = keyboardWindowId else { return }
                let elementState: ElementState = state == 1 ? .pressed : .released
                let isRepeat = false  // Wayland doesn't send repeat in key event; compositor handles it via keymap
                let keyEvent = KeyEvent(
                    physicalKey: key,
                    logicalKey: key,
                    text: nil,
                    state: elementState,
                    isRepeat: isRepeat
                )
                sendWindowEvent(.modifiersChanged(currentModifiers), to: windowId)
                sendWindowEvent(
                    .keyboardInput(deviceId: DeviceId(), event: keyEvent, isSynthetic: false),
                    to: windowId)

            case .modifiers(_, let depressed, let latched, let locked, _):
                let combined = depressed | latched | locked
                currentModifiers = Modifiers(
                    shift: combined & 1 != 0,
                    control: combined & 4 != 0,
                    alt: combined & 8 != 0,
                    superKey: combined & 64 != 0
                )
                if let windowId = keyboardWindowId {
                    sendWindowEvent(.modifiersChanged(currentModifiers), to: windowId)
                }

            default:
                break
            }
        }
    }

    // MARK: - Helpers

    private func linuxButtonToMouseButton(_ button: UInt32) -> MouseButton {
        switch button {
        case 0x110: return .left    // BTN_LEFT
        case 0x111: return .right   // BTN_RIGHT
        case 0x112: return .middle  // BTN_MIDDLE
        case 0x113: return .back    // BTN_SIDE
        case 0x114: return .forward // BTN_EXTRA
        default: return .other(UInt16(button & 0xFFFF))
        }
    }
}
