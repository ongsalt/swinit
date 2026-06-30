public enum TabletToolType: Sendable {
    case pen, eraser, brush, pencil, airbrush, finger, mouse, lens, unknown
}

public struct TabletToolFrame: Sendable {
    public var x: Double
    public var y: Double
    /// Normalised 0…1
    public var pressure: Double
    /// Normalised 0…1
    public var distance: Double
    /// Degrees from vertical
    public var tiltX: Double
    public var tiltY: Double
    /// Tool rotation in degrees (airbrush / mouse)
    public var rotation: Double
    public var time: UInt32

    public init(
        x: Double = 0, y: Double = 0,
        pressure: Double = 0, distance: Double = 0,
        tiltX: Double = 0, tiltY: Double = 0,
        rotation: Double = 0,
        time: UInt32 = 0
    ) {
        self.x = x; self.y = y
        self.pressure = pressure; self.distance = distance
        self.tiltX = tiltX; self.tiltY = tiltY
        self.rotation = rotation; self.time = time
    }
}

public enum TabletToolEvent: Sendable {
    case proximityIn(toolType: TabletToolType)
    case proximityOut
    case down
    case up
    case frame(TabletToolFrame)
    case button(id: UInt32, pressed: Bool)
}
