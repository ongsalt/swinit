// The Swift Programming Language
// https://docs.swift.org/swift-book

// import CoreD
import Foundation
import WinSDK
import Dispatch
import swinit

@main
public struct Main {
  public static func main() {
    // this wont run unless we have a window openned? (or fucking ping the main thread)
    Task.immediate {
      print("Start")
      while !Task.isCancelled {
        try await Task.sleep(for: .seconds(1))
        print("- interval")
      }
    }

    RunLoop.main.run(until: .distantPast)

    // tickrate: 0 ms take fucking 5% of my cpu
    // tickrate: 1-15 ms got about 60 tick per sec on a 60 fps screen (idk if its related or not)
    // tickrate: nil is never tick unless there is an event
    // which is still ass
    win32RunLoop(tickrate: 10)
    
    // wont work unless you have a window

    // while this is practically zero
    // RunLoop.main.run()
  }
}
