public protocol Responder {
    associatedtype UserEvent = Void
    associatedtype EventLoop: IEventLoop
    
    // Required methods
    func resumed(eventLoop: EventLoop)
    func windowEvent(eventLoop: EventLoop, windowId: WindowId, event: WindowEvent)    
}

extension Responder {
    // func newEvents(eventLoop: EventLoop, cause: StartCause) {}
    public func userEvent(eventLoop: EventLoop, event: UserEvent) {}
    // func deviceEvent(eventLoop: EventLoop, deviceId: DeviceId, event: DeviceEvent) {}
    public func aboutToWait(eventLoop: EventLoop) {}
    public func suspended(eventLoop: EventLoop) {}
    public func exiting(eventLoop: EventLoop) {}
    public func memoryWarning(eventLoop: EventLoop) {}
}
