import Foundation
import Swinit

class Responder: Swinit.Responder {
  typealias EventLoop = Swinit.EventLoop

  var window: Window? = nil
  var window2: Window? = nil

  func resumed(eventLoop: EventLoop) {
    window = eventLoop.createWindow(attributes: .init(title: "nahhhh"))
    window2 = eventLoop.createWindow(attributes: .init(title: "win2"))
    #if canImport(SwinitWin32)
      window!.drawUnderTitleBar = true
      window?.backdropStyle = .mica
    #endif
  }

  func windowEvent(
    eventLoop: EventLoop, windowId: Swinit.WindowId, event: Swinit.WindowEvent
  ) {
    switch event {
    case .redrawRequested:
      print("nah")

    case .closeRequested:  // TODO: this must be per window
      self.window = nil
      self.window2 = nil
      eventLoop.stop()

    default:
      do {}
    // print(event)
    }
  }
}

let eventLoop = EventLoop()!

// Task {
//   var i = 0
//   while !Task.isCancelled {
//     try await Task.sleep(for: .seconds(1))
//     print("> hi \(i)")
//     i += 1
//   }
// }

let r = Responder()
eventLoop.run(r)
