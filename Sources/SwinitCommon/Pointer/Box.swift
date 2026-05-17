package class Box<T> {
    public let ptr: UnsafeMutablePointer<T>
    public var readonly: UnsafePointer<T> {
        UnsafePointer(ptr)
    }
    public var opaque: OpaquePointer {
        OpaquePointer(ptr)
    }

    public var raw: UnsafeRawPointer {
        UnsafeRawPointer(ptr)
    }

    public init(_ value: T, mutate: ((inout T) -> Void)? = nil) {
        var value = value
        if let mutate {
            mutate(&value)
        }
        ptr = UnsafeMutablePointer.allocate(capacity: 1)
        ptr.initialize(to: value)
    }

    public convenience init<K>(optional value: K) where T == K? {
        self.init(value)
    }

    public convenience init(leaking value: T) {
        self.init(value)
        self.leak()
    }

    public var pointee: T {
        get {
            ptr.pointee
        }
        _modify {
            yield &ptr.pointee
        }
        set {
            ptr.pointee = newValue
        }
    }
    public var value: T {
        get {
            ptr.pointee
        }
        _modify {
            yield &ptr.pointee
        }
        set {
            ptr.pointee = newValue
        }
    }
    public subscript() -> T {
        get {
            ptr.pointee
        }
        _modify {
            yield &ptr.pointee
        }
        set {
            ptr.pointee = newValue
        }
    }

    public func mutate(_ block: (inout T) -> Void) {
        block(&pointee)
    }

    @discardableResult
    public func leak() -> Box<T> {
        Unmanaged.passRetained(self)

        return self
    }

    deinit {
        ptr.deinitialize(count: 1)
        ptr.deallocate()
    }
}
