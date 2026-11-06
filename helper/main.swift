// Arc for Chrome.app: one binary, picked by argument.
//   (none)          the app: login item, Dock stand-in for Chrome, default browser, ⌃Tab tap, panels
//   --host          native messaging host, spawned by Chrome for the extension (Host.swift)
//   --make-default  ask macOS to make this the default browser (a system dialog), then quit
//   --unregister    remove the login item, then quit
//   --demo          show the ⌃Tab switcher with sample tabs, to look at it (nothing else runs); prints
//                   the panel's rectangle on stderr for screencapture -R
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
