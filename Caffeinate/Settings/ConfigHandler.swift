//
//  ConfigHandler.swift
//  Caffeinate
//
//  Created by sxwebdev.
//

import Foundation
import Combine
import ServiceManagement
import AppKit
import IOKit.pwr_mgt
import os

/// What Caffeinate holds awake while it is active.
enum SleepMode: String, CaseIterable, Identifiable {
    /// caffeinate -d: the display stays lit, which transitively keeps the system up.
    case keepDisplayOn
    /// caffeinate -i: the display may switch off, the system keeps running.
    case allowDisplaySleep

    var id: String { rawValue }

    var title: String {
        switch self {
        case .keepDisplayOn: return "Keep the display on"
        case .allowDisplaySleep: return "Let the display sleep"
        }
    }

    var explanation: String {
        switch self {
        case .keepDisplayOn:
            return "The display stays lit. Keeping it on also keeps the system awake."
        case .allowDisplaySleep:
            return "The display switches off on its own while the system keeps running, so background work carries on."
        }
    }

    var assertionType: CFString {
        switch self {
        case .keepDisplayOn:
            return kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString
        case .allowDisplaySleep:
            return kIOPMAssertionTypePreventUserIdleSystemSleep as CFString
        }
    }
}

final class ConfigHandler: ObservableObject {

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "dev.sxwebdev.caffeinate",
        category: "login-item"
    )

    private static let sleepModeKey = "sleepMode"

    @Published var currentTab: SettingsTab = .settings

    /// Mirrors Login Items. SMAppService owns this state, so there is nothing to
    /// persist ourselves: the value is re-read from the system on every launch.
    @Published var atLogin: Bool

    /// One scalar preference, so UserDefaults rather than a config file of our own.
    /// didSet does not run during init, which is exactly what we want here.
    @Published var sleepMode: SleepMode {
        didSet {
            UserDefaults.standard.set(sleepMode.rawValue, forKey: Self.sleepModeKey)
        }
    }

    let macOS13: Bool

    init() {
        if #available(macOS 13.0, *) {
            macOS13 = true
        } else {
            macOS13 = false
        }
        atLogin = ConfigHandler.loginItemEnabled
        sleepMode = UserDefaults.standard.string(forKey: ConfigHandler.sleepModeKey)
            .flatMap(SleepMode.init(rawValue:)) ?? .keepDisplayOn
    }

    private static var loginItemEnabled: Bool {
        guard #available(macOS 13.0, *) else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    func applyAtLogin() {
        guard #available(macOS 13.0, *) else { return }
        do {
            if atLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Self.logger.error("Failed to update the login item: \(error.localizedDescription, privacy: .public)")
        }
        // Snap back to what the system actually reports so a failed register or
        // unregister cannot leave the checkbox claiming something untrue. This
        // settles after one extra pass: the corrected value already matches the
        // system, so the follow-up call finds nothing to change.
        let actual = ConfigHandler.loginItemEnabled
        if atLogin != actual {
            atLogin = actual
        }
    }

    func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
