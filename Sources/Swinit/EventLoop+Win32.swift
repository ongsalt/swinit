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

            runWaitingLoop()

            delegate?.appSuspended(self)
            delegate?.destroySurfaces(self)
        }

        func platformOpenWindow(_ attributes: WindowAttributes) -> Window {
            let id = WindowId.generate()
            let window = Window(id: id, eventLoop: self, attributes: attributes)
            windows[id] = window
            return window
        }

        func platformQuit() { PostQuitMessage(0) }

        func platformWindowRemoved(id: WindowId) {}

        private func runWaitingLoop() {
            var msg = MSG()
            let heartbeatTimer = SetTimer(nil, 0, Self.tickIntervalMs, nil)
            while GetMessageW(&msg, nil, 0, 0) {
                switch msg.message {
                case UINT(WM_TIMER) where msg.wParam == heartbeatTimer:
                    RunLoop.main.run(until: .distantPast)
                case UINT(WM_QUIT):
                    break
                default:
                    TranslateMessage(&msg)
                    DispatchMessageW(&msg)
                }
            }
            KillTimer(nil, heartbeatTimer)
        }

        /// Poll-mode entry point for game loops. Calls `aboutToWait` each frame.
        public func runPolling() {
            Window.registerWindowClass()
            delegate?.canCreateSurfaces(self)
            delegate?.appResumed(self)

            var msg = MSG()
            outer: while true {
                while PeekMessageW(&msg, nil, 0, 0, UINT(PM_REMOVE)) {
                    if msg.message == UINT(WM_QUIT) { break outer }
                    TranslateMessage(&msg)
                    DispatchMessageW(&msg)
                }
                delegate?.aboutToWait(self)

                var time: Date?
                repeat {
                    time = RunLoop.main.limitDate(forMode: .default)
                } while (time?.timeIntervalSinceNow ?? -1) <= 0

                _ = MsgWaitForMultipleObjects(
                    0, nil, false,
                    DWORD(exactly: time?.timeIntervalSinceNow ?? -1) ?? 0,
                    QS_ALLINPUT | DWORD(QS_KEY) | DWORD(QS_TOUCH) | QS_MOUSE | DWORD(QS_RAWINPUT))
            }

            delegate?.appSuspended(self)
            delegate?.destroySurfaces(self)
        }
    }

#endif
