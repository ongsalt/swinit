// Copied from winit

// probably implementation private

public final class WindowId: Identifiable, Sendable {
  public init() {}
}
extension WindowId: Hashable {
  nonisolated public static func == (lhs: WindowId, rhs: WindowId) -> Bool {
    lhs.id == rhs.id
  }

  nonisolated public func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }
}
public struct PhysicalSize<U> {
  public var width: U
  public var height: U

  public init(width: U, height: U) {
    self.width = width
    self.height = height
  }
}
public typealias PhysicalPosition = SIMD2
public struct DeviceId: Equatable {
  public init() {}
}
public enum ElementState {
  case pressed
  case released
}

public enum MouseButton {
  case left
  case right
  case middle
  case back
  case forward
  case other(UInt16)
}

public enum MouseScrollDelta {
  case line(x: Double, y: Double)
  case pixel(x: Double, y: Double)
}

public enum TouchPhase {
  case started
  case moved
  case ended
  case cancelled
}

public struct Modifiers {
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

public struct KeyEvent {
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

public enum WindowEvent {
  // case activationTokenDone(serial: AsyncRequestSerial, token: ActivationToken)
  case resized(size: PhysicalSize<UInt32>, isFinal: Bool)
  case moved(PhysicalPosition<Int32>)
  case closeRequested
  case destroyed
  // case droppedFile(PathBuf)
  // case hoveredFile(PathBuf)
  // case hoveredFileCancelled
  case focused(Bool)
  case keyboardInput(deviceId: DeviceId, event: KeyEvent, isSynthetic: Bool)
  case modifiersChanged(Modifiers)
  // case ime(Ime)
  case cursorMoved(deviceId: DeviceId, position: PhysicalPosition<Double>)
  case cursorEntered(deviceId: DeviceId)
  case cursorLeft(deviceId: DeviceId)
  case mouseWheel(deviceId: DeviceId, delta: MouseScrollDelta, phase: TouchPhase)
  case mouseInput(deviceId: DeviceId, state: ElementState, button: MouseButton)
  // case pinchGesture(deviceId: DeviceId, delta: Double, phase: TouchPhase)
  // case panGesture(deviceId: DeviceId, delta: PhysicalPosition<Float>, phase: TouchPhase)
  // case doubleTapGesture(deviceId: DeviceId)
  // case rotationGesture(deviceId: DeviceId, delta: Float, phase: TouchPhase)
  // case touchpadPressure(deviceId: DeviceId, pressure: Float, stage: Int64)
  // case axisMotion(deviceId: DeviceId, axis: AxisId, value: Double)
  // case touch(Touch)
  // case scaleFactorChanged(scaleFactor: Double, innerSizeWriter: InnerSizeWriter)
  // case themeChanged(Theme)
  // case occluded(Bool) // ios only
  case redrawRequested
}
