import CoreFoundation
import Foundation
import SwiftWayland
import WaylandProtocols
import SwinitCore

@MainActor
public final class EventLoop: SwinitCore.EventLoopProtocol {
    public typealias Window = SwinitWayland.Window

    public let connection: Connection
    let controlFlow: ControlFlow
    var responder: (any SwinitCore.Responder<EventLoop>)? = nil

    private var compositor: WlCompositor? = nil
    private var xdgWmBase: XdgWmBase? = nil
    private var seat: WlSeat? = nil
    private var pointer: WlPointer? = nil
    private var keyboard: WlKeyboard? = nil
    public private(set) var globals: Globals? = nil

    private var windows: [UInt32: WeakBox<Window>] = [:]
    private weak var pointerWindow: Window? = nil
    private weak var keyboardWindow: Window? = nil
    private var currentModifiers: Modifiers = Modifiers()

    public init?(controlFlow: ControlFlow = .default) {
        self.controlFlow = controlFlow
        self.connection = Connection()
    }

    public func createWindow(attributes: WindowAttributes) -> Window {
        guard let compositor, let xdgWmBase else {
            fatalError("createWindow called before event loop globals are ready — call inside resumed()")
        }
        let surface = try! compositor.createSurface()
        let xdgSurface = try! xdgWmBase.getXdgSurface(surface: surface)
        let toplevel = try! xdgSurface.getToplevel()
        let window = Window(eventLoop: self, attributes: attributes, surface: surface, xdgSurface: xdgSurface, toplevel: toplevel)
        windows[surface.id] = WeakBox(window)
        connection.roundtrip()
        return window
    }

    @discardableResult
    public func attach<R: SwinitCore.Responder>(_ responder: R) -> SwinitCore.Watch
    where R.EventLoop == EventLoop {
        self.responder = responder

        do {
            let globals = try Globals(connection: connection)
            compositor = try globals.bind(to: WlCompositor.self, version: 6...6)
            xdgWmBase = try globals.bind(to: XdgWmBase.self, version: 6...7)
            seat = try? globals.bind(to: WlSeat.self, version: 1...9)
            self.globals = globals

            xdgWmBase!.onEvent = { [weak self] event in
                guard let self, case .ping(let serial) = event else { return }
                try? self.xdgWmBase?.pong(serial: serial)
            }

            connection.roundtrip()
            setupInput()
            connection.roundtrip()
        } catch {
            fatalError("Failed to initialize Wayland globals: \(error)")
        }

        responder.resumed(eventLoop: self)

        let connectionWatch: SwiftWayland.Watch = connection.attach()
        return SwinitCore.Watch { connectionWatch.cancel() }
    }

    public func stop() {
        CFRunLoopStop(CFRunLoopGetCurrent())
    }

    func dispatch(_ event: WindowEvent, from window: Window) {
        responder?.windowEvent(eventLoop: self, window: window, event: event)
    }

    func unregisterWindow(_ surfaceId: UInt32) {
        windows.removeValue(forKey: surfaceId)
        if pointerWindow?.surface.id == surfaceId { pointerWindow = nil }
        if keyboardWindow?.surface.id == surfaceId { keyboardWindow = nil }
    }

    // MARK: - Input

    private func findWindow(bySurfaceId id: UInt32) -> Window? {
        windows[id]?.value
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
                if let window = findWindow(bySurfaceId: surface.id) {
                    pointerWindow = window
                    dispatch(.cursorEntered(deviceId: .placeholder), from: window)
                    dispatch(.cursorMoved(deviceId: .placeholder, position: PhysicalPosition(x, y)), from: window)
                }
            case .leave(_, let surface):
                if let window = findWindow(bySurfaceId: surface.id) {
                    dispatch(.cursorLeft(deviceId: .placeholder), from: window)
                }
                pointerWindow = nil
            case .motion(_, let x, let y):
                if let window = pointerWindow {
                    dispatch(.cursorMoved(deviceId: .placeholder, position: PhysicalPosition(x, y)), from: window)
                }
            case .button(_, _, let button, let state):
                if let window = pointerWindow {
                    dispatch(.mouseInput(deviceId: .placeholder, state: state == .pressed ? .pressed : .released, button: linuxButton(button)), from: window)
                }
            case .axis(_, let axis, let value):
                if let window = pointerWindow {
                    let delta: MouseScrollDelta = axis == .verticalScroll ? .pixel(x: 0, y: -value) : .pixel(x: -value, y: 0)
                    dispatch(.mouseWheel(deviceId: .placeholder, delta: delta, phase: .moved), from: window)
                }
            default: break
            }
        }
    }

    private func setupKeyboardEvents() {
        keyboard?.onEvent = { [weak self] event in
            guard let self else { return }
            switch event {
            case .enter(_, let surface, _):
                if let window = findWindow(bySurfaceId: surface.id) {
                    keyboardWindow = window
                    dispatch(.focused(true), from: window)
                }
            case .leave(_, let surface):
                if let window = findWindow(bySurfaceId: surface.id) {
                    dispatch(.focused(false), from: window)
                }
                keyboardWindow = nil
            case .key(_, _, let key, let state):
                if let window = keyboardWindow {
                    let keyEvent = KeyEvent(physicalKey: key, logicalKey: key, state: state == .pressed ? .pressed : .released, isRepeat: false)
                    dispatch(.modifiersChanged(currentModifiers), from: window)
                    dispatch(.keyboardInput(deviceId: .placeholder, event: keyEvent, isSynthetic: false), from: window)
                }
            case .modifiers(_, let depressed, let latched, let locked, _):
                let combined = depressed | latched | locked
                currentModifiers = Modifiers(shift: combined & 1 != 0, control: combined & 4 != 0, alt: combined & 8 != 0, superKey: combined & 64 != 0)
                if let window = keyboardWindow {
                    dispatch(.modifiersChanged(currentModifiers), from: window)
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

final class WeakBox<T: AnyObject> {
    weak var value: T?
    init(_ value: T) { self.value = value }
}
