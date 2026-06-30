public struct TouchPoint: Sendable {
    /// Compositor-assigned touch point ID (unique per active touch)
    public var id: Int32
    public var x: Double
    public var y: Double
    public var time: UInt32

    public init(id: Int32, x: Double, y: Double, time: UInt32) {
        self.id = id; self.x = x; self.y = y; self.time = time
    }
}

public enum TouchEvent: Sendable {
    case down(TouchPoint)
    case up(id: Int32, time: UInt32)
    case moved(TouchPoint)
    /// All touch point updates for this frame have been delivered
    case frame
    /// All active touches were cancelled (e.g. system gesture intercepted)
    case cancelled
}
