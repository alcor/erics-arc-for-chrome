// The ⌃Tab switcher: a Liquid Glass panel over Chrome's front window with the recently used tabs, most
// recent first, a thumbnail each with its favicon, like ⌘Tab for tabs. ⌃Tab moves the highlight on,
// ⌃⇧Tab back, Esc cancels, and letting go of Control activates the highlighted tab. A quick ⌃Tab that
// lets go before the panel would appear just switches, so the panel only shows up when you hold.
//
// The extension owns the list (it has the events) and sends it over the bridge whenever it changes,
// with a thumbnail per tab captured the last time that tab was in front; this side only draws. Nothing
// switches live while you walk, only the pick does.
//
// The layout is Arc's switcher: a row of thumbnails, each with its favicon and title underneath, the
// highlighted one on a tinted well. The surface follows Quicksilver's: a borderless non-activating panel
// with no shadow of its own, larger than the card so SwiftUI's shadows have room, and the card as Liquid
// Glass on a continuous rounded shape with a hairline and two shadows.
import AppKit
import SwiftUI

struct TabInfo {
  let id: Int, windowId: Int, title: String
  let favicon: NSImage?
}

final class SwitcherModel: ObservableObject {
  @Published var walk: [TabInfo] = []
  @Published var thumbs: [Int: NSImage] = [:]
  @Published var index = 0
  @Published var offset = 0
  @Published var visible = Switcher.maxVisible

  var shown: ArraySlice<TabInfo> { walk[min(offset, walk.count)..<min(offset + visible, walk.count)] }
}

final class Switcher {
  static let thumb = CGSize(width: 224, height: 144), gap: CGFloat = 8, pad: CGFloat = 14, cardPad: CGFloat = 10
  static let labelHeight: CGFloat = 34, radius: CGFloat = 26, shadowRoom: CGFloat = 70
  static let showAfter = 0.15, maxVisible = 5

  var tabs: [TabInfo] = []
  var thumbs: [Int: NSImage] {
    get { model.thumbs }
    set { model.thumbs = newValue }
  }
  var onActivate: (Int) -> Void = { _ in }

  private let model = SwitcherModel()
  private let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                              backing: .buffered, defer: false)
  private let hosting: NSHostingView<SwitcherView>
  private var showTimer: Timer?

  var isWalking: Bool { !model.walk.isEmpty }

  init() {
    panel.level = .floating
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false // the card draws its own, inside the panel
    panel.hidesOnDeactivate = false
    panel.ignoresMouseEvents = true
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    hosting = NSHostingView(rootView: SwitcherView(model: model))
    panel.contentView = hosting
  }

  func step(back: Bool) {
    if model.walk.isEmpty {
      guard tabs.count > 1 else { return }
      model.walk = tabs
      model.index = 0
      model.offset = 0
      showTimer = Timer.scheduledTimer(withTimeInterval: Self.showAfter, repeats: false) { [weak self] _ in self?.show() }
    }
    model.index = (model.index + (back ? -1 : 1) + model.walk.count) % model.walk.count
    if panel.isVisible { place() }
  }

  func controlUp() {
    guard isWalking else { return }
    let pick = model.walk[model.index]
    hide()
    onActivate(pick.id)
  }

  func cancel() { hide() }

  func forget(tab id: Int) { model.thumbs[id] = nil }

  // --demo: the panel with sample tabs, to look at.
  func demo() {
    let colors: [NSColor] = [.systemBlue, .systemOrange, .systemGreen, .systemPink, .systemTeal, .systemIndigo, .systemBrown]
    tabs = ["Eric's Monochrome", "Liquid Glass | Apple Developer Documentation", "Inbox (3) - Gmail", "Figma", "Hacker News",
            "Chrome Extensions: chrome.tabs", "YouTube"].enumerated().map { i, title in
      let favicon = NSImage(size: NSSize(width: 32, height: 32), flipped: false) { rect in
        colors[i].setFill(); NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill(); return true
      }
      return TabInfo(id: i, windowId: 1, title: title, favicon: favicon)
    }
    for i in 0..<5 {
      model.thumbs[i] = NSImage(size: NSSize(width: 480, height: 300), flipped: false) { rect in
        NSGradient(starting: colors[i].blended(withFraction: 0.7, of: .white)!, ending: .white)!.draw(in: rect, angle: -70)
        NSColor.black.withAlphaComponent(0.12).setFill()
        for row in 0..<7 { NSRect(x: 30, y: 250 - CGFloat(row) * 34, width: CGFloat(260 + row * 23 % 170), height: 12).fill() }
        return true
      }
    }
    step(back: false)
    step(back: false)
    // The panel's screen rectangle, top-left origin, for screencapture -R.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
      let f = panel.frame, top = (NSScreen.screens.first?.frame.height ?? 0) - f.maxY
      FileHandle.standardError.write(Data("panel \(Int(f.minX)),\(Int(top)),\(Int(f.width)),\(Int(f.height))\n".utf8))
    }
  }

  private func show() {
    guard isWalking else { return }
    place()
    panel.orderFrontRegardless()
  }

  private func hide() {
    showTimer?.invalidate()
    showTimer = nil
    model.walk = []
    panel.orderOut(nil)
  }

  static func cardSize(count: Int) -> CGSize {
    CGSize(width: CGFloat(count) * (thumb.width + 2 * cardPad) + CGFloat(count - 1) * gap + 2 * pad,
           height: thumb.height + labelHeight + 2 * cardPad + 2 * pad)
  }

  // Fits the visible run to the screen, keeps the highlight in it, and centers the card on Chrome's window.
  private func place() {
    let anchor = Chrome.frontWindowFrame
    let screen = anchor.flatMap { frame in NSScreen.screens.first { $0.frame.intersects(frame) } } ?? NSScreen.main
    let width = screen?.visibleFrame.width ?? 1200
    let fit = Int((width - 2 * Self.pad - 80 + Self.gap) / (Self.thumb.width + 2 * Self.cardPad + Self.gap))
    model.visible = max(2, min(Self.maxVisible, fit, model.walk.count))
    if model.index < model.offset { model.offset = model.index }
    if model.index >= model.offset + model.visible { model.offset = model.index - model.visible + 1 }

    let card = Self.cardSize(count: model.shown.count)
    let size = NSSize(width: card.width + 2 * Self.shadowRoom, height: card.height + 2 * Self.shadowRoom)
    let center = anchor.map { NSPoint(x: $0.midX, y: $0.midY) } ?? screen.map { NSPoint(x: $0.visibleFrame.midX, y: $0.visibleFrame.midY) } ?? .zero
    hosting.frame = NSRect(origin: .zero, size: size)
    panel.setFrame(NSRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height), display: true)
  }
}

struct SwitcherView: View {
  @ObservedObject var model: SwitcherModel
  @Environment(\.colorScheme) private var colorScheme
  private var isDark: Bool { colorScheme == .dark }

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: Switcher.radius, style: .continuous)
    let shown = Array(model.shown)
    HStack(spacing: Switcher.gap) {
      ForEach(Array(shown.enumerated()), id: \.element.id) { i, tab in
        TabCard(tab: tab, thumb: model.thumbs[tab.id], selected: model.offset + i == model.index)
      }
    }
    .padding(Switcher.pad)
    .background {
      ZStack {
        if #available(macOS 26, *) {
          shape.fill(.clear).glassEffect(.regular, in: shape)
        } else {
          shape.fill(.regularMaterial)
        }
        shape.strokeBorder(.white.opacity(isDark ? 0.14 : 0.3), lineWidth: 1.25)
      }
    }
    .clipShape(shape)
    .shadow(color: .black.opacity(0.28), radius: 36, y: 22)
    .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

}

// A thumbnail with its favicon and title underneath, as Arc lays them out; the highlighted one sits on a
// well of regular glass tinted with the accent color.
private struct TabCard: View {
  let tab: TabInfo
  let thumb: NSImage?
  let selected: Bool
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    let well = RoundedRectangle(cornerRadius: 18, style: .continuous)
    let frame = RoundedRectangle(cornerRadius: 10, style: .continuous)
    VStack(alignment: .leading, spacing: 8) {
      Group {
        if let thumb {
          Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fill)
        } else {
          ZStack {
            Color.primary.opacity(0.06)
            if let favicon = tab.favicon { Image(nsImage: favicon).resizable().frame(width: 40, height: 40) }
          }
        }
      }
      .frame(width: Switcher.thumb.width, height: Switcher.thumb.height, alignment: .top)
      .clipShape(frame)
      .overlay(frame.strokeBorder(.primary.opacity(0.12), lineWidth: 0.5))
      HStack(spacing: 8) {
        if let favicon = tab.favicon {
          Image(nsImage: favicon).resizable().frame(width: 22, height: 22)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        Text(tab.title)
          .font(.system(size: 15, weight: .medium))
          .lineLimit(1)
          .truncationMode(.tail)
      }
      .frame(width: Switcher.thumb.width, height: Switcher.labelHeight - 8, alignment: .leading)
    }
    .padding(Switcher.cardPad)
    .background {
      if selected {
        let tint = Color.accentColor.opacity(colorScheme == .dark ? 0.35 : 0.3)
        if #available(macOS 26, *) {
          well.fill(.clear).glassEffect(.regular.tint(tint), in: well)
        } else {
          well.fill(tint)
        }
      }
    }
  }
}
