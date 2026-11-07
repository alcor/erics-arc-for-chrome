// What the helper knows about Chrome: starting it with the launch flags its flags page doesn't offer,
// whether it's in front, and where its front window is.
//
// OmniboxForceAllowedToBeDefault lets a history page be the address bar's Enter target even when what
// you typed isn't the start of its address ("acme/commits" -> github.com/acme-corp/app/commits).
// Chrome reads --enable-features only at startup, so a Chrome started some other way runs without it
// until it's quit and reopened through this app; the Dock icon and the login item both come here.
import AppKit
import UserNotifications

enum Chrome {
  static let bundleId = "com.google.Chrome"
  static let features = ["OmniboxForceAllowedToBeDefault"]

  static var running: NSRunningApplication? { NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first }
  static var isFrontmost: Bool { NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleId }

  // Launches with the flags, or hands URLs to the running one (which opens them as tabs: the extension
  // turns those into mini browsers). activate: bring it to the front either way.
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

  // A Chrome that was started some other way is missing its flags. Say so, once per Chrome launch,
  // instead of silently doing nothing.
  static var warnedPid: pid_t = 0
  static func warnIfStartedWithoutFlags() {
    guard let running, running.processIdentifier != warnedPid else { return }
    let ps = Process()
    ps.executableURL = URL(fileURLWithPath: "/bin/ps")
    ps.arguments = ["-o", "args=", "-p", String(running.processIdentifier)]
    let out = Pipe()
    ps.standardOutput = out
    guard (try? ps.run()) != nil else { return }
    let args = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    let have = args.split(whereSeparator: { $0 == " " || $0 == "\n" })
      .first { $0.hasPrefix("--enable-features=") }?.dropFirst("--enable-features=".count).split(separator: ",").map(String.init) ?? []
    guard features.contains(where: { !have.contains($0) }) else { return }
    warnedPid = running.processIdentifier
    let center = UNUserNotificationCenter.current()
    center.requestAuthorization(options: [.alert]) { granted, _ in
      guard granted else { return }
      let content = UNMutableNotificationContent()
      content.title = "Chrome is running without its launch flags"
      content.body = "Quit Chrome (⌘Q) and open it from the Dock to turn the address-bar fix back on."
      center.add(UNNotificationRequest(identifier: "launch-flags", content: content, trigger: nil))
    }
  }

  struct Window {
    let id: CGWindowID // the window server's number, the same one NSWindow calls windowNumber
    let frame: CGRect
  }

  // Chrome's windows on screen, front to back, in window-list coordinates (down from the top of the
  // main screen). Window bounds need no permission; only window titles would.
  static func windows() -> [Window] {
    guard let running else { return [] }
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    return windows
      .filter { $0[kCGWindowOwnerPID as String] as? pid_t == running.processIdentifier && $0[kCGWindowLayer as String] as? Int == 0 }
      .compactMap { w -> Window? in
        guard let id = w[kCGWindowNumber as String] as? CGWindowID,
              let frame = (w[kCGWindowBounds as String] as? NSDictionary).flatMap({ CGRect(dictionaryRepresentation: $0) }),
              frame.width > 120, frame.height > 80 else { return nil }
        return Window(id: id, frame: frame)
      }
  }

  static func windowFrames() -> [CGRect] { windows().map(\.frame) }

  // Window-list coordinates to AppKit's, which count up from the bottom of the main screen.
  static func appKit(_ frame: CGRect) -> NSRect {
    let height = NSScreen.screens.first?.frame.height ?? 0
    return NSRect(x: frame.minX, y: height - frame.maxY, width: frame.width, height: frame.height)
  }

  static var frontWindowFrame: NSRect? { windowFrames().first { $0.width > 200 && $0.height > 200 }.map(appKit) }
}
