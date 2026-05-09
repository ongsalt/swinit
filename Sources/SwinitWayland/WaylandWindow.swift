import SwinitCommon

public class WaylandWindow {
    private let rawWindow: RawWindow

    public init(display: Display, attributes: WindowAttributes) {
        self.rawWindow = RawWindow(display: display, title: attributes.title)
    }
}

extension WaylandWindow: IWindow {
    public func requestRedraw() {
        rawWindow.requestRedraw()   
        rawWindow.show()
    }

    public func focus() {
        fatalError("TODO: WaylandWindow::focus")
    }
}