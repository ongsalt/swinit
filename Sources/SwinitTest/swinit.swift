// The Swift Programming Language
// https://docs.swift.org/swift-book

import Foundation
import WinSDK
import swinit

class OurResponder: Responder {
  var window: Window? = nil

  func resumed(eventLoop: swinit.EventLoop) {
    window = eventLoop.createWindow(title: "nahhhh")
    window?.drawUnderTitleBar = true
    window?.backdropStyle = .transient
  }

  func windowEvent(
    eventLoop: swinit.EventLoop, windowId: swinit.WindowId, event: swinit.WindowEvent
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
    let eventLoop = EventLoop(controlFlow: .poll)

    eventLoop.run(OurResponder())
  }
}
