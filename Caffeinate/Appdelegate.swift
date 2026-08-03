//
//  Appdelegate.swift
//  Caffeinate
//
//  Created by sxwebdev.
//

import AppKit
import Foundation
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private static let inactiveSymbolName = "cup.and.saucer"

    private static var inactiveDescription: String {
        NSLocalizedString("Caffeinate is not active", comment: "Status item tooltip")
    }

    let config = ConfigHandler()
    let blocker = SleepBlocker()

    private var statusBarItem: NSStatusItem?
    private var expiryTimer: Timer?
    private var aboutWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        // We drive every item's enabled state ourselves; AppKit's automatic handling
        // would re-enable the section headers and the macOS 12 login-item row.
        menu.autoenablesItems = false
        // Assigning a menu makes both mouse buttons open it, which is what we want.
        item.menu = menu
        statusBarItem = item

        if config.activateOnLaunch {
            startBlocking()
        }
        refreshStatusItem()
    }

    func applicationWillTerminate(_ notification: Notification) {
        cancelExpiryTimer()
        blocker.deactivate()
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let active = blocker.isActive
        // A checkbox item: the title names the feature and the checkmark carries the
        // state. Pairing a checkmark with an imperative title like "Turn Off" mixes
        // two menu idioms and reads as a contradiction.
        menu.addItem(actionItem(
            title: NSLocalizedString("Keep the Mac awake", comment: "Main menu checkbox; the checkmark shows whether it is on"),
            action: #selector(toggleActive),
            state: active ? .on : .off
        ))

        if let remaining = blocker.remaining() {
            let format = NSLocalizedString("Turns off in %@", comment: "Countdown row; %@ is a duration like 14:58")
            menu.addItem(disabledItem(title: String(format: format, SleepBlocker.formatRemaining(remaining))))
        }

        menu.addItem(.separator())
        menu.addItem(submenuItem(title: NSLocalizedString("Mode", comment: "Submenu"), items: SleepMode.allCases.map { mode in
            actionItem(
                title: mode.title,
                action: #selector(selectMode(_:)),
                state: config.sleepMode == mode ? .on : .off,
                representedObject: mode
            )
        }))
        menu.addItem(submenuItem(
            title: NSLocalizedString("Turn Off After", comment: "Submenu"),
            items: delayItems()
        ))

        menu.addItem(.separator())
        menu.addItem(actionItem(
            title: NSLocalizedString("Activate on Launch", comment: "Menu toggle"),
            action: #selector(toggleActivateOnLaunch),
            state: config.activateOnLaunch ? .on : .off
        ))

        let loginItem = actionItem(
            title: NSLocalizedString("Start at Login", comment: "Menu toggle"),
            action: #selector(toggleAtLogin),
            state: config.atLogin ? .on : .off
        )
        if !config.isLoginItemSupported {
            loginItem.isEnabled = false
            loginItem.toolTip = NSLocalizedString(
                "Requires macOS 13 or later. Add the app to Login Items in System Settings instead.",
                comment: "Tooltip on the disabled login-item row"
            )
        }
        menu.addItem(loginItem)

        menu.addItem(.separator())
        menu.addItem(actionItem(
            title: NSLocalizedString("About Caffeinate…", comment: "Menu item"),
            action: #selector(showAbout)
        ))
        menu.addItem(actionItem(
            title: NSLocalizedString("Quit Caffeinate", comment: "Menu item"),
            action: #selector(quit),
            keyEquivalent: "q"
        ))
    }

    private func delayItems() -> [NSMenuItem] {
        let current = config.autoOffDelay
        var items = AutoOffDelay.presets.map { delay in
            actionItem(
                title: delay.title,
                action: #selector(selectDelay(_:)),
                state: current == delay ? .on : .off,
                representedObject: delay
            )
        }
        // A value the user typed is not in the presets, so give it its own row.
        // Without this the submenu would show no checkmark at all.
        if !AutoOffDelay.presets.contains(current) {
            items.append(.separator())
            items.append(actionItem(
                title: current.title,
                action: #selector(selectDelay(_:)),
                state: .on,
                representedObject: current
            ))
        }
        items.append(.separator())
        items.append(actionItem(
            title: NSLocalizedString("Custom…", comment: "Opens a prompt for a custom duration"),
            action: #selector(promptForCustomDelay)
        ))
        return items
    }

    private func actionItem(title: String,
                            action: Selector,
                            state: NSControl.StateValue = .off,
                            keyEquivalent: String = "",
                            representedObject: Any? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        item.state = state
        item.isEnabled = true
        item.representedObject = representedObject
        return item
    }

    private func disabledItem(title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func submenuItem(title: String, items: [NSMenuItem]) -> NSMenuItem {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        items.forEach(submenu.addItem)
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = true
        item.submenu = submenu
        return item
    }

    // MARK: - Actions

    @objc private func toggleActive() {
        if blocker.isActive {
            stopBlocking()
        } else {
            startBlocking()
        }
    }

    @objc private func selectMode(_ sender: NSMenuItem) {
        guard let mode = sender.representedObject as? SleepMode else { return }
        config.sleepMode = mode
        restartIfActive()
    }

    @objc private func selectDelay(_ sender: NSMenuItem) {
        guard let delay = sender.representedObject as? AutoOffDelay else { return }
        config.autoOffDelay = delay
        restartIfActive()
    }

    @objc private func promptForCustomDelay() {
        // LSUIElement apps are never activated implicitly, so without this the
        // sheet would come up behind whatever the user was working in.
        NSApp.activate(ignoringOtherApps: true)

        let formatter = NumberFormatter()
        formatter.allowsFloats = false
        formatter.minimum = 1
        formatter.maximum = NSNumber(value: AutoOffDelay.maxMinutes)

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.formatter = formatter
        field.placeholderString = "30"
        if !config.autoOffDelay.isNever {
            field.stringValue = String(config.autoOffDelay.minutes)
        }

        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Turn off after", comment: "Custom duration prompt title")
        alert.informativeText = String(
            format: NSLocalizedString(
                "Enter a number of minutes between 1 and %d.",
                comment: "Custom duration prompt; %d is the largest accepted value"
            ),
            AutoOffDelay.maxMinutes
        )
        alert.addButton(withTitle: NSLocalizedString("Set", comment: "Confirms the custom duration"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Dismisses the custom duration prompt"))
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        // Parse through the formatter first so locales with their own digits
        // (Arabic-Indic, for instance) are read correctly.
        let entered = formatter.number(from: field.stringValue)?.intValue ?? Int(field.stringValue)
        guard let minutes = entered, minutes > 0 else { return }
        config.autoOffDelay = AutoOffDelay(minutes: minutes)
        restartIfActive()
    }

    @objc private func toggleActivateOnLaunch() {
        config.activateOnLaunch.toggle()
    }

    @objc private func toggleAtLogin() {
        // The menu re-reads the real state the next time it opens, so a failed
        // register or unregister cannot leave a stale checkmark behind.
        config.setAtLogin(!config.atLogin)
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = aboutWindow {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            return
        }
        aboutWindow = About().openNewWindow(
            title: NSLocalizedString("About Caffeinate", comment: "About window title"),
            size: About.windowSize,
            identifier: "About"
        )
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Blocking

    private func startBlocking() {
        blocker.activate(mode: config.sleepMode, delay: config.autoOffDelay)
        scheduleExpiryTimer()
        refreshStatusItem()
    }

    private func stopBlocking() {
        cancelExpiryTimer()
        blocker.deactivate()
        refreshStatusItem()
    }

    /// A mode or delay change has to rebuild the live assertion, otherwise it would
    /// only take effect the next time Caffeinate is switched on.
    private func restartIfActive() {
        guard blocker.isActive else {
            refreshStatusItem()
            return
        }
        blocker.deactivate()
        blocker.activate(mode: config.sleepMode, delay: config.autoOffDelay)
        scheduleExpiryTimer()
        refreshStatusItem()
    }

    /// The kernel releases the assertion on its own; this timer exists only to catch
    /// the icon up. Firing a second late guarantees the kernel went first.
    private func scheduleExpiryTimer() {
        cancelExpiryTimer()
        guard let remaining = blocker.remaining() else { return }
        expiryTimer = Timer.scheduledTimer(withTimeInterval: remaining + 1, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.expiryTimer = nil
            self.blocker.handleExpiry()
            self.refreshStatusItem()
        }
    }

    private func cancelExpiryTimer() {
        expiryTimer?.invalidate()
        expiryTimer = nil
    }

    // MARK: - Status item

    private func refreshStatusItem() {
        let active = blocker.isActive
        let mode = blocker.mode ?? config.sleepMode
        let description = active ? mode.activeStatusDescription : Self.inactiveDescription
        let names = active ? mode.activeSymbolNames : [Self.inactiveSymbolName]
        statusBarItem?.button?.image = Self.symbolImage(names: names, description: description)
        statusBarItem?.button?.toolTip = description
    }

    /// Falls through the candidate list so a symbol introduced after macOS 11 can be
    /// preferred without breaking older systems.
    private static func symbolImage(names: [String], description: String) -> NSImage? {
        for name in names {
            if let image = NSImage(systemSymbolName: name, accessibilityDescription: description) {
                return image
            }
        }
        return nil
    }
}
