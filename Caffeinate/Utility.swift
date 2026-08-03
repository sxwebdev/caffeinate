//
//  Utility.swift
//  Caffeinate
//
//  Created by sxwebdev.
//

import SwiftUI

extension View {

    private func findWindowWithTag(identifier: String) -> NSWindow? {
        return NSApplication.shared.windows.filter({ $0.identifier?.rawValue == identifier }).first
    }

    func openNewWindowWithToolbar(title: String, rect: NSRect, style: NSWindow.StyleMask, identifier: String = "", toolbar: some View) -> NSWindow {
        if !identifier.isEmpty, let window = findWindowWithTag(identifier: identifier) {
            // LSUIElement apps are never activated implicitly, so an existing
            // window would otherwise come back unfocused behind the frontmost app.
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            return window
        }

        let titlebarAccessoryView = toolbar.padding(.top, -5).padding(.leading, -8)

        let accessoryHostingView = NSHostingView(rootView: titlebarAccessoryView)
        accessoryHostingView.frame.size = accessoryHostingView.fittingSize

        let titlebarAccessory = NSTitlebarAccessoryViewController()
        titlebarAccessory.view = accessoryHostingView

        let window = NSWindow(
            contentRect: rect,
            styleMask: style,
            backing: .buffered,
            defer: false)
        window.center()
        window.title = title
        window.isReleasedWhenClosed = false
        window.identifier = NSUserInterfaceItemIdentifier(identifier)

        window.addTitlebarAccessoryViewController(titlebarAccessory)
        window.toolbarStyle = .preference

        window.contentView = NSHostingView(rootView: self)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()

        return window
    }
}
