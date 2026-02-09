// The Swift Programming Language
// https://docs.swift.org/swift-book

// import CoreD
import Foundation
import swinit

class OurResponder: Responder {
  var window: Window? = nil

  func resumed(eventLoop: swinit.EventLoop) {
    window = eventLoop.createWindow(title: "nahhhh")
  }

  func windowEvent(
    eventLoop: swinit.EventLoop, windowId: swinit.WindowId, event: swinit.WindowEvent
  ) {
    print(event)

    // window
  }
}

@main
public struct Main {
  public static func main() {
    let eventLoop = EventLoop()

    eventLoop.run(OurResponder())
  }
}
