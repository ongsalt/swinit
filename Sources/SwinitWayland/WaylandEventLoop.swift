import Foundation
import SwinitCommon

public final class WaylandEventLoop {
    let mode: ControlMode
    let wlDisplay: Display

    var responder: (any Responder<WaylandEventLoop>)? = nil

    private(set) var shouldRun: Bool = false

    public init?(mode: ControlMode = .swift) {
        self.mode = mode
        guard let display = try? Display() else { return nil }
        self.wlDisplay = display
    }

    private func runPolling() {
        shouldRun = true
        while shouldRun {
            // TODO: test this
            wlDisplay.prepareRead()
            wlDisplay.readEvent()
            RunLoop.main.run(until: .distantPast)
            wlDisplay.dispatchPending()
            wlDisplay.flush()
        }
    }

    // TODO: stop method
    private func runWithSwiftRunLoop() {
        wlDisplay.monitorEvents(queue: .main)

        // this is very unreliable
        let observer = RunLoopObserver(on: [.beforeWaiting]) { [wlDisplay] _ in
            wlDisplay.dispatchPending()
            wlDisplay.flush()
        }

        observer.start()
        defer {
            observer.stop()
        }

        RunLoop.main.run()
    }
}

extension WaylandEventLoop: IEventLoop {
    public func run<R>(_ responder: R) where WaylandEventLoop == R.EventLoop, R : SwinitCommon.Responder {
        self.responder = responder
        responder.resumed(eventLoop: self)

        switch mode {
        case .poll:
            runPolling()
        case .platform:
            fatalError("Unimplemented")
        case .swift:
            runWithSwiftRunLoop()
        case .wait:
            runWithSwiftRunLoop()
        }
    }

    // we should just stop doing responder and just do event enum with callback
    public func sendWindowEvent(_ event: WindowEvent, to windowId: WindowId) {
        self.responder?.windowEvent(eventLoop: self, windowId: windowId, event: event)
    }

    // or shuold this be global
    // EventLoop.main ????
    // and we force this to be only at most 1 per thread
    public func createWindow(title: String) -> WaylandWindow {
        WaylandWindow(display: self.wlDisplay, title: title)
    }
}
