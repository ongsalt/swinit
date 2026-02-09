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
    // window?.backdropStyle = .main

  }

  func windowEvent(
    eventLoop: swinit.EventLoop, windowId: swinit.WindowId, event: swinit.WindowEvent
  ) {
    switch event {
    case .redrawRequested:
      guard let window = window else { return }

      var ps = PAINTSTRUCT()
      let hdc = BeginPaint(window.handle, &ps)

      var rect = RECT()
      GetClientRect(window.handle, &rect)

      let brush = CreateSolidBrush(0x0000_0000)
      FillRect(hdc, &rect, brush)
      DeleteObject(brush)

      SetBkMode(hdc, TRANSPARENT)
      SetTextColor(hdc, 0x0000_0000)
      _ = "Hello, swinit!".withCString(encodedAs: UTF16.self) { ptr in
        DrawTextW(hdc, ptr, -1, &rect, UInt32(DT_CENTER | DT_VCENTER | DT_SINGLELINE))
      }

      EndPaint(window.handle, &ps)

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
