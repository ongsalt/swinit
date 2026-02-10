/// memory location is gauranteed for at least lifetime of this
public class CArray<Element> {
    public let buffer: UnsafeMutableBufferPointer<Element>
    public var ptr: UnsafeMutablePointer<Element>? {
        buffer.baseAddress
    }

    public var readonly: UnsafePointer<Element>? {
        UnsafePointer(ptr)
    }

    public init(_ array: [Element]) {
        buffer = UnsafeMutableBufferPointer<Element>.allocate(capacity: array.count)
        buffer.initialize(from: array)
    }

    public convenience init(move array: consuming [Element]) {
        self.init(array)
    }

    deinit {
        buffer.deinitialize()
    }
}
