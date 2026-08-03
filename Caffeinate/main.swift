//
//  main.swift
//  Caffeinate
//
//  Created by sxwebdev.
//

import AppKit

// `make uninstall` runs this before deleting the bundle: unregistering the login
// item is only possible from inside the app, so it has to happen while the app
// still exists. No run loop is needed, which keeps the call synchronous.
if CommandLine.arguments.contains("--unregister-login-item") {
    let outcome = ConfigHandler().setAtLogin(false)
    // Exit non-zero when the registration survived, so `make uninstall` can warn
    // instead of deleting the bundle and orphaning the Login Items entry.
    // `.unsupported` means macOS 11 or 12, where there is nothing to unregister.
    exit(outcome == .disabled || outcome == .unsupported ? 0 : 1)
}

// A plain AppKit entry point. The SwiftUI `App` this replaces needed a
// `Settings { EmptyView() }` scene to avoid spawning a window on launch, but that
// scene also installed a ⌘, command which opened an empty "Caffeinate Settings"
// window — left over after the settings UI moved into the status item menu.
let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
