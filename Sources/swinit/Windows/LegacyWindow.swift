import Foundation
import WinSDK

public class LegacyWindow {
  public private(set) var hwnd: HWND! = nil

  public init() throws {
    let instance = GetModuleHandleW(nil)!
    // why tf did i do that
    let yomum = WinString("yomum")
    let idk = WinString("a")

    var windowClass = WNDCLASSW(
      style: UInt32(CS_HREDRAW | CS_VREDRAW), lpfnWndProc: globalWndProc, cbClsExtra: 0,
      cbWndExtra: 0,
      hInstance: instance, hIcon: nil,
      hCursor: LoadCursorW(nil, UnsafePointer(bitPattern: 32512)), hbrBackground: nil,  // COLOR_WINDOWFRAME as! HBRUSH
      lpszMenuName: nil, lpszClassName: yomum.lpcwstr)
    // TODO: fix class registering

    // ah, i love winapi
    guard RegisterClassW(&windowClass) != 0 else {
      fatalError("can not register window class, e: \(GetLastError())")
    }
    // throw self pointer to createWindowsSomeshi

    // think of this as the os (windows) have 1 references to this
    let selfPtr = Unmanaged.passRetained(self).toOpaque()

    let hwnd = CreateWindowExW(
      0, yomum.lpcwstr, idk.lpcwstr, UInt32(WS_VISIBLE) | WS_OVERLAPPEDWINDOW,
      CW_USEDEFAULT,
      CW_USEDEFAULT, CW_USEDEFAULT, CW_USEDEFAULT, nil, nil,
      instance, selfPtr)

    self.hwnd = hwnd!
  }

  internal func wndProc(_ hWnd: HWND?, _ message: UINT, _ wParam: WPARAM, _ lParam: LPARAM) -> LRESULT
  {
    // print("yeah")
    switch message {
    default:
      return DefWindowProcW(hWnd, message, wParam, lParam)
    }
  }

  public func runLoop() -> Int32 {
    // copied from the browser company winui repo

    // The below run loop is taken mostly from https://github.com/compnerd/swift-win32/blob/d34ff1b8b3f15cfdf2cb71109a3c313001122a54/Sources/SwiftWin32/App%20and%20Environment/ApplicationMain.swift#L183
    // with some tweaks for WinUI
    var msg: MSG = MSG()
    while true {

      // Process all messages in thread's message queue; for GUI applications UI
      // events must have high priority.
      while PeekMessageW(&msg, nil, 0, 0, UINT(PM_REMOVE)) {
        if msg.message == UINT(WM_QUIT) {
          print("Stop")
          return Int32(msg.wParam)
        }

        // if !contentPreTranslateMessage(&msg) {
        TranslateMessage(&msg)
        DispatchMessageW(&msg)
        // }
      }

      var time: Date? = nil
      repeat {
        // Execute Foundation.RunLoop once and determine the next time the timer
        // fires.  At this point handle all Foundation.RunLoop timers, sources and
        // Dispatch.DispatchQueue.main tasks
        time = Foundation.RunLoop.main.limitDate(forMode: .default)

        // If Foundation.RunLoop doesn't contain any timers or the timers should
        // not be running right now, we interrupt the current loop or otherwise
        // continue to the next iteration.
      } while (time?.timeIntervalSinceNow ?? -1) <= 0

      // Yield control to the system until the earlier of a requisite timer
      // expiration or a message is posted to the runloop.
      _ = MsgWaitForMultipleObjects(
        0, nil, false,
        DWORD(exactly: time?.timeIntervalSinceNow ?? -1)
          ?? 0,
        QS_ALLINPUT)
    }
    return 0
  }

}

internal func getWindow(_ hWnd: HWND) -> Unmanaged<LegacyWindow>? {
  let userData = UInt(GetWindowLongPtrW(hWnd, Int32(GWLP_USERDATA)))
  guard let ptr = UnsafeRawPointer(bitPattern: userData) else {
    return nil
  }

  return Unmanaged.fromOpaque(ptr)
}

func globalWndProc(_ hWnd: HWND?, _ message: UINT, _ wParam: WPARAM, _ lParam: LPARAM) -> LRESULT {
  print(String(message, radix: 16))
  switch message {
  case UINT(WM_NCCREATE):
    let createStruct = UnsafeMutablePointer<CREATESTRUCTW>(bitPattern: UInt(lParam))!
    let selfPtr = createStruct.pointee.lpCreateParams!
    SetWindowLongPtrW(hWnd, GWLP_USERDATA, Int64(UInt(bitPattern: selfPtr)))
    // let userData = UInt(GetWindowLongPtrW(hWnd, Int32(GWLP_USERDATA)))
    // print("whattt \(userData)")
    return DefWindowProcW(hWnd, message, wParam, lParam)

  case UINT(WM_NCDESTROY):
    let window = getWindow(hWnd!)!
    window.release()
    PostQuitMessage(0)
    return LRESULT(0)

  default:
    if let window = getWindow(hWnd!) {
      return window.takeUnretainedValue().wndProc(hWnd, message, wParam, lParam)
    } else {
      return DefWindowProcW(hWnd, message, wParam, lParam)
    }
  }
}
