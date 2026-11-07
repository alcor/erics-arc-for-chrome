// Monochrome.app: one binary, picked by argument.
//   (none)          the app: login item, Dock stand-in for Chrome, default browser, ⌃Tab tap, panels
//   --host          native messaging host, spawned by Chrome for the extension (Host.swift)
//   --make-default  ask macOS to make this the default browser (a system dialog), then quit
//   --unregister    remove the login item, then quit
//   --demo          show the ⌃Tab switcher with sample tabs, to look at it (nothing else runs); prints
//                   the panel's rectangle on stderr for screencapture -R
//   --demo-shade    the peek browser shade over Chrome's second window, ordered below its first; prints its rectangle
//   --demo-profiles the profile HUD on Chrome's real Profiles menu, nothing pressed; prints its rectangle
//   --status        the keycodes the current layout gives the shortcut keys, whether the app half is up and
//                   the extension's host is connected
// Log: log stream --info --predicate 'subsystem == "local.monochrome"' (Accessibility shows there; asking
// from a shell would report the terminal's grant, not the app's)
import AppKit
import ServiceManagement

switch CommandLine.arguments.dropFirst().first {
case "--host":
  Host.run()
case "--demo":
  let app = NSApplication.shared
  app.setActivationPolicy(.accessory)
  let switcher = Switcher()
  switcher.demo()
  app.run()
case "--demo-profiles":
  let app = NSApplication.shared
  app.setActivationPolicy(.accessory)
  let profiles = Profiles()
  profiles.demo()
  app.run()
case "--demo-shade":
  let app = NSApplication.shared
  app.setActivationPolicy(.accessory)
  let overlays = MiniBrowsers()
  overlays.demoShade()
  app.run()
case "--status":
  print("layout: n=\(Keyboard.code(for: "n", qwerty: 45)) o=\(Keyboard.code(for: "o", qwerty: 31)) l=\(Keyboard.code(for: "l", qwerty: 37)) .=\(Keyboard.code(for: ".", qwerty: 47)) ,=\(Keyboard.code(for: ",", qwerty: 43)) (keycodes under the current keyboard layout)")
  print("app:", NSRunningApplication.runningApplications(withBundleIdentifier: App.bundleId).isEmpty ? "not running" : "running")
  print("host:", Socket.connect(Socket.path).map { close($0); return "socket up" } ?? "socket down")
  exit(0)
case "--unregister":
  try? SMAppService.mainApp.unregister()
  exit(0)
case "--make-default":
  // Both schemes: the system's browser picker follows http, and https is where links actually go.
  let group = DispatchGroup()
  for scheme in ["http", "https"] {
    group.enter()
    NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: scheme) { _ in group.leave() }
  }
  group.notify(queue: .main) { exit(0) }
  RunLoop.main.run()
default:
  let app = NSApplication.shared
  let delegate = App()
  app.delegate = delegate
  app.run()
}
