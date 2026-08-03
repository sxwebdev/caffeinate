//
//  Appdelegate.swift
//  Caffeinate
//
//  Created by sxwebdev.
//

import Foundation
import AppKit
import Combine
import IOKit.pwr_mgt
import SwiftUI
import os

class AppDelegate: NSObject, NSApplicationDelegate {
    private static let activeDescription = "Caffeinate is active"
    private static let inactiveDescription = "Caffeinate is not active"

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "dev.sxwebdev.caffeinate",
        category: "power"
    )

    var statusBarItem: NSStatusItem?
    var configHandler = ConfigHandler()

    // The single source of truth: we are caffeinated exactly while we hold a power assertion.
    private var noSleepAssertionID: IOPMAssertionID?
    private var hasCoffee: Bool { noSleepAssertionID != nil }
    private var sleepModeSink: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusBarItem?.button?.action = #selector(AppDelegate.statusItemClicked(_:))
        statusBarItem?.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        updateStatusItem()

        // Changing the mode mid-session has to swap the live assertion, otherwise
        // the setting would only take effect after the next toggle.
        sleepModeSink = configHandler.$sleepMode
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] mode in
                self?.reapplyAssertion(mode: mode)
            }
    }

    func applicationWillTerminate(_ notification: Notification) {
        _ = enableScreenSleep()
    }

    @objc func statusItemClicked(_ sender: Any?) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            openSettingsWindow()
        } else {
            toggleCoffee()
        }
    }

    private func openSettingsWindow() {
        let toolbar = Toolbar()
            .environmentObject(configHandler)
        _ = SettingsTabView()
            .environmentObject(configHandler)
            .openNewWindowWithToolbar(
                title: "Caffeinate",
                rect: NSRect(origin: .zero, size: SettingsTabView.windowSize),
                style: [.closable, .titled],
                identifier: "Settings",
                toolbar: toolbar
            )
    }

    private func toggleCoffee() {
        if hasCoffee {
            _ = enableScreenSleep()
        } else {
            _ = disableScreenSleep(mode: configHandler.sleepMode)
        }
        updateStatusItem()
    }

    private func reapplyAssertion(mode: SleepMode) {
        guard hasCoffee else { return }
        _ = enableScreenSleep()
        _ = disableScreenSleep(mode: mode)
        updateStatusItem()
    }

    private func updateStatusItem() {
        let active = hasCoffee
        let description = active ? Self.activeDescription : Self.inactiveDescription
        statusBarItem?.button?.image = NSImage(
            systemSymbolName: active ? "cup.and.saucer.fill" : "cup.and.saucer",
            accessibilityDescription: description
        )
        statusBarItem?.button?.toolTip = description
    }

    // https://stackoverflow.com/questions/37601453/using-swift-to-disable-sleep-screen-saver-for-osx

    func disableScreenSleep(mode: SleepMode, reason: String = "Caffeinate") -> Bool {
        guard noSleepAssertionID == nil else { return false }
        var assertionID: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            mode.assertionType,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &assertionID
        )
        // Only remember the assertion if it was actually created, otherwise the
        // guard above would block every later attempt.
        guard result == kIOReturnSuccess else {
            Self.logger.error("Failed to create the power assertion: \(result)")
            return false
        }
        noSleepAssertionID = assertionID
        return true
    }

    func enableScreenSleep() -> Bool {
        guard let assertionID = noSleepAssertionID else { return false }
        let result = IOPMAssertionRelease(assertionID)
        // Drop the ID either way: a release failure means this ID is no longer
        // valid, so holding on to it would only wedge the toggle in the on state.
        noSleepAssertionID = nil
        guard result == kIOReturnSuccess else {
            Self.logger.error("Failed to release the power assertion: \(result)")
            return false
        }
        return true
    }
}
