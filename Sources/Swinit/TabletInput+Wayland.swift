#if os(Linux)
import SwinitCore
import WaylandClientProtocols

extension TabletToolType {
    init(from raw: ZwpTabletToolV2.`Type`) {
        switch raw {
        case .pen:      self = .pen
        case .eraser:   self = .eraser
        case .brush:    self = .brush
        case .pencil:   self = .pencil
        case .airbrush: self = .airbrush
        case .finger:   self = .finger
        case .mouse:    self = .mouse
        case .lens:     self = .lens
        @unknown default: self = .unknown
        }
    }
}
#endif
