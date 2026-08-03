//
//  ConfigHandlerTests.swift
//  CaffeinateTests
//
//  Created by sxwebdev.
//

import XCTest

final class ConfigHandlerTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var config: ConfigHandler!

    override func setUp() {
        super.setUp()
        // A private suite per test so nothing leaks into the real preferences.
        suiteName = "dev.sxwebdev.caffeinate.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        config = ConfigHandler(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        config = nil
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaultsOnFirstLaunch() {
        XCTAssertEqual(config.sleepMode, .keepDisplayOn)
        XCTAssertEqual(config.autoOffDelay, .never)
        XCTAssertFalse(config.activateOnLaunch)
    }

    func testSleepModeRoundTrip() {
        config.sleepMode = .allowDisplaySleep
        XCTAssertEqual(config.sleepMode, .allowDisplaySleep)
        XCTAssertEqual(defaults.string(forKey: "sleepMode"), "allowDisplaySleep")
    }

    func testAutoOffDelayRoundTrip() {
        config.autoOffDelay = AutoOffDelay(minutes: 120)
        XCTAssertEqual(config.autoOffDelay, AutoOffDelay(minutes: 120))
        XCTAssertEqual(defaults.integer(forKey: "autoOffMinutes"), 120)
    }

    func testCustomAutoOffDelayRoundTrip() {
        config.autoOffDelay = AutoOffDelay(minutes: 7)
        XCTAssertEqual(config.autoOffDelay.minutes, 7, "a value that is not one of the presets must persist too")
    }

    func testStoredAutoOffMinutesAreClampedOnRead() {
        defaults.set(99_999, forKey: "autoOffMinutes")
        XCTAssertEqual(config.autoOffDelay.minutes, AutoOffDelay.maxMinutes)

        defaults.set(-5, forKey: "autoOffMinutes")
        XCTAssertTrue(config.autoOffDelay.isNever)
    }

    func testActivateOnLaunchRoundTrip() {
        config.activateOnLaunch = true
        XCTAssertTrue(config.activateOnLaunch)
        XCTAssertTrue(defaults.bool(forKey: "activateOnLaunch"))
    }

    /// Preferences outlive the app, so a fresh handler on the same store has to see
    /// what the previous one wrote.
    func testValuesSurviveANewHandler() {
        config.sleepMode = .allowDisplaySleep
        config.autoOffDelay = AutoOffDelay(minutes: 45)
        config.activateOnLaunch = true

        let reopened = ConfigHandler(defaults: defaults)

        XCTAssertEqual(reopened.sleepMode, .allowDisplaySleep)
        XCTAssertEqual(reopened.autoOffDelay, AutoOffDelay(minutes: 45))
        XCTAssertTrue(reopened.activateOnLaunch)
    }

    /// A value written by a newer build, or a hand-edited plist, must not crash or
    /// leave the app in an undefined mode.
    func testUnknownStoredValuesFallBackToDefaults() {
        defaults.set("teleportTheMac", forKey: "sleepMode")
        defaults.set("nextTuesday", forKey: "autoOffMinutes")

        XCTAssertEqual(config.sleepMode, .keepDisplayOn)
        XCTAssertEqual(config.autoOffDelay, .never)
    }

    func testWrongTypeStoredValuesFallBackToDefaults() {
        defaults.set(42, forKey: "sleepMode")
        defaults.set(["a", "b"], forKey: "autoOffMinutes")

        XCTAssertEqual(config.sleepMode, .keepDisplayOn)
        XCTAssertEqual(config.autoOffDelay, .never)
    }

    func testLoginItemSupportMatchesTheRunningOS() {
        if #available(macOS 13.0, *) {
            XCTAssertTrue(config.isLoginItemSupported)
        } else {
            XCTAssertFalse(config.isLoginItemSupported)
            XCTAssertFalse(config.atLogin, "without SMAppService the app can never be a login item")
        }
    }
}
