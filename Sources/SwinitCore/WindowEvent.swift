public struct PhysicalSize<U: Sendable>: Sendable {
    public var width: U
    public var height: U
    public init(width: U, height: U) {
        self.width = width
        self.height = height
    }
}

public typealias PhysicalPosition = SIMD2

public struct DeviceId: Equatable, Sendable {
    public init() {}
    /// Placeholder used until proper per-device OS tracking is implemented.
    public static let placeholder = DeviceId()
}

public enum ElementState: Sendable {
    case pressed
    case released
}

public enum MouseButton: Sendable {
    case left
    case right
    case middle
    case back
    case forward
    case other(UInt16)
}

public enum MouseScrollDelta: Sendable {
    case line(x: Double, y: Double)
    case pixel(x: Double, y: Double)
}

public enum TouchPhase: Sendable {
    case started
    case moved
    case ended
    case cancelled
}

public struct Modifiers: Sendable {
    public var shift: Bool
    public var control: Bool
    public var alt: Bool
    public var superKey: Bool

    public init(shift: Bool = false, control: Bool = false, alt: Bool = false, superKey: Bool = false) {
        self.shift = shift
        self.control = control
        self.alt = alt
        self.superKey = superKey
    }
}

public struct KeyEvent: Sendable {
    public var physicalKey: UInt32
    public var logicalKey: UInt32
    public var text: String?
    public var state: ElementState
    public var isRepeat: Bool

    public init(physicalKey: UInt32, logicalKey: UInt32, text: String? = nil, state: ElementState, isRepeat: Bool) {
        self.physicalKey = physicalKey
        self.logicalKey = logicalKey
        self.text = text
        self.state = state
        self.isRepeat = isRepeat
    }
}

public enum WindowState: Sendable {
    case normal
    case maximized
    case fullscreen
    case minimized
}

public enum WindowEvent: Sendable {
    case resized(size: PhysicalSize<UInt32>, isFinal: Bool)
    case moved(PhysicalPosition<Int32>)
    case closeRequested
    case destroyed
    case focused(Bool)
    case stateChanged(WindowState)
    case keyboardInput(deviceId: DeviceId, event: KeyEvent, isSynthetic: Bool)
    case modifiersChanged(Modifiers)
    case cursorMoved(deviceId: DeviceId, position: PhysicalPosition<Double>)
    case cursorEntered(deviceId: DeviceId)
    case cursorLeft(deviceId: DeviceId)
    case mouseWheel(deviceId: DeviceId, delta: MouseScrollDelta, phase: TouchPhase)
    case mouseInput(deviceId: DeviceId, state: ElementState, button: MouseButton)
    case redrawRequested
}
