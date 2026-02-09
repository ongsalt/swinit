import Foundation
import WinSDK

public func win32RunLoop(tickrate: Int? = nil) -> Int32 {
  var msg: MSG = MSG()
  var nExitCode: Int32 = EXIT_SUCCESS

  let start = ContinuousClock.now
  var ticked: Int64 = 0
  var lastTicked: Int64 = 0
  mainLoop: while true {
    ticked += 1
    // let s = max(Double(start.duration(to: .now).components.seconds), 1)
    if ticked - lastTicked > 100 {
    let s = max(Double(start.duration(to: .now).attoseconds / 1_000_000_000_000_000_000), 0.00000000001)
      print("tick rate \(Float(ticked) / Float(s)) ")
      lastTicked = ticked
    }
    // Process all messages in thread's message queue; for GUI applications UI
    // events must have high priority.
    while PeekMessageW(&msg, nil, 0, 0, UINT(PM_REMOVE)) {
      print("msg: \(msg)")
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

    let next =
      DWORD(exactly: time?.timeIntervalSinceNow ?? -1)
      ?? tickrate.map { DWORD($0) } ?? INFINITE
    // print("Next: \(next)")

    // print("next dword: \(ms) \(INFINITE)")
    _ = MsgWaitForMultipleObjects(
      0, nil, false,
      next,  // bruhhhhh
      QS_ALLINPUT | DWORD(QS_KEY) | DWORD(QS_TOUCH) | QS_MOUSE | DWORD(QS_RAWINPUT))
  }

  return nExitCode
}
