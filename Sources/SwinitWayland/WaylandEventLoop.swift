import CoreFoundation
import Foundation
import SwinitCommon

public final class WaylandEventLoop: IEventLoop {
    public typealias Window = WaylandWindow

    let controlFlow: ControlFlow

    var responder: (any Responder<WaylandEventLoop>)? = nil

    public init?(controlFlow: ControlFlow = .default) {
        // ignored bruh
        self.controlFlow = controlFlow
    }

    public func createWindow(attributes: SwinitCommon.WindowAttributes) -> WaylandWindow {
        WaylandWindow()
    }

    public func sendWindowEvent(_ event: WindowEvent, to windowId: WindowId) {
        if self.responder == nil {
            fatalError("self.responder is nil: \(event) \(windowId)")
        }
        self.responder?.windowEvent(eventLoop: self, windowId: windowId, event: event)
    }

    public func run<R>(_ responder: R)
    where WaylandEventLoop == R.EventLoop, R: SwinitCommon.Responder {
        self.responder = responder
        responder.resumed(eventLoop: self)
        RunLoop.main.run()
    }

    public func stop() {
        // bruh
        CFRunLoopStop(CFRunLoopGetCurrent())
    }

}
