import SwinitCore
import Foundation

#if os(Linux)
import CoreFoundation
import WaylandClient
import WaylandClientProtocols
import SwinitWayland
#elseif os(Windows)
import WinSDK
import SwinitWin32
#endif

@MainActor
public final class EventLoop {
    public weak var delegate: (any EventLoopDelegate)?

    var windows: [WindowId: Window] = [:]

    public init() {}

    /// Blocks the calling thread until `quit()` is called.
    ///
    /// - Win32: owns the main thread; runs `GetMessage` loop with 1 ms timer to flush
    ///   `RunLoop.main` for Swift async.
    /// - Wayland: registers a CF source on the Wayland fd and calls `RunLoop.main.run()`.
    public func run() {
        platformRun()
    }

    /// Convenience: assigns `delegate` then calls `run()`.
    public func run(_ delegate: some EventLoopDelegate) {
        self.delegate = delegate
        run()
    }

    @discardableResult
    public func openWindow(_ attributes: WindowAttributes = .init()) -> Window {
        platformOpenWindow(attributes)
    }

    public func close(id: WindowId) {
        windows[id]?.close()
    }

    public func quit() {
        platformQuit()
    }

    public subscript(id: WindowId) -> Window? { windows[id] }

    func removeWindow(id: WindowId) {
        windows.removeValue(forKey: id)
        platformWindowRemoved(id: id)
    }

    // MARK: Platform stored properties — implementations in EventLoop+<Platform>.swift

#if os(Linux)
    public var connection: Connection?
    var connectionWatch: WaylandClient.Watch? = nil
    var xdgWmBase:            XdgWmBase?
    var seat:                 WlSeat?
    var pointer:              WlPointer?
    var keyboard:             WlKeyboard?
    var waylandCompositor:    WlCompositor?
    var waylandDecoManager:            ZxdgDecorationManagerV1?
    var waylandSubcompositor:          WlSubcompositor?
    var waylandShm:                    WlShm?
    var waylandFractionalScaleManager: WpFractionalScaleManagerV1?
    var waylandTabletManager:          ZwpTabletManagerV2?
    var waylandTabletSeat:             ZwpTabletSeatV2?
    var waylandTablets:                [ZwpTabletV2] = []
    var touch:                         WlTouch?
    var seatCapabilities:              WlSeat.Capability = []
    var xkb:                           XKBState = XKBState()
    #if WaylandCSD
    var csdRouter = CSDInputRouter()
    #endif
    var pointerWindow:   Window?
    var keyboardWindow:  Window?
    var currentModifiers = Modifiers()
    var surfaceToWindow: [UInt32: WindowId] = [:]

    /// Wayland shared memory allocator — for software rendering.
    public var shm: WlShm? { waylandShm }
    public var waylandDisplay: WlDisplay { connection!.display }

#elseif os(Windows)
    package static let tickIntervalMs: UInt32 = 1
#endif
}
