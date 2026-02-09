// // Copyright © 2019 Saleem Abdulrasool <compnerd@compnerd.org>
// // SPDX-License-Identifier: BSD-3-Clause

// import WinSDK
// import Foundation


// // private let pApplicationStateChangeRoutine: PAPPSTATE_CHANGE_ROUTINE = { (quiesced: UInt8, context: PVOID?) in
// //   let foregrounding: Bool = quiesced == 0
// //   if foregrounding {
// //     Application.shared.delegate?
// //         .applicationWillEnterForeground(Application.shared)

// //     // Post ApplicationDelegate.willEnterForegroundNotification
// //     NotificationCenter.default
// //         .post(name: Delegate.willEnterForegroundNotification,
// //               object: Application.shared)
// //   } else {
// //     Application.shared.delegate?
// //         .applicationDidEnterBackground(Application.shared)

// //     // Post ApplicationDelegate.willEnterBackgroundNotification
// //     NotificationCenter.default
// //         .post(name: Delegate.didEnterBackgroundNotification,
// //               object: Application.shared)
// //   }
// // }

// @discardableResult
// public func ApplicationMain(_ argc: Int32,
//                             _ argv: UnsafeMutablePointer<UnsafeMutablePointer<Int8>?>,
//                             _ application: String?,
//                             _ delegate: String?) -> Int32 {

//   // var information: Application.Information?
//   // if let path = Bundle.main.path(forResource: "Info", ofType: "plist"),
//   //     let contents = FileManager.default.contents(atPath: path) {
//   //   information = try? PropertyListDecoder().decode(Application.Information.self,
//   //                                                   from: contents)
//   // }

//   // Setup the main application class.  The following order describes how the
//   // user may actually configure the selected class:
//   //
//   //    1. `application`: the parameter passed to `ApplicationMain(_:_:_:_:)`
//   //    2. `PrincipalClass`: the value configured in `Info.plist`
//   //    3. `Application`: the default application class provided by Swift/Win32
//   //
//   // We must have an application class to instantiate as this is the main entry
//   // point which is executed by this framework.


//   // Initialize COM
//   do {
//     let result = CoInitializeEx(nil, DWORD32(COINIT_MULTITHREADED.rawValue))
//   } catch {
//     // log.error("CoInitializeEx: \(error)")
//     return EXIT_FAILURE
//   }

//   // Enable Per Monitor DPI Awareness
//   if !SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2) {
//     // log.error("SetProcessDpiAwarenessContext: \(Error(win32: GetLastError()))")
//   }


//   // RegisterAppStateChangeNotification

//   // Post ApplicationDelegate.didFinishLaunchingNotification

//   // Application.shared.delegate?
//   //     .applicationDidBecomeActive(Application.shared)

//   // TODO(compnerd) populate these based on the application instantiation


//   var msg: MSG = MSG()
//   var nExitCode: Int32 = EXIT_SUCCESS

//   mainLoop: while true {
//     // Process all messages in thread's message queue; for GUI applications UI
//     // events must have high priority.
//     while PeekMessageW(&msg, nil, 0, 0, UINT(PM_REMOVE)) {
//       if msg.message == UINT(WM_QUIT) {
//         nExitCode = Int32(msg.wParam)
//         break mainLoop
//       }

//       TranslateMessage(&msg)
//       DispatchMessageW(&msg)
//     }

//     var time: Date? = nil
//     repeat {
//       // Execute Foundation.RunLoop once and determine the next time the timer
//       // fires.  At this point handle all Foundation.RunLoop timers, sources and
//       // Dispatch.DispatchQueue.main tasks
//       time = RunLoop.main.limitDate(forMode: .default)

//       // If Foundation.RunLoop doesn't contain any timers or the timers should
//       // not be running right now, we interrupt the current loop or otherwise
//       // continue to the next iteration.
//     } while (time?.timeIntervalSinceNow ?? -1) <= 0

//     // Yield control to the system until the earlier of a requisite timer
//     // expiration or a message is posted to the runloop.
//     _ = MsgWaitForMultipleObjects(0, nil, false,
//                                   DWORD(exactly: time?.timeIntervalSinceNow ?? -1)
//                                       ?? INFINITE,
//                                   QS_ALLINPUT | DWORD(QS_KEY) | QS_MOUSE | DWORD(QS_RAWINPUT))
//   }


//   return nExitCode
// }

// // extension ApplicationDelegate {
// //   public static func main() {
// //     ApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil,
// //                     String(describing: String(reflecting: Self.self)))
// //   }
// // }