public struct WindowId: Hashable, Sendable {
    let rawValue: UInt64
    private init(_ v: UInt64) { rawValue = v }

    package static func generate() -> WindowId {
        WindowId(UInt64.random(in: 1...UInt64.max))
    }
}

public struct Size: Hashable, Sendable {
    public var width: UInt32
    public var height: UInt32

    public static let zero = Size(width: 0, height: 0)

    public init(width: UInt32, height: UInt32) {
        self.width = width
        self.height = height
    }
}
