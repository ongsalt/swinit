#if os(Windows)
    import SwinitCore
    import WinSDK
    import SwinitWin32
    import Foundation

    // MARK: - Win32 computed properties (backed by stored vars in Window.swift)

    extension Window {

        public var drawUnderTitleBar: Bool {
            get { _drawUnderTitleBar }
            set {
                _drawUnderTitleBar = newValue
                var margins = MARGINS(
                    cxLeftWidth: -1, cxRightWidth: -1,
                    cyTopHeight: newValue ? -1 : 25, cyBottomHeight: -1)
                _ = DwmExtendFrameIntoClientArea(handle, &margins)
            }
        }

        public var backdropStyle: WindowsBackdropStyle {
            get { _backdropStyle }
            set {
                _backdropStyle = newValue
                drawUnderTitleBar = _drawUnderTitleBar  // re-apply margins
                var pref = newValue.rawValue
                DwmSetWindowAttribute(handle, 38, &pref, UInt32(MemoryLayout<UInt32>.size))
            }
        }

        public var titleBarAppearance: TitleBarAppearance {
            get { _titleBarAppearance }
            set {
                _titleBarAppearance = newValue
                applyTitleBarAppearance()
            }
        }

        // MARK: Platform setup (called from Window.init)

        func setupWin32Platform(attributes: WindowAttributes) {
            hInstance = GetModuleHandleW(nil)!
            Window.registerWindowClass()

            let selfPtr = Unmanaged.passUnretained(self).toOpaque()
            var exStyle: UInt32 = 0
            if attributes.noRedirectionBitmap { exStyle |= UInt32(WS_EX_NOREDIRECTIONBITMAP) }
            if attributes.transparency { exStyle |= UInt32(WS_EX_LAYERED) }

            Window.windowClassName.withCString(encodedAs: UTF16.self) { className in
                attributes.title.withCString(encodedAs: UTF16.self) { titlePtr in
                    handle = CreateWindowExW(
                        exStyle, className, titlePtr, WS_OVERLAPPEDWINDOW,
                        CW_USEDEFAULT, CW_USEDEFAULT,
                        Int32(attributes.size.width), Int32(attributes.size.height),
                        nil, nil, hInstance, selfPtr)!
                }
            }

            SetWindowPos(
                handle, nil, 0, 0, 0, 0,
                UInt32(SWP_NOSIZE) | UInt32(SWP_NOMOVE) | UInt32(SWP_DRAWFRAME)
                    | UInt32(SWP_SHOWWINDOW))

            _scaleFactor = Double(GetDpiForWindow(handle)) / 96.0
        }

        // MARK: Platform methods

        func platformSetTitle(_ title: String) {
            title.withCString(encodedAs: UTF16.self) { SetWindowTextW(handle, $0) }
        }

        func platformRequestRedraw() { _pendingRedraw = true }

        func platformRequestResize(to size: Size) {
            SetWindowPos(
                handle, nil, 0, 0, Int32(size.width), Int32(size.height),
                UINT(SWP_NOMOVE | SWP_NOZORDER))
        }

        func platformFocus() {
            SetForegroundWindow(handle)
            SetFocus(handle)
        }

        func platformDestroy() {
            SetWindowLongPtrW(handle, GWLP_USERDATA, 0)
            DestroyWindow(handle)
        }

        private func applyTitleBarAppearance() {
            var isDark: WindowsBool = _titleBarAppearance.resolvedDark ? true : false
            if DwmSetWindowAttribute(handle, 20, &isDark, DWORD(MemoryLayout<WindowsBool>.size))
                != S_OK
            {
                DwmSetWindowAttribute(handle, 19, &isDark, DWORD(MemoryLayout<WindowsBool>.size))
            }
        }

        // MARK: Window procedure

        func wndProc(_ message: UINT, _ wParam: WPARAM, _ lParam: LPARAM) -> LRESULT {
            switch message {
            case UINT(WM_ENTERSIZEMOVE):
                isResizing = true
                currentHeartbeatTimer = SetTimer(
                    handle, UInt64.random(in: .min ... .max),
                    EventLoop.tickIntervalMs, nil)
                return 0

            case UINT(WM_TIMER) where currentHeartbeatTimer != nil:
                _ = RunLoop.main.run(mode: .default, before: .distantPast)
                return 0

            case UINT(WM_EXITSIZEMOVE):
                isResizing = false
                if let t = currentHeartbeatTimer { KillTimer(handle, t) }
                var rect = RECT()
                GetClientRect(handle, &rect)
                let sz = Size(
                    width: UInt32(max(0, rect.right - rect.left)),
                    height: UInt32(max(0, rect.bottom - rect.top)))
                _size = sz
                dispatch(.resized(size: sz, isFinal: true))
                return 0

            case UINT(WM_SIZE):
                let sz = Size(width: UInt32(SwinitWin32.LOWORD(lParam)), height: UInt32(SwinitWin32.HIWORD(lParam)))
                _size = sz
                dispatch(.resized(size: sz, isFinal: !isResizing))
                return 0

            case UINT(WM_MOVE):
                let pos = PhysicalPosition(
                    Int32(Int16(bitPattern: SwinitWin32.LOWORD(lParam))),
                    Int32(Int16(bitPattern: SwinitWin32.HIWORD(lParam))))
                dispatch(.moved(pos))
                return 0

            case UINT(WM_CLOSE):
                dispatch(.closeRequested)
                return 0

            case UINT(WM_DESTROY):
                return 0

            case UINT(WM_SETFOCUS):
                dispatch(.focused(true))
                return 0
            case UINT(WM_KILLFOCUS):
                dispatch(.focused(false))
                return 0

            case UINT(WM_MOUSEMOVE):
                let pos = PhysicalPosition(
                    Double(Int16(bitPattern: SwinitWin32.LOWORD(lParam))),
                    Double(Int16(bitPattern: SwinitWin32.HIWORD(lParam))))
                dispatch(.cursorMoved(deviceId: .placeholder, position: pos))
                var tme = TRACKMOUSEEVENT(
                    cbSize: UInt32(MemoryLayout<TRACKMOUSEEVENT>.size),
                    dwFlags: UInt32(TME_LEAVE), hwndTrack: handle, dwHoverTime: 0)
                TrackMouseEvent(&tme)
                return 0

            case UINT(WM_MOUSELEAVE):
                dispatch(.cursorLeft(deviceId: .placeholder))
                return 0

            case UINT(WM_LBUTTONDOWN), UINT(WM_RBUTTONDOWN),
                UINT(WM_MBUTTONDOWN), UINT(WM_XBUTTONDOWN):
                dispatch(
                    .mouseInput(
                        deviceId: .placeholder, state: .pressed,
                        button: mouseButton(from: message, wParam: wParam)))
                return 0

            case UINT(WM_LBUTTONUP), UINT(WM_RBUTTONUP),
                UINT(WM_MBUTTONUP), UINT(WM_XBUTTONUP):
                dispatch(
                    .mouseInput(
                        deviceId: .placeholder, state: .released,
                        button: mouseButton(from: message, wParam: wParam)))
                return 0

            case UINT(WM_MOUSEWHEEL):
                dispatch(
                    .mouseWheel(
                        deviceId: .placeholder,
                        delta: wheelDelta(hiword: SwinitWin32.HIWORD(wParam), horizontal: false),
                        phase: .moved))
                return 0

            case UINT(WM_MOUSEHWHEEL):
                dispatch(
                    .mouseWheel(
                        deviceId: .placeholder,
                        delta: wheelDelta(hiword: SwinitWin32.HIWORD(wParam), horizontal: true),
                        phase: .moved))
                return 0

            case UINT(WM_KEYDOWN), UINT(WM_SYSKEYDOWN):
                let ev = KeyEvent(
                    physicalKey: UInt32((lParam >> 16) & 0xFF),
                    logicalKey: UInt32(wParam), state: .pressed,
                    isRepeat: (lParam & (1 << 30)) != 0)
                dispatch(.modifiersChanged(captureModifiers()))
                dispatch(.keyboardInput(deviceId: .placeholder, event: ev, isSynthetic: false))
                return 0

            case UINT(WM_KEYUP), UINT(WM_SYSKEYUP):
                let ev = KeyEvent(
                    physicalKey: UInt32((lParam >> 16) & 0xFF),
                    logicalKey: UInt32(wParam), state: .released, isRepeat: false)
                dispatch(.modifiersChanged(captureModifiers()))
                dispatch(.keyboardInput(deviceId: .placeholder, event: ev, isSynthetic: false))
                return 0

            case UINT(WM_DPICHANGED):
                _scaleFactor = Double(SwinitWin32.LOWORD(wParam)) / 96.0
                dispatch(.scaleFactorChanged(scaleFactor: _scaleFactor))
                let rect = UnsafePointer<RECT>(bitPattern: Int(lParam))!.pointee
                SetWindowPos(
                    handle, nil,
                    rect.left, rect.top,
                    rect.right - rect.left, rect.bottom - rect.top,
                    UINT(SWP_NOZORDER | SWP_NOACTIVATE))
                return 0

            case UINT(WM_PAINT):
                dispatch(.redrawRequested)
                ValidateRect(handle, nil)
                return 0

            case UINT(WM_ERASEBKGND):
                return 1

            default:
                return DefWindowProcW(handle, message, wParam, lParam)
            }
        }

        // MARK: Window class registration

        static let windowClassName = "swinit_window"
        private static var windowClassRegistered = false

        static func registerWindowClass() {
            guard !windowClassRegistered else { return }
            windowClassRegistered = true
            SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2)
            windowClassName.withCString(encodedAs: UTF16.self) { namePtr in
                var wc = WNDCLASSEXW(
                    cbSize: UInt32(MemoryLayout<WNDCLASSEXW>.size),
                    style: UInt32(CS_HREDRAW | CS_VREDRAW),
                    lpfnWndProc: globalWndProc,
                    cbClsExtra: 0, cbWndExtra: 0,
                    hInstance: GetModuleHandleW(nil),
                    hIcon: nil,
                    hCursor: LoadCursorW(nil, UnsafePointer(bitPattern: 32512)),
                    hbrBackground: UnsafeMutablePointer(bitPattern: Int(COLOR_WINDOWFRAME)),
                    lpszMenuName: nil, lpszClassName: namePtr, hIconSm: nil)
                if RegisterClassExW(&wc) == 0 {
                    let err = GetLastError()
                    guard err == DWORD(ERROR_CLASS_ALREADY_EXISTS) else {
                        fatalError("RegisterClassExW failed: \(err)")
                    }
                }
            }
        }
    }

    // MARK: - File-private Win32 helpers

    private func getWindow(_ hWnd: HWND) -> Unmanaged<Window>? {
        let ud = UInt(GetWindowLongPtrW(hWnd, Int32(GWLP_USERDATA)))
        guard let ptr = UnsafeRawPointer(bitPattern: ud) else { return nil }
        return Unmanaged<Window>.fromOpaque(ptr)
    }

    private func globalWndProc(_ hWnd: HWND?, _ msg: UINT, _ wParam: WPARAM, _ lParam: LPARAM)
        -> LRESULT
    {
        if msg == UINT(WM_NCCREATE) {
            let cs = UnsafeMutablePointer<CREATESTRUCTW>(bitPattern: UInt(lParam))!
            SetWindowLongPtrW(
                hWnd, GWLP_USERDATA,
                Int64(UInt(bitPattern: cs.pointee.lpCreateParams!)))
            return DefWindowProcW(hWnd, msg, wParam, lParam)
        }
        guard let window = getWindow(hWnd!) else {
            return DefWindowProcW(hWnd, msg, wParam, lParam)
        }
        return MainActor.assumeIsolated {
            window.takeUnretainedValue().wndProc(msg, wParam, lParam)
        }
    }

    private func mouseButton(from message: UINT, wParam: WPARAM) -> MouseButton {
        switch message {
        case UINT(WM_LBUTTONDOWN), UINT(WM_LBUTTONUP): return .left
        case UINT(WM_RBUTTONDOWN), UINT(WM_RBUTTONUP): return .right
        case UINT(WM_MBUTTONDOWN), UINT(WM_MBUTTONUP): return .middle
        default:
            let btn = SwinitWin32.HIWORD(wParam)
            return btn == XBUTTON1 ? .back : (btn == XBUTTON2 ? .forward : .other(btn))
        }
    }

    private func wheelDelta(hiword: WORD, horizontal: Bool) -> MouseScrollDelta {
        let raw = Int16(bitPattern: hiword)
        let value = Double(raw)
        if abs(raw) < WHEEL_DELTA {
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

#endif
