// The ⌃Tab switcher: a floating panel over Chrome's front window with the recently used tabs, most
// recent first, a thumbnail, favicon and title each, like ⌘Tab for tabs. ⌃Tab moves the highlight on,
// ⌃⇧Tab back, Esc cancels, and letting go of Control activates the highlighted tab. A quick ⌃Tab that
// lets go before the panel would appear just switches, so the panel only shows up when you hold.
//
// The extension owns the list (it has the events) and sends it over the bridge whenever it changes,
// with a thumbnail per tab captured the last time that tab was in front; this side only draws. Nothing
// switches live while you walk, only the pick does.
import AppKit

struct TabInfo {
  let id: Int, windowId: Int, title: String
  let favicon: NSImage?
}

final class Switcher {
  static let card = NSSize(width: 176, height: 110), gap: CGFloat = 12, pad: CGFloat = 16, titleHeight: CGFloat = 36
  static let showAfter = 0.15, maxVisible = 6

  var tabs: [TabInfo] = []
  var thumbs: [Int: NSImage] = [:]
  var onActivate: (Int) -> Void = { _ in }

  private let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
  private let backdrop = NSVisualEffectView()
  private var walk: [TabInfo] = []
  private var index = 0, offset = 0
  private var showTimer: Timer?

  var isWalking: Bool { !walk.isEmpty }

  init() {
    panel.level = .popUpMenu
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.hidesOnDeactivate = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    backdrop.material = .hudWindow
    backdrop.blendingMode = .behindWindow
    backdrop.state = .active
    backdrop.wantsLayer = true
    backdrop.layer?.cornerRadius = 14
    backdrop.layer?.masksToBounds = true
    panel.contentView = backdrop
  }

  func step(back: Bool) {
    if walk.isEmpty {
      guard tabs.count > 1 else { return }
      walk = tabs
      index = 0
      offset = 0
      showTimer = Timer.scheduledTimer(withTimeInterval: Self.showAfter, repeats: false) { [weak self] _ in self?.show() }
    }
    index = (index + (back ? -1 : 1) + walk.count) % walk.count
    if panel.isVisible { render() }
  }

  func controlUp() {
    guard isWalking else { return }
    let pick = walk[index]
    hide()
    onActivate(pick.id)
  }

  func cancel() { hide() }

  func forget(tab id: Int) { thumbs[id] = nil }

  private func show() {
    guard isWalking else { return }
    render()
    panel.orderFrontRegardless()
  }

  private func hide() {
    showTimer?.invalidate()
    showTimer = nil
    walk = []
    panel.orderOut(nil)
  }

  private func render() {
    let screen = Chrome.frontWindowFrame.flatMap { frame in NSScreen.screens.first { $0.frame.intersects(frame) } } ?? NSScreen.main
    let fit = Int(((screen?.visibleFrame.width ?? 1200) - 2 * Self.pad - 80 + Self.gap) / (Self.card.width + Self.gap))
    let visible = max(2, min(Self.maxVisible, fit, walk.count))
    if index < offset { offset = index }
    if index >= offset + visible { offset = index - visible + 1 }
    let shown = Array(walk[offset..<min(offset + visible, walk.count)])

    let width = CGFloat(shown.count) * Self.card.width + CGFloat(shown.count - 1) * Self.gap + 2 * Self.pad
    let height = Self.card.height + Self.titleHeight + 2 * Self.pad
    backdrop.subviews.forEach { $0.removeFromSuperview() }
    for (i, tab) in shown.enumerated() {
      let x = Self.pad + CGFloat(i) * (Self.card.width + Self.gap)
      backdrop.addSubview(cardView(tab, selected: offset + i == index, at: NSPoint(x: x, y: Self.pad)))
    }

    let anchor = Chrome.frontWindowFrame ?? screen?.visibleFrame ?? .zero
    let origin = NSPoint(x: anchor.midX - width / 2, y: anchor.midY - height / 2)
    panel.setFrame(NSRect(origin: origin, size: NSSize(width: width, height: height)), display: true)
  }

  private func cardView(_ tab: TabInfo, selected: Bool, at origin: NSPoint) -> NSView {
    let inset: CGFloat = 6
    let view = NSView(frame: NSRect(origin: NSPoint(x: origin.x - inset, y: origin.y - inset),
                                    size: NSSize(width: Self.card.width + 2 * inset, height: Self.card.height + Self.titleHeight + 2 * inset)))
    view.wantsLayer = true
    view.layer?.cornerRadius = 10
    if selected { view.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.35).cgColor }

    let thumb = NSImageView(frame: NSRect(x: inset, y: inset + Self.titleHeight, width: Self.card.width, height: Self.card.height))
    thumb.wantsLayer = true
    thumb.layer?.cornerRadius = 6
    thumb.layer?.masksToBounds = true
    thumb.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.5).cgColor
    thumb.imageScaling = .scaleProportionallyUpOrDown
    thumb.imageAlignment = .alignTop
    if let image = thumbs[tab.id] {
      thumb.image = image
    } else if let favicon = tab.favicon {
      let big = NSImageView(frame: NSRect(x: (Self.card.width - 32) / 2, y: (Self.card.height - 32) / 2, width: 32, height: 32))
      big.image = favicon
      big.imageScaling = .scaleProportionallyUpOrDown
      thumb.addSubview(big)
    }
    view.addSubview(thumb)

    let favicon = NSImageView(frame: NSRect(x: inset + 4, y: inset + 10, width: 16, height: 16))
    favicon.image = tab.favicon
    favicon.imageScaling = .scaleProportionallyUpOrDown
    view.addSubview(favicon)

    let title = NSTextField(labelWithString: tab.title)
    title.frame = NSRect(x: inset + 26, y: inset + 8, width: Self.card.width - 30, height: 20)
    title.font = .systemFont(ofSize: 12, weight: selected ? .semibold : .regular)
    title.lineBreakMode = .byTruncatingTail
    title.textColor = .labelColor
    view.addSubview(title)
    return view
  }
}
