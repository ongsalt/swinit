import Foundation

import SwinitCommon

import WinSDK

public final class WindowEventLoop: IEventLoop {
  let controlFlow: ControlFlow

  var responder: (any Responder<WindowEventLoop>)? = nil

  public init?(controlFlow: ControlFlow = .wait) {
    self.controlFlow = controlFlow
  }

  public func createWindow(title: String) -> WindowsWindow {
    WindowsWindow(eventLoop: self, title: title)
  }

  public func run<R>(_ responder: R) where WindowEventLoop == R.EventLoop, R: SwinitCommon.Responder {
    self.responder = responder

    // TODO: check which platform need this
    responder.resumed(eventLoop: self)
    let result =
      switch controlFlow {
      case .wait:
        runWaitingLoop()
      case .poll:
        runPollingLoop()
      default:
        runWaitingLoop()
      }
  }

  public func sendWindowEvent(_ event: WindowEvent, to windowId: WindowId) {
    if self.responder == nil {
      fatalError("self.responder is nil: \(event) \(windowId)")
    }
    self.responder?.windowEvent(eventLoop: self, windowId: windowId, event: event)
  }

  private func runLoopWithHeartbeatThread() {

  }

  private func runPollingLoop() -> Int32 {
    var msg: MSG = MSG()
    var nExitCode: Int32 = EXIT_SUCCESS

    mainLoop: while true {
      // Process all messages in thread's message queue; for GUI applications UI
      // events must have high priority.
      while PeekMessageW(&msg, nil, 0, 0, UINT(PM_REMOVE)) {
        if msg.message == UINT(WM_QUIT) {
          nExitCode = Int32(msg.wParam)
          break mainLoop
        }

        TranslateMessage(&msg)
        DispatchMessageW(&msg)
      }

      var time: Date? = nil
      repeat {
        // Execute Foundation.RunLoop once and determine the next time the timer
        // fires.  At this point handle all Foundation.RunLoop timers, sources and
        // Dispatch.DispatchQueue.main tasks
        time = RunLoop.main.limitDate(forMode: .default)

        // If Foundation.RunLoop doesn't contain any timers or the timers should
        // not be running right now, we interrupt the current loop or otherwise
        // continue to the next iteration.
      } while (time?.timeIntervalSinceNow ?? -1) <= 0

      _ = MsgWaitForMultipleObjects(
        0, nil, false,
        DWORD(exactly: time?.timeIntervalSinceNow ?? -1)
          ?? 0,  // bruhhhhh
        QS_ALLINPUT | DWORD(QS_KEY) | DWORD(QS_TOUCH) | QS_MOUSE | DWORD(QS_RAWINPUT))
    }

    return nExitCode
  }

  // its actually wait with extra step
  private func runWaitingLoop() -> Int32 {
    var msg: MSG = MSG()
    var nExitCode: Int32 = EXIT_SUCCESS
    let TICK_INTERVAL_MS: UInt32 = 1

    // schedule immdediately
    let heartbeatTimer = SetTimer(nil, 0, 0, nil)

    while GetMessageW(&msg, nil, 0, 0) {
      switch msg.message {
      case UINT(WM_TIMER) where msg.wParam == heartbeatTimer:
        SetTimer(nil, heartbeatTimer, TICK_INTERVAL_MS, nil)
        RunLoop.main.run(until: .distantPast)
      case UINT(WM_QUIT):
        nExitCode = Int32(msg.wParam)
        break
      default:
        // print("msg: \(msg)")
        TranslateMessage(&msg)
        DispatchMessageW(&msg)
      }
    }

    return nExitCode
  }
}
