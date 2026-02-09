import CWin32
import Foundation
import WinSDK

public class WindowsWindow: Identifiable {
  public typealias ID = WindowId
  public let id: WindowId = WindowId()

  public private(set) var handle: HWND! = nil
  private unowned let eventLoop: WindowEventLoop

  private let _title: WinString
  private let _windowClass: WinString

  public var title: String {
    get {
      _title.string
    }
    set {
      _title.string = newValue
      // TODO:
    }
  }

  public var drawUnderTitleBar: Bool = false {
    didSet {
      var margins = MARGINS(
        cxLeftWidth: -1,
        cxRightWidth: -1,
        cyTopHeight: drawUnderTitleBar ? -1 : 25,
        cyBottomHeight: -1
      )
      _ = DwmExtendFrameIntoClientArea(self.handle, &margins)
      // // This removes the black background and lets Mica show throughs
    }
  }

  public var backdropStyle: WindowsBackdropStyle = .auto {
    didSet {
      DwmSetWindowAttribute(
        handle,
        numericCast(DWMWA_SYSTEMBACKDROP_TYPE.rawValue),
        UnsafeRawPointer(bitPattern: Int(backdropStyle.underlying.rawValue)),
        UInt32(MemoryLayout<UInt32>.size)
      )
    }
  }

  init(eventLoop: WindowEventLoop, title: String, windowClass: String = "swinit_window") {
    self.eventLoop = eventLoop

    let instance = GetModuleHandleW(nil)!
    // why tf did i do that
    self._title = WinString(title)
    self._windowClass = WinString(windowClass)

    var windowClass = WNDCLASSW(
      style: UInt32(CS_HREDRAW | CS_VREDRAW),
      lpfnWndProc: globalWndProc,
      cbClsExtra: 0,
      cbWndExtra: 0,
      hInstance: instance,
      hIcon: nil,
      hCursor: LoadCursorW(nil, UnsafePointer(bitPattern: 32512)),  // IDC_ARROW
      hbrBackground: UnsafeMutablePointer(bitPattern: Int(COLOR_WINDOWFRAME)),  // COLOR_WINDOWFRAME as! HBRUSH
      // hbrBackground: UnsafeMutablePointer(bitPattern: 0),
      lpszMenuName: nil,
      lpszClassName: _windowClass.lpcwstr
    )

    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2)

    // ah, i love winapi
    guard RegisterClassW(&windowClass) != 0 else {
      fatalError("can not register window class, e: \(GetLastError())")
    }
    // throw self pointer to createWindowsSomeshi

    // think of this as the os (windows) have an unowned references to this
    let selfPtr = Unmanaged.passUnretained(self).toOpaque()

    let hwnd = CreateWindowExW(
      0, 
      _windowClass.lpcwstr,
      _title.lpcwstr,
      UInt32(WS_VISIBLE) | WS_OVERLAPPEDWINDOW,
      CW_USEDEFAULT,
      CW_USEDEFAULT,
      CW_USEDEFAULT,
      CW_USEDEFAULT,
      nil,
      nil,
      instance,
      selfPtr
    )

    self.handle = hwnd!
  }

  internal func wndProc(_ hWnd: HWND?, _ message: UINT, _ wParam: WPARAM, _ lParam: LPARAM)
    -> LRESULT
  {
    switch message {
    case UINT(WM_SIZE):
      let width = UInt32(LOWORD(lParam))
      let height = UInt32(HIWORD(lParam))
      let size = PhysicalSize(width: width, height: height)
      eventLoop.sendWindowEvent(.resized(size), to: id)
      return 0

    case UINT(WM_MOVE):
      let x = Int32(Int16(bitPattern: LOWORD(lParam)))
      let y = Int32(Int16(bitPattern: HIWORD(lParam)))
      let position = PhysicalPosition(x, y)
      eventLoop.sendWindowEvent(.moved(position), to: id)
      return 0

    case UINT(WM_CLOSE):
      eventLoop.sendWindowEvent(.closeRequested, to: id)
      return 0

    case UINT(WM_DESTROY):
      eventLoop.sendWindowEvent(.destroyed, to: id)
      return 0

    case UINT(WM_SETFOCUS):
      eventLoop.sendWindowEvent(.focused(true), to: id)
      return 0

    case UINT(WM_KILLFOCUS):
      eventLoop.sendWindowEvent(.focused(false), to: id)
      return 0

    case UINT(WM_MOUSEMOVE):
      let x = Double(Int16(bitPattern: LOWORD(lParam)))
      let y = Double(Int16(bitPattern: HIWORD(lParam)))
      let position = PhysicalPosition(x, y)
      let deviceId = DeviceId()
      eventLoop.sendWindowEvent(.cursorMoved(deviceId: deviceId, position: position), to: id)

      // Track mouse leave events
      var tme = TRACKMOUSEEVENT(
        cbSize: UInt32(MemoryLayout<TRACKMOUSEEVENT>.size),
        dwFlags: UInt32(TME_LEAVE),
        hwndTrack: hWnd,
        dwHoverTime: 0
      )
      TrackMouseEvent(&tme)
      return 0

    case UINT(WM_MOUSELEAVE):
      let deviceId = DeviceId()
      eventLoop.sendWindowEvent(.cursorLeft(deviceId: deviceId), to: id)
      return 0

    case UINT(WM_PAINT):
      eventLoop.sendWindowEvent(.redrawRequested, to: id)
      ValidateRect(handle, nil)
      return 0

    default:
      return DefWindowProcW(hWnd, message, wParam, lParam)
    }
  }

  deinit {
    DestroyWindow(handle)
  }
}

extension WindowsWindow: IWindow {
  public func requestRedraw() {
    InvalidateRect(handle, nil, false)
  }

  public func focus() {
    SetForegroundWindow(handle)
    SetFocus(handle)
  }
}

private func getWindow(_ hWnd: HWND) -> Unmanaged<WindowsWindow>? {
  let userData = UInt(GetWindowLongPtrW(hWnd, Int32(GWLP_USERDATA)))
  guard let ptr = UnsafeRawPointer(bitPattern: userData) else {
    return nil
  }

  return Unmanaged.fromOpaque(ptr)
}

private func globalWndProc(_ hWnd: HWND?, _ message: UINT, _ wParam: WPARAM, _ lParam: LPARAM)
  -> LRESULT
{
  // print(String(message, radix: 16))
  switch message {
  case UINT(WM_NCCREATE):
    let createStruct = UnsafeMutablePointer<CREATESTRUCTW>(bitPattern: UInt(lParam))!
    let selfPtr = createStruct.pointee.lpCreateParams!
    SetWindowLongPtrW(hWnd, GWLP_USERDATA, Int64(UInt(bitPattern: selfPtr)))
    // let userData = UInt(GetWindowLongPtrW(hWnd, Int32(GWLP_USERDATA)))
    // print("whattt \(userData)")
    return DefWindowProcW(hWnd, message, wParam, lParam)

  case UINT(WM_NCDESTROY):
    // TODO: think about releasing this
    // This should be called some where else
    // let window = getWindow(hWnd!)!
    // window.release()
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
