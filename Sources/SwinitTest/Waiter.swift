import Dispatch
import Foundation
import WinSDK

class Waiter {
  init() {
    // TODO:
    // let timer = CreateWaitableTimer(nil, false, nil);

    // TODO: call this again if input drift
  }

  func wait(time: UInt32) async {
    DispatchQueue.global(qos: .userInitiated).async {
      // TODO: handle drift
      MsgWaitForMultipleObjects(0, nil, false, time, QS_ALLINPUT)

      NotificationCenter.default.post(name: NSNotification.Name.winWaiter, object: 420)
    }

    var token: (any NSObjectProtocol)? = nil
    await withUnsafeContinuation { continuation in
      token = NotificationCenter.default.addObserver(
        forName: NSNotification.Name.winWaiter, object: nil, queue: .main
      ) { _ in
        continuation.resume()
      }
    }
    consume token
  }

  func waitFr(threadId: DWORD, time: UInt32) {
    DispatchQueue.global(qos: .userInitiated).async {
      // TODO: handle drift
      MsgWaitForMultipleObjects(0, nil, false, time, QS_ALLINPUT)
      print("waited \(time / 1000) sec")
      PostThreadMessageA(threadId, 67, 0, 0)
    }
  }
}

extension NSNotification.Name {
  static let winWaiter: NSNotification.Name = NSNotification.Name("lt.ongsa.swinit.winWaiter")
}
