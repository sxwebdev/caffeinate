//
//  SleepBlockerTests.swift
//  CaffeinateTests
//
//  Created by sxwebdev.
//

import IOKit.pwr_mgt
import XCTest

/// Records what SleepBlocker asked IOKit to do and lets a test dictate the answers.
private final class FakeBackend: PowerAssertionBackend {
    var createResult: IOReturn = kIOReturnSuccess
    var idToHandOut: IOPMAssertionID = 42
    var releaseResult: IOReturn = kIOReturnSuccess

    private(set) var createdProperties: [[String: Any]] = []
    private(set) var releasedIDs: [IOPMAssertionID] = []

    func create(properties: [String: Any]) -> (result: IOReturn, id: IOPMAssertionID) {
        createdProperties.append(properties)
        return (createResult, createResult == kIOReturnSuccess ? idToHandOut : 0)
    }

    func release(id: IOPMAssertionID) -> IOReturn {
        releasedIDs.append(id)
        return releaseResult
    }
}

final class SleepBlockerTests: XCTestCase {

    private var backend: FakeBackend!
    private var clock: Date!
    private var blocker: SleepBlocker!

    override func setUp() {
        super.setUp()
        backend = FakeBackend()
        clock = Date(timeIntervalSince1970: 1_000_000)
        blocker = SleepBlocker(backend: backend, now: { self.clock })
    }

    // MARK: - Activation

    func testActivateRecordsAssertionOnSuccess() {
        backend.idToHandOut = 7

        XCTAssertTrue(blocker.activate(mode: .keepDisplayOn, delay: .never))

        XCTAssertTrue(blocker.isActive)
        XCTAssertEqual(blocker.assertion?.id, 7)
        XCTAssertEqual(blocker.mode, .keepDisplayOn)
        XCTAssertEqual(backend.createdProperties.count, 1)
    }

    /// Regression guard: an earlier version stored the failed result anyway, which
    /// made the guard in activate() reject every subsequent attempt forever.
    func testFailedActivationLeavesNoStateAndAllowsRetry() {
        backend.createResult = kIOReturnError

        XCTAssertFalse(blocker.activate(mode: .keepDisplayOn, delay: .never))
        XCTAssertFalse(blocker.isActive)
        XCTAssertNil(blocker.assertion)

        backend.createResult = kIOReturnSuccess
        XCTAssertTrue(blocker.activate(mode: .keepDisplayOn, delay: .never), "a retry after a failure must be able to succeed")
        XCTAssertTrue(blocker.isActive)
    }

    func testActivateWhileAlreadyActiveIsRejected() {
        XCTAssertTrue(blocker.activate(mode: .keepDisplayOn, delay: .never))

        XCTAssertFalse(blocker.activate(mode: .allowDisplaySleep, delay: AutoOffDelay(minutes: 60)))

        XCTAssertEqual(backend.createdProperties.count, 1, "must not create a second assertion")
        XCTAssertEqual(blocker.mode, .keepDisplayOn, "the original assertion stays untouched")
    }

    // MARK: - Deactivation

    func testDeactivateReleasesTheRecordedAssertion() {
        backend.idToHandOut = 99
        blocker.activate(mode: .keepDisplayOn, delay: .never)

        XCTAssertTrue(blocker.deactivate())

        XCTAssertEqual(backend.releasedIDs, [99])
        XCTAssertFalse(blocker.isActive)
        XCTAssertNil(blocker.assertion)
    }

    /// A release failure means the ID is already invalid, so keeping it would wedge
    /// the toggle in the active state with no way back.
    func testDeactivateClearsStateEvenWhenReleaseFails() {
        blocker.activate(mode: .keepDisplayOn, delay: .never)
        backend.releaseResult = kIOReturnError

        XCTAssertFalse(blocker.deactivate())

        XCTAssertFalse(blocker.isActive)
        XCTAssertNil(blocker.assertion)
    }

    func testDeactivateWhileInactiveDoesNothing() {
        XCTAssertFalse(blocker.deactivate())
        XCTAssertTrue(backend.releasedIDs.isEmpty)
    }

    // MARK: - Assertion properties

    func testPropertiesMapModeToAssertionType() {
        let displayOn = SleepBlocker.assertionProperties(mode: .keepDisplayOn, delay: .never)
        XCTAssertEqual(displayOn[kIOPMAssertionTypeKey] as? String, kIOPMAssertionTypePreventUserIdleDisplaySleep)

        let displaySleep = SleepBlocker.assertionProperties(mode: .allowDisplaySleep, delay: .never)
        XCTAssertEqual(displaySleep[kIOPMAssertionTypeKey] as? String, kIOPMAssertionTypePreventUserIdleSystemSleep)
    }

    func testPropertiesCarryNameAndLevel() {
        let properties = SleepBlocker.assertionProperties(mode: .keepDisplayOn, delay: .never)
        XCTAssertEqual(properties[kIOPMAssertionNameKey] as? String, SleepBlocker.assertionName)
        XCTAssertEqual(properties[kIOPMAssertionLevelKey] as? Int, Int(kIOPMAssertionLevelOn))
    }

    func testPropertiesOmitTimeoutWithoutDelay() {
        let properties = SleepBlocker.assertionProperties(mode: .keepDisplayOn, delay: .never)
        XCTAssertNil(properties[kIOPMAssertionTimeoutKey])
        XCTAssertNil(properties[kIOPMAssertionTimeoutActionKey])
    }

    /// The kernel owning the timeout is the whole point: it releases the assertion
    /// even if this process is wedged, so the keys have to actually be sent.
    func testPropertiesIncludeKernelTimeoutWithDelay() {
        let properties = SleepBlocker.assertionProperties(mode: .keepDisplayOn, delay: AutoOffDelay(minutes: 15))
        XCTAssertEqual(properties[kIOPMAssertionTimeoutKey] as? TimeInterval, 900)
        XCTAssertEqual(properties[kIOPMAssertionTimeoutActionKey] as? String, kIOPMAssertionTimeoutActionRelease)
    }

    // MARK: - Expiry

    func testExpiryIsDerivedFromTheInjectedClock() {
        blocker.activate(mode: .keepDisplayOn, delay: AutoOffDelay(minutes: 60))

        XCTAssertEqual(blocker.expiry, clock.addingTimeInterval(3600))
        XCTAssertEqual(blocker.remaining(), 3600)
    }

    func testNoExpiryWithoutDelay() {
        blocker.activate(mode: .keepDisplayOn, delay: .never)

        XCTAssertNil(blocker.expiry)
        XCTAssertNil(blocker.remaining())
    }

    func testRemainingCountsDownAndNeverGoesNegative() {
        blocker.activate(mode: .keepDisplayOn, delay: AutoOffDelay(minutes: 15))

        clock = clock.addingTimeInterval(600)
        XCTAssertEqual(blocker.remaining(), 300)

        clock = clock.addingTimeInterval(1_000)
        XCTAssertEqual(blocker.remaining(), 0, "an overdue assertion reports zero, not a negative value")
    }

    func testHandleExpiryReleasesAndClears() {
        backend.idToHandOut = 5
        blocker.activate(mode: .keepDisplayOn, delay: AutoOffDelay(minutes: 15))

        blocker.handleExpiry()

        XCTAssertEqual(backend.releasedIDs, [5], "release once more so an early call cannot leak the assertion")
        XCTAssertFalse(blocker.isActive)
    }

    func testHandleExpiryWhileInactiveDoesNothing() {
        blocker.handleExpiry()
        XCTAssertTrue(backend.releasedIDs.isEmpty)
    }

    // MARK: - Formatting

    func testFormatRemaining() {
        XCTAssertEqual(SleepBlocker.formatRemaining(0), "0:00")
        XCTAssertEqual(SleepBlocker.formatRemaining(9), "0:09")
        XCTAssertEqual(SleepBlocker.formatRemaining(59), "0:59")
        XCTAssertEqual(SleepBlocker.formatRemaining(60), "1:00")
        XCTAssertEqual(SleepBlocker.formatRemaining(900), "15:00")
        XCTAssertEqual(SleepBlocker.formatRemaining(3599), "59:59")
        XCTAssertEqual(SleepBlocker.formatRemaining(3600), "1:00:00")
        XCTAssertEqual(SleepBlocker.formatRemaining(7325), "2:02:05")
        XCTAssertEqual(SleepBlocker.formatRemaining(-10), "0:00", "a negative interval must not render as garbage")
    }

    // MARK: - Delay mapping

    func testAutoOffDelaySeconds() {
        XCTAssertNil(AutoOffDelay.never.seconds)
        XCTAssertTrue(AutoOffDelay.never.isNever)
        XCTAssertEqual(AutoOffDelay(minutes: 15).seconds, 900)
        XCTAssertEqual(AutoOffDelay(minutes: 30).seconds, 1_800)
        XCTAssertEqual(AutoOffDelay(minutes: 60).seconds, 3_600)
        XCTAssertEqual(AutoOffDelay(minutes: 120).seconds, 7_200)
        XCTAssertEqual(AutoOffDelay(minutes: 7).seconds, 420, "a custom value is not restricted to the presets")
    }

    /// A typed value or a stale preference must never reach the kernel unclamped.
    func testAutoOffDelayClampsOutOfRangeInput() {
        XCTAssertEqual(AutoOffDelay(minutes: -1).minutes, 0)
        XCTAssertEqual(AutoOffDelay(minutes: -10_000).minutes, 0)
        XCTAssertTrue(AutoOffDelay(minutes: -1).isNever)
        XCTAssertEqual(AutoOffDelay(minutes: 0).minutes, 0)
        XCTAssertEqual(AutoOffDelay(minutes: 1).minutes, 1)
        XCTAssertEqual(AutoOffDelay(minutes: AutoOffDelay.maxMinutes).minutes, AutoOffDelay.maxMinutes)
        XCTAssertEqual(AutoOffDelay(minutes: AutoOffDelay.maxMinutes + 1).minutes, AutoOffDelay.maxMinutes)
        XCTAssertEqual(AutoOffDelay(minutes: .max).minutes, AutoOffDelay.maxMinutes)
    }

    func testPresetsStartWithNeverAndAreUnique() {
        XCTAssertEqual(AutoOffDelay.presets.first, .never)
        XCTAssertEqual(Set(AutoOffDelay.presets).count, AutoOffDelay.presets.count)
        for preset in AutoOffDelay.presets {
            XCTAssertFalse(preset.title.isEmpty, "every preset needs a menu title")
        }
    }

    /// Durations are rendered by DateComponentsFormatter, so the only thing we can
    /// assert language-independently is that a real duration is produced and that
    /// distinct lengths do not collapse onto the same label.
    func testCustomDurationsProduceDistinctNonEmptyTitles() {
        let titles = [7, 15, 45, 60, 90, 120, AutoOffDelay.maxMinutes].map { AutoOffDelay(minutes: $0).title }
        for title in titles {
            XCTAssertFalse(title.isEmpty)
        }
        XCTAssertEqual(Set(titles).count, titles.count)
        XCTAssertNotEqual(AutoOffDelay(minutes: 15).title, AutoOffDelay.never.title)
    }

    func testEveryModeHasATitleSymbolAndStableRawValue() {
        for mode in SleepMode.allCases {
            XCTAssertFalse(mode.title.isEmpty)
            XCTAssertFalse(mode.activeStatusDescription.isEmpty)
            XCTAssertFalse(mode.activeSymbolNames.isEmpty, "the status item needs at least one symbol candidate")
            XCTAssertEqual(SleepMode(rawValue: mode.rawValue), mode)
        }
        XCTAssertNotEqual(
            SleepMode.keepDisplayOn.assertionType,
            SleepMode.allowDisplaySleep.assertionType,
            "the two modes must ask the kernel for different things"
        )
    }
}
