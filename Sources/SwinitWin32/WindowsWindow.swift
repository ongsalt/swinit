import CWin32

import Foundation

import SwinitCommon

import WinSDK

public class WindowsWindow: Identifiable {
  public typealias ID = WindowId
  public let id: WindowId = WindowId()

  public private(set) var handle: HWND! = nil
  public private(set) var hInstance: HINSTANCE! = nil
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
      self.drawUnderTitleBar = Bool(drawUnderTitleBar)
      var pref = backdropStyle.rawValue
      DwmSetWindowAttribute(
        handle,
        38,  // DWMWA_SYSTEMBACKDROP_TYPE.rawValue
        &pref,
        UInt32(MemoryLayout<UInt32>.size)
      )
    }
  }

  init(eventLoop: WindowEventLoop, attributes: WindowAttributes) {
    self.eventLoop = eventLoop

    self.hInstance = GetModuleHandleW(nil)!
    // why tf did i do that
    self._title = WinString(attributes.title)
    self._windowClass = WinString(attributes.windowClass)

    var windowClass = WNDCLASSW(
      style: UInt32(CS_HREDRAW | CS_VREDRAW),
      lpfnWndProc: globalWndProc,
      cbClsExtra: 0,
      cbWndExtra: 0,
      hInstance: hInstance,
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

    var exStyle: UInt32 = 0
    if attributes.noRedirectionBitmap {
      exStyle |= UInt32(WS_EX_NOREDIRECTIONBITMAP)
    }
    if attributes.transparency {
      exStyle |= UInt32(WS_EX_LAYERED)
    }

    let hwnd = CreateWindowExW(
      exStyle, // TODO: expose window attributes config
      _windowClass.lpcwstr,
      _title.lpcwstr,
      UInt32(WS_VISIBLE) | WS_OVERLAPPEDWINDOW,
      CW_USEDEFAULT,
      CW_USEDEFAULT,
      CW_USEDEFAULT,
      CW_USEDEFAULT,
      nil,
      nil,
      hInstance,
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

    case UINT(WM_LBUTTONDOWN), UINT(WM_RBUTTONDOWN), UINT(WM_MBUTTONDOWN), UINT(WM_XBUTTONDOWN):
      let button: MouseButton
      switch message {
      case UINT(WM_LBUTTONDOWN): button = .left
      case UINT(WM_RBUTTONDOWN): button = .right
      case UINT(WM_MBUTTONDOWN): button = .middle
      default:
        let btn = HIWORD(wParam)
        button = btn == XBUTTON1 ? .back : (btn == XBUTTON2 ? .forward : .other(btn))
      }
      eventLoop.sendWindowEvent(.mouseInput(deviceId: DeviceId(), state: .pressed, button: button), to: id)
      return 0

    case UINT(WM_LBUTTONUP), UINT(WM_RBUTTONUP), UINT(WM_MBUTTONUP), UINT(WM_XBUTTONUP):
      let button: MouseButton
      switch message {
      case UINT(WM_LBUTTONUP): button = .left
      case UINT(WM_RBUTTONUP): button = .right
      case UINT(WM_MBUTTONUP): button = .middle
      default:
        let btn = HIWORD(wParam)
        button = btn == XBUTTON1 ? .back : (btn == XBUTTON2 ? .forward : .other(btn))
      }
      eventLoop.sendWindowEvent(.mouseInput(deviceId: DeviceId(), state: .released, button: button), to: id)
      return 0

    case UINT(WM_MOUSEWHEEL):
      let delta = Double(Int16(bitPattern: HIWORD(wParam))) / Double(WHEEL_DELTA)
      eventLoop.sendWindowEvent(.mouseWheel(deviceId: DeviceId(), delta: .line(x: 0, y: delta), phase: .moved), to: id)
      return 0

    case UINT(WM_MOUSEHWHEEL):
      let delta = Double(Int16(bitPattern: HIWORD(wParam))) / Double(WHEEL_DELTA)
      eventLoop.sendWindowEvent(.mouseWheel(deviceId: DeviceId(), delta: .line(x: delta, y: 0), phase: .moved), to: id)
      return 0

    case UINT(WM_KEYDOWN), UINT(WM_SYSKEYDOWN):
      let physicalKey = UInt32((lParam >> 16) & 0xFF)
      let logicalKey = UInt32(wParam)
      let isRepeat = (lParam & (1 << 30)) != 0
      let event = KeyEvent(physicalKey: physicalKey, logicalKey: logicalKey, text: nil, state: .pressed, isRepeat: isRepeat)
      
      let modifiers = Modifiers(
        shift: GetKeyState(Int32(VK_SHIFT)) < 0,
        control: GetKeyState(Int32(VK_CONTROL)) < 0,
        alt: GetKeyState(Int32(VK_MENU)) < 0,
        superKey: GetKeyState(Int32(VK_LWIN)) < 0 || GetKeyState(Int32(VK_RWIN)) < 0
      )
      
      eventLoop.sendWindowEvent(.modifiersChanged(modifiers), to: id)
      eventLoop.sendWindowEvent(.keyboardInput(deviceId: DeviceId(), event: event, isSynthetic: false), to: id)
      return 0

    case UINT(WM_KEYUP), UINT(WM_SYSKEYUP):
      let physicalKey = UInt32((lParam >> 16) & 0xFF)
      let logicalKey = UInt32(wParam)
      let event = KeyEvent(physicalKey: physicalKey, logicalKey: logicalKey, text: nil, state: .released, isRepeat: false)
      
      let modifiers = Modifiers(
        shift: GetKeyState(Int32(VK_SHIFT)) < 0,
        control: GetKeyState(Int32(VK_CONTROL)) < 0,
        alt: GetKeyState(Int32(VK_MENU)) < 0,
        superKey: GetKeyState(Int32(VK_LWIN)) < 0 || GetKeyState(Int32(VK_RWIN)) < 0
      )
      
      eventLoop.sendWindowEvent(.modifiersChanged(modifiers), to: id)
      eventLoop.sendWindowEvent(.keyboardInput(deviceId: DeviceId(), event: event, isSynthetic: false), to: id)
      return 0

    // no gdi
    case UINT(WM_ERASEBKGND):
      return 1

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

  default:
    if let window = getWindow(hWnd!) {
      return window.takeUnretainedValue().wndProc(hWnd, message, wParam, lParam)
    } else {
      return DefWindowProcW(hWnd, message, wParam, lParam)
    }
  }
}
