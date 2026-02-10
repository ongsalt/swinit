/// 
/// On linux/wayland im gonna try using limit date
/// current approach is let swift run it own loop (preferably) and watch wayland fd using DispatchSource
/// whihc iiuc make a new thread instead of fucking add the fd to CFPortSet to be epolled later
import Foundation
import FoundationNetworking
import Dispatch

public enum ControlMode {
    /// Its game loop.
    case poll
    
    /// unavailable on window because there is no way to let the (ns)runloop 
    /// run by itself while waiting for windows messages
    /// and CoreFoundation is also not exported so there is not much that i can do
    /// Wayland: wait for messages on seperate thread
    /// macos/ios: same as platform
    case swift

    /// Windows: Use platform loop with `heartbeat` message to keep runloop not stall every now and then
    /// while GetMessageW(...) { 
    ///     RunLoop.main.run(until: .distantPast)
    /// }
    /// Wayland: idk, probably epoll with 2 kind of event: wayland/swift heartbeat, why use this tho
    /// macos/ios: (NS)RunLoop IS the platform api
    case platform

    /// Will try to use swift RunLoop unless its impossible 
    /// this correspond to .swift except for windows which is .platform
    case wait
}

func testFetch() async {
    let req = URLRequest(url: URL(string: "https://dummyjson.com/RESOURCE/?limit=10&skip=5&select=key1,key2,key3")!)
    // its libcurl, so probably a worker thread
    let (data, response) = try! await URLSession.shared.data(for: req)
    let res = String(bytes: data, encoding: .utf8)
    // DispatchQueue
    print(res)
}

// Usages
class EventLoop {
    init(mode: ControlMode) {}

    func run(responder: some Responder) {}
}
