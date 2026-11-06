// ⌃Tab, taken from the keyboard before Chrome sees it. Chrome won't let an extension bind Tab or tell
// it when Control is released, so this event tap does that part, only while Chrome is in front.
//
// With the extension connected, ⌃Tab and ⌃⇧Tab step through the switcher (Switcher.swift) and letting
// go of Control picks a tab; Chrome never sees the keystroke. Without it, the keys are rewritten to
// what the extension's own commands are bound to, the way the Karabiner rule used to: the first ⌃Tab
// since Control went down becomes ⌃. (recent-next), more ⌃Tabs while it's held become ⌃⇧.
// (recent-continue), and ⌃⇧Tab becomes ⌃, (recent-prev).
import AppKit

final class Tap {
  static var shared: Tap!
  static let tab: Int64 = 48, period: Int64 = 47, comma: Int64 = 43, escape: Int64 = 53

  var useSwitcher: () -> Bool = { false }
  var switcher: Switcher!
  private var port: CFMachPort?
  private var walking = false // fallback: a ⌃Tab has been sent since Control went down

  func install() -> Bool {
    Tap.shared = self
    let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
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
    if type == .flagsChanged {
      if !control {
        walking = false
        switcher.controlUp()
      }
      return pass
    }
    guard type == .keyDown, Chrome.isFrontmost else { return pass }
    let key = event.getIntegerValueField(.keyboardEventKeycode)
    if key == Tap.escape && switcher.isWalking {
      switcher.cancel()
      return nil
    }
    guard key == Tap.tab, control, !flags.contains(.maskCommand), !flags.contains(.maskAlternate) else { return pass }
    if useSwitcher() {
      switcher.step(back: shift)
      return nil
    }
    if shift {
      event.setIntegerValueField(.keyboardEventKeycode, value: Tap.comma)
      event.flags = .maskControl
    } else {
      event.setIntegerValueField(.keyboardEventKeycode, value: Tap.period)
      event.flags = walking ? [.maskControl, .maskShift] : .maskControl
      walking = true
    }
    return pass
  }
}
