/// 
/// On linux/wayland im gonna try using limit date
/// current approach is let swift run it own loop (preferably) and watch wayland fd using DispatchSource
/// whihc iiuc make a new thread instead of fucking add the fd to CFPortSet to be epolled later
import Foundation
import FoundationNetworking
import Dispatch

public enum ControlFlow {
    /// Game loop.
    case poll
    
    /// Swift controls main thread.
    /// unavailable on window because there is no way to let the (ns)runloop 
    /// run by itself while waiting for windows messages
    /// and CoreFoundation is also not exported so there is not much that i can do
    /// MIGHT change once custom executor is landed
    /// Wayland: wait for messages on seperate thread
    /// Apple: same as platform
    case swift

    /// Windows: Use platform loop with `heartbeat` message to keep runloop not stall every now and then
    /// while GetMessageW(...) { 
    ///     RunLoop.main.run(until: .distantPast)
    /// }
    /// Wayland: idk, probably epoll with 2 kind of event: wayland/swift heartbeat, why use this tho
    /// Apple: (NS)RunLoop IS the platform api
    case platform

    /// Will try to use swift RunLoop unless its impossible 
    /// this correspond to .swift except for windows which is .platform
    case `default`
}

// Usages
// class EventLoop {
//     init(mode: ControlFlow) {}

//     func run(responder: some Responder) {}
// }
