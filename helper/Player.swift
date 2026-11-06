// Sidebar mini player: a small floating panel over the bottom of Chrome's vertical tab sidebar showing
// what a music tab is playing, with previous, play/pause and next. Clicking the track goes to its tab;
// × hides it until you've been back to that tab. The extension (player.js) sends what to show over the
// bridge and gets the button presses back.
//
// Where the sidebar is: the extension sends the focused window's bounds and the sidebar's width; the
// panel sits on the frontmost on-screen Chrome window with the same size (so it follows while you drag)
// or the same corner (while you resize).
import AppKit

struct Bounds: Decodable { let left, top, width, height: Double }
struct PlayerState: Decodable {
  let show: Bool
  let title, artist, artwork: String?
  let playing: Bool?
  let sidebar: Double?
  let window: Bounds?
}

// Takes the first click even though the panel never becomes the active window.
final class Button: NSButton {
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
final class ClickArea: NSView {
  var onClick = {}
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  override func mouseDown(with event: NSEvent) { onClick() }
}

final class Player: NSObject {
  static let height: CGFloat = 84, inset: CGFloat = 8
  var onAction: (String) -> Void = { _ in }
  let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
  let card = NSVisualEffectView()
  let art = NSImageView()
  let title = NSTextField(labelWithString: "")
  let artist = NSTextField(labelWithString: "")
  var playButton: Button!
  var state: PlayerState?
  var artworkURL: String?

  override init() {
    super.init()
    panel.level = .floating
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.hidesOnDeactivate = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

    card.material = .hudWindow
    card.blendingMode = .behindWindow
    card.state = .active
    card.wantsLayer = true
    card.layer?.cornerRadius = 10
    card.layer?.masksToBounds = true
    panel.contentView = card

    art.imageScaling = .scaleProportionallyUpOrDown
    art.wantsLayer = true
    art.layer?.cornerRadius = 6
    art.layer?.masksToBounds = true
    title.font = .boldSystemFont(ofSize: 13)
    artist.font = .systemFont(ofSize: 11)
    artist.textColor = .secondaryLabelColor
    for label in [title, artist] {
      label.lineBreakMode = .byTruncatingTail
      label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal) // else long titles widen the panel
    }

    playButton = button("play.fill", "playpause")
    let controls = NSStackView(views: [button("backward.fill", "previoustrack"), playButton, button("forward.fill", "nexttrack")])
    controls.spacing = 28
    let close = button("xmark", "close", size: 9)
    close.contentTintColor = .secondaryLabelColor
    let track = ClickArea()
    track.onClick = { [weak self] in self?.onAction("focus") }

    for view in [art, title, artist, controls, track, close] as [NSView] {
      view.translatesAutoresizingMaskIntoConstraints = false
      card.addSubview(view)
    }
    NSLayoutConstraint.activate([
      art.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
      art.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
      art.widthAnchor.constraint(equalToConstant: 40),
      art.heightAnchor.constraint(equalToConstant: 40),
      title.leadingAnchor.constraint(equalTo: art.trailingAnchor, constant: 8),
      title.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -24),
      title.topAnchor.constraint(equalTo: art.topAnchor, constant: 3),
      artist.leadingAnchor.constraint(equalTo: title.leadingAnchor),
      artist.trailingAnchor.constraint(equalTo: title.trailingAnchor),
      artist.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 2),
      controls.centerXAnchor.constraint(equalTo: card.centerXAnchor),
      controls.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -8),
      track.leadingAnchor.constraint(equalTo: card.leadingAnchor),
      track.trailingAnchor.constraint(equalTo: card.trailingAnchor),
      track.topAnchor.constraint(equalTo: card.topAnchor),
      track.bottomAnchor.constraint(equalTo: art.bottomAnchor),
      close.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -8),
      close.topAnchor.constraint(equalTo: card.topAnchor, constant: 8),
    ])

    Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.follow() }
  }

  func button(_ symbol: String, _ action: String, size: CGFloat = 15) -> Button {
    let b = Button(title: "", target: self, action: #selector(pressed))
    b.identifier = NSUserInterfaceItemIdentifier(action)
    b.isBordered = false
    b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: action)?
      .withSymbolConfiguration(.init(pointSize: size, weight: .regular))
    b.contentTintColor = .labelColor
    return b
  }

  @objc func pressed(_ sender: Button) { onAction(sender.identifier!.rawValue) }

  func apply(_ s: PlayerState?) {
    state = s
    guard let s else { return follow() }
    title.stringValue = s.title ?? ""
    artist.stringValue = s.artist ?? ""
    let symbol = s.playing == true ? "pause.fill" : "play.fill"
    playButton.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "play/pause")?
      .withSymbolConfiguration(.init(pointSize: 15, weight: .regular))
    if s.artwork != artworkURL {
      artworkURL = s.artwork
      art.image = nil
      // Only web and inline images: the page picks this address, and this app isn't held to the page's limits.
      if let url = s.artwork.flatMap(URL.init(string:)), ["https", "data"].contains(url.scheme) {
        URLSession.shared.dataTask(with: url) { data, _, _ in
          DispatchQueue.main.async {
            if self.artworkURL == s.artwork, let data { self.art.image = NSImage(data: data) }
          }
        }.resume()
      }
    }
    follow()
  }

  // Keeps the panel on the bottom of the sidebar; hides it when Chrome isn't the app in front.
  func follow() {
    guard let s = state, s.show, let w = s.window, let sidebar = s.sidebar,
          let chrome = Chrome.running, Chrome.isFrontmost, let primary = NSScreen.screens.first
    else { return panel.orderOut(nil) }
    let sent = CGRect(x: w.left, y: w.top, width: w.width, height: w.height)
    let near = { (a: CGFloat, b: CGFloat) in abs(a - b) < 2 }
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    let frame = windows.lazy
      .filter { $0[kCGWindowOwnerPID as String] as? pid_t == chrome.processIdentifier && $0[kCGWindowLayer as String] as? Int == 0 }
      .compactMap { ($0[kCGWindowBounds as String] as? NSDictionary).flatMap { CGRect(dictionaryRepresentation: $0) } }
      .first { (near($0.width, sent.width) && near($0.height, sent.height)) || (near($0.minX, sent.minX) && near($0.minY, sent.minY)) }
    guard let frame else { return panel.orderOut(nil) } // minimized, or on another Space
    // Window bounds count down from the top of the main screen; AppKit counts up from its bottom.
    let rect = NSRect(x: frame.minX + Self.inset, y: primary.frame.height - frame.maxY + Self.inset,
                      width: sidebar - 2 * Self.inset, height: Self.height)
    if panel.frame != rect { panel.setFrame(rect, display: true) }
    if !panel.isVisible { panel.orderFrontRegardless() }
  }
}
