//
//  Utility.swift
//  Caffeinate
//
//  Created by sxwebdev.
//

import SwiftUI

extension View {

    /// Hosts this view in a plain utility window. LSUIElement apps are never
    /// activated implicitly, so the caller is expected to activate the app first.
    func openNewWindow(title: String, size: CGSize, identifier: String) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.identifier = NSUserInterfaceItemIdentifier(identifier)
        // Keep the instance alive across closes so reopening reuses this window.
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: self)
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        return window
    }
}
