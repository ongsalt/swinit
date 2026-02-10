import CoreFoundation


// TODO: actully getting CFRunLoop from a RunLoop
public class RunLoopObserver {
    let observer: CFRunLoopObserver
    let runLoop: CFRunLoop

    public init(
        on activities: [CFRunLoopActivity],
        runLoop: CFRunLoop = CFRunLoopGetCurrent(),
        repeated: Bool = true,
        priority: Int = 0,
        _ callback: @escaping (CFRunLoopActivity) -> Void
    ) {
        self.runLoop = runLoop

        let activities = activities.reduce(CFOptionFlags()) { partialResult, activity in
            activity.rawValue | partialResult
        }

        observer = CFRunLoopObserverCreateWithHandler(
            nil, activities, repeated, priority
        ) { observer, activity in
            callback(activity)
        }!
    }

    public func start() {
        CFRunLoopAddObserver(runLoop, observer, kCFRunLoopDefaultMode)
    }

    public func stop() {
        CFRunLoopRemoveObserver(runLoop, observer, kCFRunLoopDefaultMode)
    }
}
