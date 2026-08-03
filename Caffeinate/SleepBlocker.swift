//
//  SleepBlocker.swift
//  Caffeinate
//
//  Created by sxwebdev.
//

import Foundation
import IOKit.pwr_mgt
import os

/// The IOKit calls SleepBlocker needs, behind a seam so the state machine can be
/// tested without touching real power management.
protocol PowerAssertionBackend {
    func create(properties: [String: Any]) -> (result: IOReturn, id: IOPMAssertionID)
    func release(id: IOPMAssertionID) -> IOReturn
}

struct IOKitPowerAssertionBackend: PowerAssertionBackend {
    func create(properties: [String: Any]) -> (result: IOReturn, id: IOPMAssertionID) {
        var assertionID: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithProperties(properties as CFDictionary, &assertionID)
        return (result, assertionID)
    }

    func release(id: IOPMAssertionID) -> IOReturn {
        IOPMAssertionRelease(id)
    }
}

/// Owns the single power assertion. We are keeping the Mac awake exactly while
/// `isActive` is true, so there is no separate flag that could disagree with reality.
final class SleepBlocker {

    struct Assertion: Equatable {
        let id: IOPMAssertionID
        let mode: SleepMode
        /// When the kernel will release this assertion by itself, if a delay was set.
        let expiry: Date?
    }

    static let assertionName = "Caffeinate"

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "dev.sxwebdev.caffeinate",
        category: "power"
    )

    private let backend: PowerAssertionBackend
    private let now: () -> Date

    private(set) var assertion: Assertion?

    var isActive: Bool { assertion != nil }
    var mode: SleepMode? { assertion?.mode }
    var expiry: Date? { assertion?.expiry }

    init(backend: PowerAssertionBackend = IOKitPowerAssertionBackend(),
         now: @escaping () -> Date = Date.init) {
        self.backend = backend
        self.now = now
    }

    /// The property dictionary handed to IOKit. The kernel owns the timeout, which
    /// means the assertion is released even if this process wedges or is suspended.
    static func assertionProperties(mode: SleepMode, delay: AutoOffDelay) -> [String: Any] {
        var properties: [String: Any] = [
            kIOPMAssertionTypeKey: mode.assertionType,
            kIOPMAssertionNameKey: assertionName,
            kIOPMAssertionLevelKey: kIOPMAssertionLevelOn,
        ]
        if let seconds = delay.seconds {
            properties[kIOPMAssertionTimeoutKey] = seconds
            properties[kIOPMAssertionTimeoutActionKey] = kIOPMAssertionTimeoutActionRelease
        }
        return properties
    }

    @discardableResult
    func activate(mode: SleepMode, delay: AutoOffDelay) -> Bool {
        guard assertion == nil else { return false }
        let properties = Self.assertionProperties(mode: mode, delay: delay)
        let (result, id) = backend.create(properties: properties)
        // Only record the assertion when it was actually created, otherwise the
        // guard above would refuse every later attempt.
        guard result == kIOReturnSuccess else {
            Self.logger.error("Failed to create the power assertion: \(result)")
            return false
        }
        assertion = Assertion(
            id: id,
            mode: mode,
            expiry: delay.seconds.map { now().addingTimeInterval($0) }
        )
        return true
    }

    @discardableResult
    func deactivate() -> Bool {
        guard let assertion else { return false }
        let result = backend.release(id: assertion.id)
        // Drop the record either way: a release failure means this ID is no longer
        // valid, so keeping it would only wedge us in the active state forever.
        self.assertion = nil
        guard result == kIOReturnSuccess else {
            Self.logger.error("Failed to release the power assertion: \(result)")
            return false
        }
        return true
    }

    /// The kernel has almost certainly released the assertion already; release once
    /// more so a slightly early call cannot leak it, and drop our record either way.
    func handleExpiry() {
        guard let assertion else { return }
        _ = backend.release(id: assertion.id)
        self.assertion = nil
    }

    /// Seconds left before the kernel releases the assertion, if a delay is running.
    func remaining() -> TimeInterval? {
        guard let expiry = assertion?.expiry else { return nil }
        return max(0, expiry.timeIntervalSince(now()))
    }

    /// mm:ss under an hour, h:mm:ss above it.
    static func formatRemaining(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}
