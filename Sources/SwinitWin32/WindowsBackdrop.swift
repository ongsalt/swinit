import CWin32

public enum WindowsBackdropStyle {
  case auto
  case none
  case main
  case transient
  case tabbed

  var underlying: DWM_SYSTEMBACKDROP_TYPE {
    switch self {
    case .auto:
      DWMSBT_AUTO
    case .none:
      DWMSBT_NONE
    case .main:
      DWMSBT_MAINWINDOW
    case .transient:
      DWMSBT_TRANSIENTWINDOW
    case .tabbed:
      DWMSBT_TABBEDWINDOW
    }
  }
}
