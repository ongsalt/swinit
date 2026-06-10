import Foundation
import SwinitCore
import WinSDK

@MainActor
public final class Window: SwinitCore.WindowProtocol {
    // nonisolated(unsafe): accessed from deinit and C callbacks, both guaranteed main thread
    public nonisolated(unsafe) private(set) var handle: HWND! = nil
    public nonisolated(unsafe) private(set) var hInstance: HINSTANCE! = nil
    private unowned let eventLoop: EventLoop

    private let _title: WinString
    private let _windowClass: WinString

    public var title: String {
        get { _title.string }
        set {
            _title.string = newValue
            SetWindowTextW(handle, _title.lpcwstr)
        }
    }

    public var size: SIMD2<UInt> {
        get {
            var rect = RECT()
            GetWindowRect(handle, &rect)
            return SIMD2<UInt>(UInt(max(0, rect.right - rect.left)), UInt(max(0, rect.bottom - rect.top)))
        }
        set {
            SetWindowPos(handle, nil, 0, 0, Int32(newValue.x), Int32(newValue.y), UINT(SWP_NOMOVE | SWP_NOZORDER))
        }
    }

    public var drawUnderTitleBar: Bool = false {
        didSet {
            var margins = MARGINS(
                cxLeftWidth: -1, cxRightWidth: -1,
                cyTopHeight: drawUnderTitleBar ? -1 : 25, cyBottomHeight: -1)
            _ = DwmExtendFrameIntoClientArea(handle, &margins)
        }
    }

    public var backdropStyle: WindowsBackdropStyle = .auto {
        didSet {
            self.drawUnderTitleBar = Bool(drawUnderTitleBar)
            var pref = backdropStyle.rawValue
            DwmSetWindowAttribute(handle, 38, &pref, UInt32(MemoryLayout<UInt32>.size))
        }
    }

    init(eventLoop: EventLoop, attributes: WindowAttributes) {
        self.eventLoop = eventLoop
        self.hInstance = GetModuleHandleW(nil)!
        self._title = WinString(attributes.title)
        self._windowClass = Self.windowClass

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        var exStyle: UInt32 = 0
        if attributes.noRedirectionBitmap { exStyle |= UInt32(WS_EX_NOREDIRECTIONBITMAP) }
        if attributes.transparency { exStyle |= UInt32(WS_EX_LAYERED) }

        handle = CreateWindowExW(
            exStyle,
            _windowClass.lpcwstr, _title.lpcwstr,
            UInt32(WS_VISIBLE) | WS_OVERLAPPEDWINDOW,
            CW_USEDEFAULT, CW_USEDEFAULT,
            Int32(attributes.size.x), Int32(attributes.size.y),
            nil, nil, hInstance, selfPtr)!
    }

    // MARK: - Window class

    nonisolated(unsafe) static let windowClass: WinString = {
        SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2)
        let name = WinString("swinit_default")
        var wc = WNDCLASSW(
            style: UInt32(CS_HREDRAW | CS_VREDRAW),
            lpfnWndProc: globalWndProc,
            cbClsExtra: 0, cbWndExtra: 0,
            hInstance: GetModuleHandleW(nil),
            hIcon: nil,
            hCursor: LoadCursorW(nil, UnsafePointer(bitPattern: 32512)),
            hbrBackground: UnsafeMutablePointer(bitPattern: Int(COLOR_WINDOWFRAME)),
            lpszMenuName: nil,
            lpszClassName: name.lpcwstr)

        if RegisterClassW(&wc) == 0 {
            let err = GetLastError()
            // ERROR_CLASS_ALREADY_EXISTS is fine (e.g. multiple EventLoop instances)
            guard err == DWORD(ERROR_CLASS_ALREADY_EXISTS) else {
                fatalError("RegisterClassW failed: \(err)")
            }
        }
        return name
    }()

    // MARK: - Message proc

    private var isResizing = false
    private var currentHeartbeatTimer: UInt64?

    /// Called from globalWndProc on the main thread. Does not take hWnd — uses self.handle.
    internal func wndProc(_ message: UINT, _ wParam: WPARAM, _ lParam: LPARAM) -> LRESULT {
        switch message {
        case UINT(WM_ENTERSIZEMOVE):
            isResizing = true
            currentHeartbeatTimer = SetTimer(handle, UInt64.random(in: .min ... .max), EventLoop.tickIntervalMs, nil)
            return 0

        case UINT(WM_TIMER) where currentHeartbeatTimer != nil:
            RunLoop.main.run(until: .distantPast)
            return 0

        case UINT(WM_EXITSIZEMOVE):
            isResizing = false
            if let t = currentHeartbeatTimer { KillTimer(handle, t) }
            var rect = RECT()
            GetClientRect(handle, &rect)
            let size = PhysicalSize(width: UInt32(max(0, rect.right - rect.left)), height: UInt32(max(0, rect.bottom - rect.top)))
            eventLoop.dispatch(.resized(size: size, isFinal: true), from: self)
            return 0

        case UINT(WM_SIZE):
            let size = PhysicalSize(width: UInt32(LOWORD(lParam)), height: UInt32(HIWORD(lParam)))
            eventLoop.dispatch(.resized(size: size, isFinal: !isResizing), from: self)
            return 0

        case UINT(WM_MOVE):
            let pos = PhysicalPosition(Int32(Int16(bitPattern: LOWORD(lParam))), Int32(Int16(bitPattern: HIWORD(lParam))))
            eventLoop.dispatch(.moved(pos), from: self)
            return 0

        case UINT(WM_CLOSE):
            eventLoop.dispatch(.closeRequested, from: self)
            return 0

        case UINT(WM_DESTROY):
            eventLoop.dispatch(.destroyed, from: self)
            return 0

        case UINT(WM_SETFOCUS):
            eventLoop.dispatch(.focused(true), from: self)
            return 0

        case UINT(WM_KILLFOCUS):
            eventLoop.dispatch(.focused(false), from: self)
            return 0

        case UINT(WM_MOUSEMOVE):
            let pos = PhysicalPosition(Double(Int16(bitPattern: LOWORD(lParam))), Double(Int16(bitPattern: HIWORD(lParam))))
            eventLoop.dispatch(.cursorMoved(deviceId: .placeholder, position: pos), from: self)
            var tme = TRACKMOUSEEVENT(cbSize: UInt32(MemoryLayout<TRACKMOUSEEVENT>.size), dwFlags: UInt32(TME_LEAVE), hwndTrack: handle, dwHoverTime: 0)
            TrackMouseEvent(&tme)
            return 0

        case UINT(WM_MOUSELEAVE):
            eventLoop.dispatch(.cursorLeft(deviceId: .placeholder), from: self)
            return 0

        case UINT(WM_LBUTTONDOWN), UINT(WM_RBUTTONDOWN), UINT(WM_MBUTTONDOWN), UINT(WM_XBUTTONDOWN):
            eventLoop.dispatch(.mouseInput(deviceId: .placeholder, state: .pressed, button: mouseButton(from: message, wParam: wParam)), from: self)
            return 0

        case UINT(WM_LBUTTONUP), UINT(WM_RBUTTONUP), UINT(WM_MBUTTONUP), UINT(WM_XBUTTONUP):
            eventLoop.dispatch(.mouseInput(deviceId: .placeholder, state: .released, button: mouseButton(from: message, wParam: wParam)), from: self)
            return 0

        case UINT(WM_MOUSEWHEEL):
            eventLoop.dispatch(.mouseWheel(deviceId: .placeholder, delta: wheelDelta(hiword: HIWORD(wParam), horizontal: false), phase: .moved), from: self)
            return 0

        case UINT(WM_MOUSEHWHEEL):
            eventLoop.dispatch(.mouseWheel(deviceId: .placeholder, delta: wheelDelta(hiword: HIWORD(wParam), horizontal: true), phase: .moved), from: self)
            return 0

        case UINT(WM_KEYDOWN), UINT(WM_SYSKEYDOWN):
            let physicalKey = UInt32((lParam >> 16) & 0xFF)
            let event = KeyEvent(physicalKey: physicalKey, logicalKey: UInt32(wParam), state: .pressed, isRepeat: (lParam & (1 << 30)) != 0)
            eventLoop.dispatch(.modifiersChanged(captureModifiers()), from: self)
            eventLoop.dispatch(.keyboardInput(deviceId: .placeholder, event: event, isSynthetic: false), from: self)
            return 0

        case UINT(WM_KEYUP), UINT(WM_SYSKEYUP):
            let physicalKey = UInt32((lParam >> 16) & 0xFF)
            let event = KeyEvent(physicalKey: physicalKey, logicalKey: UInt32(wParam), state: .released, isRepeat: false)
            eventLoop.dispatch(.modifiersChanged(captureModifiers()), from: self)
            eventLoop.dispatch(.keyboardInput(deviceId: .placeholder, event: event, isSynthetic: false), from: self)
            return 0

        case UINT(WM_ERASEBKGND):
            return 1

        default:
            return DefWindowProcW(handle, message, wParam, lParam)
        }
    }

    deinit {
        // Zero GWLP_USERDATA first: the synchronous WM_DESTROY fired inside
        // DestroyWindow must not dereference this already-deallocating object.
        SetWindowLongPtrW(handle, GWLP_USERDATA, 0)
        DestroyWindow(handle)
    }

    public func requestRedraw() { InvalidateRect(handle, nil, false) }
    public func focus() { SetForegroundWindow(handle); SetFocus(handle) }
}

// MARK: - Helpers

private func mouseButton(from message: UINT, wParam: WPARAM) -> MouseButton {
    switch message {
    case UINT(WM_LBUTTONDOWN), UINT(WM_LBUTTONUP): return .left
    case UINT(WM_RBUTTONDOWN), UINT(WM_RBUTTONUP): return .right
    case UINT(WM_MBUTTONDOWN), UINT(WM_MBUTTONUP): return .middle
    default:
        let btn = HIWORD(wParam)
        return btn == XBUTTON1 ? .back : (btn == XBUTTON2 ? .forward : .other(btn))
    }
}

/// Touchpad heuristic: fine-grained deltas (< WHEEL_DELTA) are sent as pixel
/// deltas; full WHEEL_DELTA multiples are sent as line deltas.
private func wheelDelta(hiword: WORD, horizontal: Bool) -> MouseScrollDelta {
    let raw = Int16(bitPattern: hiword)
    let value = Double(raw)
    if abs(raw) < WHEEL_DELTA {
        // Touchpad sends sub-120 increments — treat as pixel scroll
        return horizontal ? .pixel(x: value, y: 0) : .pixel(x: 0, y: -value)
    } else {
        let lines = value / Double(WHEEL_DELTA)
        return horizontal ? .line(x: lines, y: 0) : .line(x: 0, y: lines)
    }
}

private func captureModifiers() -> Modifiers {
    Modifiers(
        shift: GetKeyState(Int32(VK_SHIFT)) < 0,
        control: GetKeyState(Int32(VK_CONTROL)) < 0,
        alt: GetKeyState(Int32(VK_MENU)) < 0,
        superKey: GetKeyState(Int32(VK_LWIN)) < 0 || GetKeyState(Int32(VK_RWIN)) < 0)
}

private func getWindow(_ hWnd: HWND) -> Unmanaged<Window>? {
    let userData = UInt(GetWindowLongPtrW(hWnd, Int32(GWLP_USERDATA)))
    guard let ptr = UnsafeRawPointer(bitPattern: userData) else { return nil }
    return Unmanaged.fromOpaque(ptr)
}

private func globalWndProc(_ hWnd: HWND?, _ message: UINT, _ wParam: WPARAM, _ lParam: LPARAM) -> LRESULT {
    switch message {
    case UINT(WM_NCCREATE):
        let cs = UnsafeMutablePointer<CREATESTRUCTW>(bitPattern: UInt(lParam))!
        SetWindowLongPtrW(hWnd, GWLP_USERDATA, Int64(UInt(bitPattern: cs.pointee.lpCreateParams!)))
        return DefWindowProcW(hWnd, message, wParam, lParam)
    default:
        guard let window = getWindow(hWnd!) else {
            return DefWindowProcW(hWnd, message, wParam, lParam)
        }
        // Safe: Win32 message pump always runs on the main thread.
        return MainActor.assumeIsolated {
            window.takeUnretainedValue().wndProc(message, wParam, lParam)
        }
    }
}
