//
//  ConfigHandler.swift
//  Caffeinate
//
//  Created by sxwebdev.
//

import Foundation
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
        case .keepDisplayOn:
            return NSLocalizedString("Keep the display on", comment: "Sleep mode menu item")
        case .allowDisplaySleep:
            return NSLocalizedString("Let the display sleep", comment: "Sleep mode menu item")
        }
    }

    /// Shown as the status item tooltip while this mode is holding the Mac awake.
    /// Kept as one whole sentence per mode so translations are not forced to
    /// assemble a phrase out of fragments.
    var activeStatusDescription: String {
        switch self {
        case .keepDisplayOn:
            return NSLocalizedString("Caffeinate is active — the display stays on", comment: "Status item tooltip")
        case .allowDisplaySleep:
            return NSLocalizedString("Caffeinate is active — the system stays awake", comment: "Status item tooltip")
        }
    }

    var assertionType: String {
        switch self {
        case .keepDisplayOn: return kIOPMAssertionTypePreventUserIdleDisplaySleep
        case .allowDisplaySleep: return kIOPMAssertionTypePreventUserIdleSystemSleep
        }
    }

    /// Tried in order: the first name the running system knows wins. Lets us use
    /// newer symbols without breaking the macOS 11 deployment target.
    var activeSymbolNames: [String] {
        switch self {
        case .keepDisplayOn: return ["cup.and.saucer.fill"]
        case .allowDisplaySleep: return ["mug.fill", "moon.zzz.fill", "cup.and.saucer.fill"]
        }
    }
}

/// How long Caffeinate stays active before switching itself off, as a whole number
/// of minutes. Zero means no timer at all.
struct AutoOffDelay: Equatable, Hashable {
    static let maxMinutes = 24 * 60

    let minutes: Int

    /// Out-of-range input is clamped rather than rejected, so neither a stale
    /// preference nor a typed value can ask the kernel for a nonsense timeout.
    init(minutes: Int) {
        self.minutes = min(max(0, minutes), Self.maxMinutes)
    }

    static let never = AutoOffDelay(minutes: 0)

    static let presets: [AutoOffDelay] = [
        never,
        AutoOffDelay(minutes: 15),
        AutoOffDelay(minutes: 30),
        AutoOffDelay(minutes: 60),
        AutoOffDelay(minutes: 120),
    ]

    var isNever: Bool { minutes == 0 }

    var seconds: TimeInterval? { isNever ? nil : TimeInterval(minutes) * 60 }

    /// Durations come from DateComponentsFormatter rather than our own strings
    /// files: it already knows every language's plural rules, which is what makes
    /// an arbitrary user-entered number safe to display in any localization.
    var title: String {
        guard !isNever else {
            return NSLocalizedString("Indefinitely", comment: "Auto-off delay menu item")
        }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .full
        formatter.zeroFormattingBehavior = .dropAll
        return formatter.string(from: TimeInterval(minutes) * 60) ?? String(minutes)
    }
}

/// Preferences. Scalar values live in UserDefaults; the login item is owned by
/// SMAppService, so that one is read back from the system rather than stored.
final class ConfigHandler {

    private enum Key {
        static let sleepMode = "sleepMode"
        static let autoOffMinutes = "autoOffMinutes"
        static let activateOnLaunch = "activateOnLaunch"
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "dev.sxwebdev.caffeinate",
        category: "config"
    )

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var sleepMode: SleepMode {
        get {
            defaults.string(forKey: Key.sleepMode)
                .flatMap(SleepMode.init(rawValue:)) ?? .keepDisplayOn
        }
        set { defaults.set(newValue.rawValue, forKey: Key.sleepMode) }
    }

    /// integer(forKey:) yields 0 for a missing or non-numeric entry, so a corrupt
    /// preference degrades to "no timer" instead of failing.
    var autoOffDelay: AutoOffDelay {
        get { AutoOffDelay(minutes: defaults.integer(forKey: Key.autoOffMinutes)) }
        set { defaults.set(newValue.minutes, forKey: Key.autoOffMinutes) }
    }

    var activateOnLaunch: Bool {
        get { defaults.bool(forKey: Key.activateOnLaunch) }
        set { defaults.set(newValue, forKey: Key.activateOnLaunch) }
    }

    // MARK: - Login item

    var isLoginItemSupported: Bool {
        if #available(macOS 13.0, *) { return true }
        return false
    }

    var atLogin: Bool {
        guard #available(macOS 13.0, *) else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    /// Returns the state the system actually ended up in, so a failure cannot
    /// leave the menu claiming something untrue.
    @discardableResult
    func setAtLogin(_ enabled: Bool) -> Bool {
        guard #available(macOS 13.0, *) else { return false }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Self.logger.error("Failed to update the login item: \(error.localizedDescription, privacy: .public)")
        }
        return atLogin
    }
}
