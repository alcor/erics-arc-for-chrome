// The app half: launched at login (it registers itself as a login item) and from the Dock, where it
// takes Chrome's place so that opening Chrome goes through it and gets the launch flags. Also the
// default browser: links from other apps arrive here and go to the extension over the bridge, which
// opens them as mini browsers without a tab ever passing through the main window. If the extension isn't
// connected, the link goes to Chrome the ordinary way and the extension catches it there.
//
// Chrome runs one copy of the extension per profile, each with its own port, so there is one
// connection per profile here. Tab and window ids are unique across a Chrome process, so lists merge;
// what needs routing is which connection gets a message: the owner of a tab or mini browser, or the
// one whose front window is the window in front on screen.
import AppKit
import ServiceManagement

final class Connection {
  let peer: LineSocket
  var tabs: [TabInfo] = []
  var front: (id: Int, frame: CGRect)?
  var minis: [MiniBrowser] = []
  var targets: [Target] = []
  init(peer: LineSocket) { self.peer = peer }
}

final class App: NSObject, NSApplicationDelegate {
  static let bundleId = "local.monochrome"
  let switcher = Switcher()
  let player = Player()
  let minis = MiniBrowsers()
  let profiles = Profiles()
  let tap = Tap()
  var server: SocketServer?
  var connections: [Connection] = []
  var playerOwner: Connection?
  var sessions = Set<String>()
  var scrollTimer: Timer?

  func applicationDidFinishLaunching(_ notification: Notification) {
    signal(SIGPIPE, SIG_IGN)
    NSApp.setActivationPolicy(.accessory)
    try? SMAppService.mainApp.register()

    tap.switcher = switcher
    tap.useSwitcher = { [weak self] in
      guard let self else { return false }
      switcher.frontWindow = frontConnection?.front?.id ?? -1
      return !connections.isEmpty && switcher.inFront.count > 1
    }
    switcher.onActivate = { [weak self] id in
      guard let self else { return }
      send(["activate": id], to: connections.first { c in c.tabs.contains { $0.id == id } } ?? frontConnection)
    }
    player.onAction = { [weak self] action in self?.send(["player": ["action": action]], to: self?.playerOwner) }
    minis.onAction = { [weak self] action in
      guard let self else { return }
      let window = action["window"] as? Int
      send(["mini": action], to: connections.first { c in c.minis.contains { $0.id == window } } ?? frontConnection)
    }
    tap.onScroll = { [weak self] in
      guard let self else { return }
      scrollTimer?.invalidate()
      scrollTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in self?.send(["scrolled": true], to: self?.frontConnection) }
    }
    tap.onAltCommandClick = { [weak self] in self?.send(["miniNext": true], to: self?.frontConnection) }
    tap.onMouse = { [weak self] down in self?.minis.mouseDown = down }
    tap.onCommandL = { [weak self] in
      guard let self, let front = minis.frontWindow else { return false }
      minis.showAddress(front.id)
      return true
    }
    tap.onNewMiniBrowser = { [weak self] in
      guard let self, let front = frontConnection else { return false }
      send(["miniNew": true], to: front)
      return true
    }
    tap.onMiniBrowserOpen = { [weak self] pick in
      guard let self, !connections.isEmpty, let front = minis.frontWindow else { return false }
      if pick { minis.showMenu(front.id) } else { minis.onAction(["window": front.id, "action": "open"]) }
      return true
    }
    tap.onProfile = { [weak self] step, index in
      guard let self else { return }
      if let index { profiles.go(to: index) } else { profiles.cycle(step) }
    }
    Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.minis.follow() }

    server = SocketServer(path: Socket.path, queue: .main)
    if server == nil { log.error("socket: could not listen at \(Socket.path, privacy: .public)") }
    server?.onConnection = { [weak self] peer in
      guard let self else { return }
      let connection = Connection(peer: peer)
      connections.append(connection)
      log.info("host: connected (\(self.connections.count))")
      peer.onLine = { [weak self, weak connection] line in
        guard let connection, let message = JSONLine.decode(line) else { return }
        self?.receive(message, from: connection)
      }
      peer.onClose = { [weak self, weak connection] in
        guard let self, let connection else { return }
        connections.removeAll { $0 === connection }
        log.info("host: disconnected (\(self.connections.count) left)")
        if playerOwner === connection { playerOwner = nil; player.apply(nil) }
        merge()
      }
    }

    whenTrusted { [weak self] in
      let installed = self?.tap.install() ?? false
      log.info("tap: \(installed ? "installed" : "could not be created", privacy: .public)")
    }
    if Chrome.running == nil { Chrome.open(activate: false) } else { Chrome.warnIfStartedWithoutFlags() }
  }

  // The Dock icon (and the login item, on a Mac where the app was already running).
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
    Chrome.open(activate: true)
    Chrome.warnIfStartedWithoutFlags()
    return false
  }

  // Links from other apps, as the default browser: to the profile whose window is in front.
  func application(_ application: NSApplication, open urls: [URL]) {
    let web = urls.filter { ["http", "https"].contains($0.scheme?.lowercased()) }
    guard !web.isEmpty else { return }
    if let front = frontConnection {
      for url in web { send(["open": url.absoluteString], to: front) }
      Chrome.running?.activate()
    } else {
      Chrome.open(web, activate: true)
    }
  }

  // The connection whose reported front window is the Chrome window in front on screen; failing a
  // match, the first one.
  var frontConnection: Connection? {
    guard let front = Chrome.windows().first else { return connections.first }
    let near = { (a: CGFloat, b: CGFloat) in abs(a - b) < 2 }
    return connections.first { c in
      guard let f = c.front?.frame else { return false }
      return (near(f.width, front.frame.width) && near(f.height, front.frame.height)) || (near(f.minX, front.frame.minX) && near(f.minY, front.frame.minY))
    } ?? connections.first
  }

  func send(_ message: [String: Any], to connection: Connection?) {
    guard let connection, let line = JSONLine.encode(message) else { return }
    connection.peer.send(line)
  }

  func receive(_ message: [String: Any], from connection: Connection) {
    if let hello = message["hello"] as? [String: Any], let session = hello["session"] as? String, !sessions.contains(session) {
      // A session id this app hasn't seen: Chrome restarted, and tab ids with it.
      if !sessions.isEmpty { switcher.thumbs = [:] }
      sessions.insert(session)
    }
    if let mru = message["mru"] as? [[String: Any]] {
      log.info("mru: \(mru.count) tabs")
      connection.tabs = mru.compactMap { tab in
        guard let id = tab["id"] as? Int, let windowId = tab["windowId"] as? Int else { return nil }
        return TabInfo(id: id, windowId: windowId, title: tab["title"] as? String ?? "", favicon: image(tab["favicon"] as? String))
      }
      if let id = message["window"] as? Int, let frame = (message["front"] as? [String: Any]).flatMap(rect) { connection.front = (id, frame) }
      merge()
    }
    if let thumb = message["thumb"] as? [String: Any], let id = thumb["id"] as? Int, let image = image(thumb["data"] as? String) {
      log.info("thumb: tab \(id)")
      switcher.thumbs[id] = image
    }
    if let closed = message["closed"] as? Int { switcher.forget(tab: closed) }
    if let targets = message["targets"] as? [[String: Any]] {
      connection.targets = targets.compactMap { t -> Target? in
        guard let windowId = t["windowId"] as? Int else { return nil }
        let groups = (t["groups"] as? [[String: Any]] ?? []).compactMap { g -> (id: Int, title: String, color: String)? in
          guard let id = g["id"] as? Int else { return nil }
          return (id, g["title"] as? String ?? "", g["color"] as? String ?? "grey")
        }
        return Target(windowId: windowId, title: t["title"] as? String ?? "", groups: groups)
      }
    }
    if let minis = message["minis"] as? [[String: Any]] {
      log.info("minis: \(minis.count)")
      connection.minis = minis.compactMap { w -> MiniBrowser? in
        guard let id = w["id"] as? Int, let frame = rect(w) else { return nil }
        return MiniBrowser(id: id, frame: frame, url: w["url"] as? String ?? "", title: w["title"] as? String ?? "",
                           over: (w["over"] as? [String: Any]).flatMap(rect), targets: connection.targets)
      }
      merge()
    }
    if let shortcuts = message["shortcuts"] as? [String: String] {
      log.info("shortcuts: \(shortcuts.count)")
      minis.shortcuts = shortcuts
    }
    if let menu = message["miniMenu"] as? Int { minis.showMenu(menu) }
    if message.keys.contains("player") {
      let state = (message["player"] as? [String: Any]).flatMap { try? JSONSerialization.data(withJSONObject: $0) }
        .flatMap { try? JSONDecoder().decode(PlayerState.self, from: $0) }
      if state != nil { playerOwner = connection }
      if state != nil || playerOwner === connection { player.apply(state) }
    }
  }

  // The switcher and the bars see every profile's tabs and mini browsers together.
  func merge() {
    switcher.tabs = connections.flatMap(\.tabs)
    minis.windows = connections.flatMap(\.minis)
  }

  // Window bounds arrive as Chrome sends them: left, top, width, height.
  func rect(_ b: [String: Any]) -> CGRect? {
    guard let left = b["left"] as? Double, let top = b["top"] as? Double, let width = b["width"] as? Double, let height = b["height"] as? Double
    else { return nil }
    return CGRect(x: left, y: top, width: width, height: height)
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
