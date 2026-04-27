import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // Enforce a landscape-friendly window: the game's UI is laid out for a
    // wider-than-tall canvas. Allowing portrait shapes makes the menu /
    // splash card overflow and visually rotate.
    self.contentMinSize = NSSize(width: 960, height: 540)
    if windowFrame.width < 960 || windowFrame.height < 540 {
      self.setContentSize(NSSize(width: 1100, height: 620))
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
