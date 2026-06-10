@MainActor
public protocol Responder<EventLoop> {
    associatedtype EventLoop: EventLoopProtocol

    /// The event loop is ready; create windows here.
    func resumed(eventLoop: EventLoop)

    func windowEvent(eventLoop: EventLoop, window: EventLoop.Window, event: WindowEvent)

    func aboutToWait(eventLoop: EventLoop)
    func suspended(eventLoop: EventLoop)
    func memoryWarning(eventLoop: EventLoop)
}

extension Responder {
    public func aboutToWait(eventLoop: EventLoop) {}
    public func suspended(eventLoop: EventLoop) {}
    public func memoryWarning(eventLoop: EventLoop) {}
}
