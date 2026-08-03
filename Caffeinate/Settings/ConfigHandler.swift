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
    private let loginItem: LoginItemManaging

    init(defaults: UserDefaults = .standard, loginItem: LoginItemManaging = SystemLoginItem()) {
        self.defaults = defaults
        self.loginItem = loginItem
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

    /// What actually happened, so the caller can react instead of guessing.
    enum LoginItemOutcome: Equatable {
        case enabled
        case disabled
        /// Registration went through but the user has to approve it by hand.
        case needsApproval
        case failed
        case unsupported
    }

    /// Read this once and derive from it rather than calling the three helpers below in
    /// a row: every read is a synchronous round trip to launchd, and independent reads
    /// can disagree halfway through building a menu.
    var loginItemState: LoginItemState { loginItem.state }

    var isLoginItemSupported: Bool { loginItemState != .unsupported }

    /// Only `.enabled` really launches at login. `.requiresApproval` means the user
    /// switched it off in System Settings, so reporting it as on would be a lie.
    var atLogin: Bool { loginItemState == .enabled }

    /// Registered yet switched off by the user. The menu has to show this, otherwise
    /// clicking the row looks like it did nothing at all.
    var loginItemNeedsApproval: Bool { loginItemState == .requiresApproval }

    /// Flips the login item. The direction comes from whether it is registered at all,
    /// not from `atLogin`: `.requiresApproval` reports as not-on, so keying off that
    /// would only ever call register() and the state could never be cleared.
    @discardableResult
    func toggleAtLogin() -> LoginItemOutcome {
        setAtLogin(!loginItem.state.isRegistered)
    }

    /// Reports the state the system actually ended up in, so a failure or a pending
    /// approval cannot leave the menu claiming something untrue.
    @discardableResult
    func setAtLogin(_ enabled: Bool) -> LoginItemOutcome {
        guard loginItem.state != .unsupported else { return .unsupported }
        do {
            if enabled {
                try loginItem.register()
            } else {
                try loginItem.unregister()
            }
        } catch {
            Self.logger.error("Failed to update the login item: \(error.localizedDescription, privacy: .public)")
            // register() throws for an already-registered service, which is exactly the
            // awaiting-approval case. Reporting a blanket failure here would turn it
            // back into a silent no-op, so judge by the resulting state instead.
            return outcome(requested: enabled)
        }
        return outcome(requested: enabled)
    }

    /// The outcome depends on the direction asked for, not only on where we ended up:
    /// landing on `.requiresApproval` is progress for an enable request and a failure
    /// for a disable request.
    private func outcome(requested enabled: Bool) -> LoginItemOutcome {
        switch loginItem.state {
        case .unsupported: return .unsupported
        case .enabled: return enabled ? .enabled : .failed
        case .requiresApproval: return enabled ? .needsApproval : .failed
        case .notRegistered, .notFound: return enabled ? .failed : .disabled
        }
    }

    func openLoginItemSettings() {
        loginItem.openSystemSettings()
    }
}
