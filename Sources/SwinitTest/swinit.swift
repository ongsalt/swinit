// The Swift Programming Language
// https://docs.swift.org/swift-book

import Foundation
import Swinit

class OurResponder: Responder {
  var window: Window? = nil

  func resumed(eventLoop: Swinit.EventLoop) {
    window = eventLoop.createWindow(title: "nahhhh")
    // window?.drawUnderTitleBar = true
    // window?.backdropStyle = .transient
  }

  func windowEvent(
    eventLoop: Swinit.EventLoop, windowId: Swinit.WindowId, event: Swinit.WindowEvent
  ) {
    switch event {
    case .redrawRequested:
      print("nah")

    case .closeRequested:
      self.window = nil

    default:
      print(event)
    }
  }
}

@main
public struct Main {
  public static func main() {
    // EventLoop.main.ensure(controlFlow: .poll)

    EventLoop.main.run()

    // let eventLoop = EventLoop(controlFlow: .poll)

    // eventLoop.run(OurResponder())
  }
}
