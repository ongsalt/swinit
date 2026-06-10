import Foundation
import SwinitCore
import WinSDK

@MainActor
public final class EventLoop: SwinitCore.EventLoopProtocol {
    public typealias Window = SwinitWin32.Window

    let controlFlow: ControlFlow
    var responder: (any SwinitCore.Responder<EventLoop>)? = nil

    public init?(controlFlow: ControlFlow = .default) {
        self.controlFlow = controlFlow
    }

    public func createWindow(attributes: WindowAttributes) -> Window {
        Window(eventLoop: self, attributes: attributes)
    }

    /// On Win32 attach() blocks the calling thread until stop() is called.
    /// The returned Watch.cancel() is a no-op — use stop() to exit the loop.
    @discardableResult
    public func attach<R: SwinitCore.Responder>(_ responder: R) -> SwinitCore.Watch
    where R.EventLoop == EventLoop {
        self.responder = responder
        responder.resumed(eventLoop: self)
        switch controlFlow {
        case .poll: _ = runPollingLoop()
        default: _ = runWaitingLoop()
        }
        return SwinitCore.Watch {}
    }

    // Overrides the default protocol extension — attach() already ran the message loop.
    public func run<R: SwinitCore.Responder>(_ responder: R) where R.EventLoop == EventLoop {
        _ = attach(responder)
    }

    public func stop() {
        PostQuitMessage(0)
    }

    func dispatch(_ event: WindowEvent, from window: Window) {
        responder?.windowEvent(eventLoop: self, window: window, event: event)
    }

    // MARK: - Message loops

    static let tickIntervalMs: UInt32 = 1

    private func runPollingLoop() -> Int32 {
        var msg = MSG()
        var nExitCode: Int32 = EXIT_SUCCESS

        mainLoop: while true {
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
                time = RunLoop.main.limitDate(forMode: .default)
            } while (time?.timeIntervalSinceNow ?? -1) <= 0

            _ = MsgWaitForMultipleObjects(
                0, nil, false,
                DWORD(exactly: time?.timeIntervalSinceNow ?? -1) ?? 0,
                QS_ALLINPUT | DWORD(QS_KEY) | DWORD(QS_TOUCH) | QS_MOUSE | DWORD(QS_RAWINPUT))
        }

        return nExitCode
    }

    private func runWaitingLoop() -> Int32 {
        var msg = MSG()
        var nExitCode: Int32 = EXIT_SUCCESS
        let heartbeatTimer = SetTimer(nil, 0, Self.tickIntervalMs, nil)

        while GetMessageW(&msg, nil, 0, 0) {
            switch msg.message {
            case UINT(WM_TIMER) where msg.wParam == heartbeatTimer:
                RunLoop.main.run(until: .distantPast)
            case UINT(WM_QUIT):
                nExitCode = Int32(msg.wParam)
                break
            default:
                TranslateMessage(&msg)
                DispatchMessageW(&msg)
            }
        }

        return nExitCode
    }
}
