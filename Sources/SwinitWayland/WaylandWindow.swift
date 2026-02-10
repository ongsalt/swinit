import SwinitCommon

public class WaylandWindow {
    private let rawWindow: RawWindow

    public init(display: Display, title: String) {
        self.rawWindow = RawWindow(display: display, title: title)
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