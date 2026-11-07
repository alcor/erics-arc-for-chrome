// ⌃Tab, taken from the keyboard before Chrome sees it. Chrome won't let an extension bind Tab or tell
// it when Control is released, so this event tap does that part, only while Chrome is in front. The
// same tap sees what an extension can't without a script in every page: a scroll (the tab in front
// has changed, for its thumbnail), an ⌥⌘-click (a link to open as a mini browser: it becomes a ⌘-click,
// which Chrome opens as a background tab, and the extension is told that tab is a mini browser), and ⌘L
// in a mini browser (its address field is the helper's), and the mini browser shortcuts themselves: ⌥⇧N
// from any app for a new one, ⌘O and ⇧⌘O in one to open it in Chrome or pick where. Chrome can't
// pre-set those for the extension (a manifest suggests at most four keys and none global), so the
// helper takes them when it's connected and the extension's own shortcuts are the fallback. ⌃⌥→, ⌃⌥←
// and ⌃⌥1 to 9 switch Chrome profiles (Profiles.swift).
//
// With the extension connected, ⌃Tab and ⌃⇧Tab step through the switcher (Switcher.swift) and letting
// go of Control picks a tab; Chrome never sees the keystroke. Without it, the keys are rewritten to
// what the extension's own commands are bound to, the way the Karabiner rule used to: the first ⌃Tab
// since Control went down becomes ⌃. (recent-next), more ⌃Tabs while it's held become ⌃⇧.
// (recent-continue), and ⌃⇧Tab becomes ⌃, (recent-prev).
import AppKit

final class Tap {
  static var shared: Tap!
  static let tab: Int64 = 48, escape: Int64 = 53, left: Int64 = 123, right: Int64 = 124 // the same on every layout; letters and punctuation go through Keyboard
  static let qwertyPeriod: Int64 = 47, qwertyComma: Int64 = 43

  var useSwitcher: () -> Bool = { false }
  var onScroll: () -> Void = {}
  var onAltCommandClick: () -> Void = {}
  var onMouse: (Bool) -> Void = { _ in } // the button went down (true) or up
  var onCommandL: () -> Bool = { false } // true: taken
  var onNewMiniBrowser: () -> Bool = { false } // ⌥⇧N from any app
  var onMiniBrowserOpen: (Bool) -> Bool = { _ in false } // ⌘O (false) or ⇧⌘O (true) in a mini browser
  var onProfile: (Int, Int?) -> Void = { _, _ in } // ⌃⌥→ (+1) / ⌃⌥← (-1), or ⌃⌥1…9 as an index
  var switcher: Switcher!
  private var port: CFMachPort?
  private var walking = false // fallback: a ⌃Tab has been sent since Control went down

  func install() -> Bool {
    Tap.shared = self
    let mask = [CGEventType.keyDown, .flagsChanged, .scrollWheel, .leftMouseDown, .leftMouseUp].reduce(0) { $0 | (1 << $1.rawValue) }
    let callback: CGEventTapCallBack = { _, type, event, _ in Tap.shared.handle(type, event) }
    guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                       eventsOfInterest: CGEventMask(mask), callback: callback, userInfo: nil)
    else { return false }
    self.port = port
    CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, port, 0), .commonModes)
    CGEvent.tapEnable(tap: port, enable: true)
    return true
  }

  func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
    let pass = Unmanaged.passUnretained(event)
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      if let port { CGEvent.tapEnable(tap: port, enable: true) }
      return pass
    }
    let flags = event.flags
    let control = flags.contains(.maskControl), shift = flags.contains(.maskShift)
    let command = flags.contains(.maskCommand), option = flags.contains(.maskAlternate)
    if type == .scrollWheel {
      if Chrome.isFrontmost { onScroll() }
      return pass
    }
    if type == .leftMouseDown || type == .leftMouseUp {
      onMouse(type == .leftMouseDown)
      if Chrome.isFrontmost && option && command && !control && !shift {
        event.flags = flags.subtracting(.maskAlternate)
        if type == .leftMouseDown { onAltCommandClick() }
      }
      return pass
    }
    if type == .flagsChanged {
      if !control {
        walking = false
        switcher.controlUp()
      }
      return pass
    }
    guard type == .keyDown else { return pass }
    let key = event.getIntegerValueField(.keyboardEventKeycode)
    let typed = Keyboard.character(key)
    // ⌥⇧N anywhere: a new mini browser, the one shortcut that has to work from other apps.
    if typed == "n" && option && shift && !command && !control && onNewMiniBrowser() { return nil }
    guard Chrome.isFrontmost else { return pass }
    // ⌃⌥ with an arrow or a digit: profiles.
    if control && option && !command && !shift {
      if key == Tap.right { onProfile(1, nil); return nil }
      if key == Tap.left { onProfile(-1, nil); return nil }
      if let digit = Int(typed), (1...9).contains(digit) { onProfile(0, digit - 1); return nil }
    }
    if key == Tap.escape && switcher.isWalking {
      switcher.cancel()
      return nil
    }
    if typed == "l" && command && !control && !option && !shift && onCommandL() { return nil }
    if typed == "o" && command && !control && !option && onMiniBrowserOpen(shift) { return nil }
    guard key == Tap.tab, control, !flags.contains(.maskCommand), !flags.contains(.maskAlternate) else { return pass }
    log.info("ctrl-tab: shift=\(shift, privacy: .public) switcher=\(self.useSwitcher(), privacy: .public)")
    if useSwitcher() {
      switcher.step(back: shift)
      return nil
    }
    if shift {
      event.setIntegerValueField(.keyboardEventKeycode, value: Keyboard.code(for: ",", qwerty: Tap.qwertyComma))
      event.flags = .maskControl
    } else {
      event.setIntegerValueField(.keyboardEventKeycode, value: Keyboard.code(for: ".", qwerty: Tap.qwertyPeriod))
      event.flags = walking ? [.maskControl, .maskShift] : .maskControl
      walking = true
    }
    return pass
  }
}
