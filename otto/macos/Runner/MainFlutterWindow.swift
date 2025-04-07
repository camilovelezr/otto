import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    
    // Basic window setup
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    
    // Set minimum window size
    self.minSize = NSSize(width: 800, height: 600)
    
    // Configure window style
    self.styleMask = [.titled, .closable, .miniaturizable, .resizable]
    self.titlebarAppearsTransparent = false
    self.isOpaque = true
    
    // Register plugins
    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
