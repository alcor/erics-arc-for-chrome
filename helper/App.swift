// The app half: launched at login (it registers itself as a login item) and from the Dock, where it
// wears Chrome's icon so that opening Chrome goes through it and gets the launch flags. Also the
// default browser: links from other apps arrive here and go to the extension over the bridge, which
// opens them as Little Arcs without a tab ever passing through the main window. If the extension isn't
// connected, the link goes to Chrome the ordinary way and the extension catches it there.
import AppKit
import ServiceManagement

final class App: NSObject, NSApplicationDelegate {
  static let bundleId = "local.arc-for-chrome.helper"
  let switcher = Switcher()
  let player = Player()
  let tap = Tap()
  var server: SocketServer?
  var host: LineSocket?
  var session: String?

  func applicationDidFinishLaunching(_ notification: Notification) {
    signal(SIGPIPE, SIG_IGN)
    NSApp.setActivationPolicy(.accessory)
    try? SMAppService.mainApp.register()

    tap.switcher = switcher
    tap.useSwitcher = { [weak self] in self?.host != nil && (self?.switcher.tabs.count ?? 0) > 1 }
    switcher.onActivate = { [weak self] id in self?.send(["activate": id]) }
    player.onAction = { [weak self] action in self?.send(["player": ["action": action]]) }

    server = SocketServer(path: Socket.path, queue: .main)
    if server == nil { log.error("socket: could not listen at \(Socket.path)") }
    server?.onConnection = { [weak self] peer in
      guard let self else { return }
      log.info("host: connected")
      host?.stop()
      host = peer
      peer.onLine = { [weak self] line in
        guard let message = JSONLine.decode(line) else { return }
        self?.receive(message)
      }
      peer.onClose = { [weak self] in
        log.info("host: disconnected")
        if self?.host === peer { self?.host = nil; self?.player.apply(nil) }
      }
    }

    whenTrusted { [weak self] in
      let installed = self?.tap.install() ?? false
      log.info("tap: \(installed ? "installed" : "could not be created")")
    }
    if Chrome.running == nil { Chrome.open(activate: false) } else { Chrome.warnIfStartedWithoutFlags() }
  }

  // The Dock icon (and the login item, on a Mac where the app was already running).
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
    Chrome.open(activate: true)
    Chrome.warnIfStartedWithoutFlags()
    return false
  }

  // Links from other apps, as the default browser.
  func application(_ application: NSApplication, open urls: [URL]) {
    let web = urls.filter { ["http", "https"].contains($0.scheme?.lowercased()) }
    guard !web.isEmpty else { return }
    if host != nil {
      for url in web { send(["open": url.absoluteString]) }
      Chrome.running?.activate()
    } else {
      Chrome.open(web, activate: true)
    }
  }

  func send(_ message: [String: Any]) {
    guard let line = JSONLine.encode(message) else { return }
    host?.send(line)
  }

  func receive(_ message: [String: Any]) {
    if let hello = message["hello"] as? [String: Any] {
      let now = hello["session"] as? String
      if now != session { switcher.thumbs = [:]; switcher.tabs = [] }
      session = now
    }
    if let mru = message["mru"] as? [[String: Any]] {
      log.info("mru: \(mru.count) tabs")
      switcher.tabs = mru.compactMap { tab in
        guard let id = tab["id"] as? Int, let windowId = tab["windowId"] as? Int else { return nil }
        return TabInfo(id: id, windowId: windowId, title: tab["title"] as? String ?? "", favicon: image(tab["favicon"] as? String))
      }
    }
    if let thumb = message["thumb"] as? [String: Any], let id = thumb["id"] as? Int, let image = image(thumb["data"] as? String) {
      log.info("thumb: tab \(id)")
      switcher.thumbs[id] = image
    }
    if let closed = message["closed"] as? Int { switcher.forget(tab: closed) }
    if message.keys.contains("player") {
      let state = (message["player"] as? [String: Any]).flatMap { try? JSONSerialization.data(withJSONObject: $0) }
        .flatMap { try? JSONDecoder().decode(PlayerState.self, from: $0) }
      player.apply(state)
    }
  }

  // Images arrive as data: URLs.
  func image(_ dataURL: String?) -> NSImage? {
    guard let dataURL, let comma = dataURL.firstIndex(of: ","), dataURL.hasPrefix("data:"),
          let data = Data(base64Encoded: String(dataURL[dataURL.index(after: comma)...]))
    else { return nil }
    return NSImage(data: data)
  }

  // The event tap needs Accessibility. Ask once, then wait for the switch to be flipped.
  func whenTrusted(_ then: @escaping () -> Void) {
    let prompt = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    if AXIsProcessTrustedWithOptions(prompt) { return then() }
    log.info("accessibility: not granted yet, waiting")
    Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { timer in
      if AXIsProcessTrusted() {
        timer.invalidate()
        then()
      }
    }
  }
}
