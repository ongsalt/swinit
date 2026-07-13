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

            runWithRunLoop()

            delegate?.exiting(self)
        }

        func platformOpenWindow(_ attributes: WindowAttributes) -> Window {
            let id = WindowId.generate()
            let window = Window(id: id, eventLoop: self, attributes: attributes)
            windows[id] = window
            return window
        }

        func platformQuit() { 
            shouldQuit = true
         }

        func platformWindowRemoved(id: WindowId) {}

        func runWithRunLoop() {
            // RunLoop.main.run()
            shouldQuit = false
            while !shouldQuit {
                // wakes on: window messages (QS_ALLINPUT mask Foundation set),
                // dispatch main queue, timers. Returns after each serviced batch.
                // On windows this call is blocking, its not everywhere else 
                _ = RunLoop.main.run(mode: .default, before: .distantFuture)

                delegate?.aboutToWait(self)
                for window in Array(windows.values) where window._pendingRedraw {
                    window._pendingRedraw = false
                    window.dispatch(.redrawRequested)
                }
            }

        }
    }

#endif
