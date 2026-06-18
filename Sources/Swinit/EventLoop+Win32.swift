#if os(Windows)
    import SwinitCore
    import Foundation
    import WinSDK
    import SwinitWin32

    extension EventLoop {

        func platformRun() {
            Window.registerWindowClass()

            delegate?.canCreateSurfaces(self)
            delegate?.appResumed(self)

            runPolling()

            delegate?.exiting(self)
        }

        func platformOpenWindow(_ attributes: WindowAttributes) -> Window {
            let id = WindowId.generate()
            let window = Window(id: id, eventLoop: self, attributes: attributes)
            windows[id] = window
            return window
        }

        func platformQuit() { PostQuitMessage(0) }

        func platformWindowRemoved(id: WindowId) {}

        // copied from https://github.com/compnerd/swift-win32/blob/d34ff1b8b3f15cfdf2cb71109a3c313001122a54/Sources/SwiftWin32/App%20and%20Environment/ApplicationMain.swift
        func runPolling() {
            var msg = MSG()
            outer: while true {
                while PeekMessageW(&msg, nil, 0, 0, UINT(PM_REMOVE)) {
                    if msg.message == UINT(WM_QUIT) { break outer }
                    TranslateMessage(&msg)
                    DispatchMessageW(&msg)
                }

                var time: Date?
                repeat {
                    time = RunLoop.main.limitDate(forMode: .default)
                } while (time?.timeIntervalSinceNow ?? -1) <= 0

                _ = MsgWaitForMultipleObjects(
                    0, nil, false,
                    DWORD(exactly: time?.timeIntervalSinceNow ?? -1) ?? INFINITE,
                    QS_ALLINPUT)
            }
        }
    }

#endif
