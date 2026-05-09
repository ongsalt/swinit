import Foundation

import Swinit

class Responder: Swinit.Responder {
  typealias EventLoop = Swinit.EventLoop

  var window: Window? = nil

  func resumed(eventLoop: EventLoop) {
    window = eventLoop.createWindow(attributes: .init(title: "nahhhh"))
    #if canImport(SwinitWin32)
      // window!.drawUnderTitleBar = true
      window?.handle
    // window?.backdropStyle = .mica
    #endif  // canImport(SwinitWin32)
  }

  func windowEvent(
    eventLoop: EventLoop, windowId: Swinit.WindowId, event: Swinit.WindowEvent
  ) {
    switch event {
    case .redrawRequested:
      print("nah")

    case .closeRequested:
      self.window = nil
      eventLoop.stop()

    default:
      print(event)
    }
  }
}
@main
public struct Main {
  public static func main() {
    let eventLoop = EventLoop()!

    // Task {
    //   while !Task.isCancelled {
    //     try await Task.sleep(for: .seconds(1))
    //     print("hi")
    //   }
    // }

    let r = Responder()
    eventLoop.run(r)
  }
}
