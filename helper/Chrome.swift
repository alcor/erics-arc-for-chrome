// What the helper knows about Chrome: starting it with the launch flags its flags page doesn't offer,
// whether it's in front, and where its front window is.
//
// OmniboxForceAllowedToBeDefault lets a history page be the address bar's Enter target even when what
// you typed isn't the start of its address ("acme/commits" -> github.com/acme-corp/app/commits).
// Chrome reads --enable-features only at startup, so a Chrome started some other way runs without it
// until it's quit and reopened through this app; the Dock icon and the login item both come here.
import AppKit

enum Chrome {
  static let bundleId = "com.google.Chrome"
  static let features = ["OmniboxForceAllowedToBeDefault"]

  static var running: NSRunningApplication? { NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first }
  static var isFrontmost: Bool { NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleId }

  // Launches with the flags, or hands URLs to the running one (which opens them as tabs: the extension
  // turns those into Little Arcs). activate: bring it to the front either way.
  static func open(_ urls: [URL] = [], activate: Bool) {
    guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = activate
    if running == nil { configuration.arguments = ["--enable-features=" + features.joined(separator: ",")] }
    if urls.isEmpty {
      NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
    } else {
      NSWorkspace.shared.open(urls, withApplicationAt: appURL, configuration: configuration)
    }
  }

  // A Chrome that was started some other way is missing its flags. Say so instead of silently doing nothing.
  static func warnIfStartedWithoutFlags() {
    guard let running else { return }
    let ps = Process()
    ps.executableURL = URL(fileURLWithPath: "/bin/ps")
    ps.arguments = ["-o", "args=", "-p", String(running.processIdentifier)]
    let out = Pipe()
    ps.standardOutput = out
    guard (try? ps.run()) != nil else { return }
    let args = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    let have = args.split(separator: " ").first { $0.hasPrefix("--enable-features=") }?.dropFirst(18).split(separator: ",").map(String.init) ?? []
    guard features.contains(where: { !have.contains($0) }) else { return }
    let script = Process()
    script.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    script.arguments = ["-e", #"display notification "Quit Chrome (⌘Q) and open it from the Dock to turn the address-bar fix back on." with title "Chrome is running without its launch flags""#]
    try? script.run()
  }

  // The front Chrome window's frame in AppKit coordinates (up from the bottom of the main screen).
  // Window bounds need no permission; only window titles would.
  static var frontWindowFrame: NSRect? {
    guard let running, let primary = NSScreen.screens.first else { return nil }
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    let frame = windows.lazy
      .filter { $0[kCGWindowOwnerPID as String] as? pid_t == running.processIdentifier && $0[kCGWindowLayer as String] as? Int == 0 }
      .compactMap { ($0[kCGWindowBounds as String] as? NSDictionary).flatMap { CGRect(dictionaryRepresentation: $0) } }
      .first { $0.width > 200 && $0.height > 200 }
    guard let frame else { return nil }
    return NSRect(x: frame.minX, y: primary.frame.height - frame.maxY, width: frame.width, height: frame.height)
  }
}
