//
//  ConfigHandlerTests.swift
//  CaffeinateTests
//
//  Created by sxwebdev.
//

import XCTest

/// Stands in for launchd so the login-item logic can be exercised without touching
/// the real background-task database.
private final class FakeLoginItem: LoginItemManaging {
    var state: LoginItemState = .notRegistered
    var registerError: Error?
    var unregisterError: Error?
    /// What `state` becomes after a successful register(). Lets a test model the case
    /// where registration succeeds but the user still has to approve the item.
    var stateAfterRegister: LoginItemState = .enabled
    /// Likewise for unregister(): the call can return cleanly while the system keeps
    /// reporting the item as registered.
    var stateAfterUnregister: LoginItemState = .notRegistered

    private(set) var registerCount = 0
    private(set) var unregisterCount = 0
    private(set) var openSystemSettingsCount = 0

    func register() throws {
        registerCount += 1
        if let registerError { throw registerError }
        state = stateAfterRegister
    }

    func unregister() throws {
        unregisterCount += 1
        if let unregisterError { throw unregisterError }
        state = stateAfterUnregister
    }

    func openSystemSettings() {
        openSystemSettingsCount += 1
    }
}

final class ConfigHandlerTests: XCTestCase {

    /// One fixed suite rather than a fresh UUID per test: this bundle is unsandboxed,
    /// so a new suite name each run would leave a plist behind in the developer's real
    /// ~/Library/Preferences, and nothing would ever clean them up.
    private static let suiteName = "dev.sxwebdev.caffeinate.tests"

    private static var suitePlistURL: URL? {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Preferences/\(suiteName).plist")
    }

    private var defaults: UserDefaults!
    private var loginItem: FakeLoginItem!
    private var config: ConfigHandler!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: Self.suiteName)
        // The suite outlives a single test method now, so start from a known state.
        defaults.removePersistentDomain(forName: Self.suiteName)
        loginItem = FakeLoginItem()
        config = ConfigHandler(defaults: defaults, loginItem: loginItem)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: Self.suiteName)
        // removePersistentDomain empties the domain but leaves the plist on disk, so
        // unlink it explicitly instead of littering the home directory.
        if let url = Self.suitePlistURL {
            try? FileManager.default.removeItem(at: url)
        }
        config = nil
        loginItem = nil
        defaults = nil
        super.tearDown()
    }

    // MARK: - Stored preferences

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

        let reopened = ConfigHandler(defaults: defaults, loginItem: loginItem)

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

    // MARK: - Login item state

    /// Only `.enabled` actually launches the app at login. Reporting any other state
    /// as "on" would put a checkmark on something that will not happen.
    func testAtLoginIsTrueOnlyWhenEnabled() {
        let expectations: [(LoginItemState, Bool)] = [
            (.enabled, true),
            (.requiresApproval, false),
            (.notRegistered, false),
            (.notFound, false),
            (.unsupported, false),
        ]
        for (state, expected) in expectations {
            loginItem.state = state
            XCTAssertEqual(config.atLogin, expected, "atLogin for \(state)")
        }
    }

    func testNeedsApprovalOnlyForRequiresApproval() {
        for state: LoginItemState in [.enabled, .notRegistered, .notFound, .unsupported] {
            loginItem.state = state
            XCTAssertFalse(config.loginItemNeedsApproval, "needsApproval for \(state)")
        }
        loginItem.state = .requiresApproval
        XCTAssertTrue(config.loginItemNeedsApproval)
    }

    func testSupportedUnlessUnsupported() {
        for state: LoginItemState in [.enabled, .requiresApproval, .notRegistered, .notFound] {
            loginItem.state = state
            XCTAssertTrue(config.isLoginItemSupported, "isLoginItemSupported for \(state)")
        }
        loginItem.state = .unsupported
        XCTAssertFalse(config.isLoginItemSupported)
    }

    // MARK: - Login item mutations

    func testEnablingRegistersExactlyOnce() {
        XCTAssertEqual(config.setAtLogin(true), .enabled)
        XCTAssertEqual(loginItem.registerCount, 1)
        XCTAssertEqual(loginItem.unregisterCount, 0, "enabling must not unregister")
        XCTAssertTrue(config.atLogin)
    }

    func testDisablingUnregistersExactlyOnce() {
        loginItem.state = .enabled

        XCTAssertEqual(config.setAtLogin(false), .disabled)
        XCTAssertEqual(loginItem.unregisterCount, 1)
        XCTAssertEqual(loginItem.registerCount, 0, "disabling must not register")
        XCTAssertFalse(config.atLogin)
    }

    /// The case that used to be a silent no-op: register() returns without throwing,
    /// but the user switched the item off in System Settings so it stays off.
    func testRegisteringIntoRequiresApprovalIsReportedNotSwallowed() {
        loginItem.stateAfterRegister = .requiresApproval

        XCTAssertEqual(config.setAtLogin(true), .needsApproval)
        XCTAssertEqual(loginItem.registerCount, 1)
        XCTAssertFalse(config.atLogin, "the item is registered but will not launch, so it is not on")
        XCTAssertTrue(config.loginItemNeedsApproval)
    }

    /// register() can succeed yet leave the item unregistered; that is a failure, not
    /// a success, and it must not be reported as enabled.
    func testRegisteringThatDoesNotTakeEffectIsAFailure() {
        loginItem.stateAfterRegister = .notRegistered

        XCTAssertEqual(config.setAtLogin(true), .failed)
        XCTAssertFalse(config.atLogin)
    }

    func testThrowingRegisterIsReportedAsFailure() {
        loginItem.registerError = LoginItemError.unsupported

        XCTAssertEqual(config.setAtLogin(true), .failed)
        XCTAssertEqual(loginItem.registerCount, 1)
        XCTAssertFalse(config.atLogin)
    }

    func testThrowingUnregisterIsReportedAsFailure() {
        loginItem.state = .enabled
        loginItem.unregisterError = LoginItemError.unsupported

        XCTAssertEqual(config.setAtLogin(false), .failed)
        XCTAssertTrue(config.atLogin, "a failed unregister leaves the item enabled")
    }

    func testUnsupportedSystemIsNeverTouched() {
        loginItem.state = .unsupported

        XCTAssertEqual(config.setAtLogin(true), .unsupported)
        XCTAssertEqual(loginItem.registerCount, 0, "macOS 11 and 12 have no SMAppService to call")
        XCTAssertEqual(loginItem.unregisterCount, 0)
    }

    func testOpenLoginItemSettingsIsForwarded() {
        config.openLoginItemSettings()
        XCTAssertEqual(loginItem.openSystemSettingsCount, 1)
    }

    // MARK: - Toggle direction

    func testIsRegisteredCoversExactlyTheRegisteredStates() {
        XCTAssertTrue(LoginItemState.enabled.isRegistered)
        XCTAssertTrue(LoginItemState.requiresApproval.isRegistered)
        XCTAssertFalse(LoginItemState.notRegistered.isRegistered)
        XCTAssertFalse(LoginItemState.notFound.isRegistered)
        XCTAssertFalse(LoginItemState.unsupported.isRegistered)
    }

    /// The bug this guards: taking the direction from `atLogin` made `.requiresApproval`
    /// impossible to clear, because that state reports as not-on, so every click called
    /// register() again and the row could never be un-dashed.
    func testTogglingAnAwaitingApprovalItemTurnsItOff() {
        loginItem.state = .requiresApproval

        XCTAssertEqual(config.toggleAtLogin(), .disabled)
        XCTAssertEqual(loginItem.unregisterCount, 1)
        XCTAssertEqual(loginItem.registerCount, 0, "it is already registered; registering again does nothing")
    }

    func testTogglingAnEnabledItemTurnsItOff() {
        loginItem.state = .enabled

        XCTAssertEqual(config.toggleAtLogin(), .disabled)
        XCTAssertEqual(loginItem.unregisterCount, 1)
        XCTAssertEqual(loginItem.registerCount, 0)
    }

    func testTogglingAnUnregisteredItemTurnsItOn() {
        loginItem.state = .notRegistered

        XCTAssertEqual(config.toggleAtLogin(), .enabled)
        XCTAssertEqual(loginItem.registerCount, 1)
        XCTAssertEqual(loginItem.unregisterCount, 0)
    }

    func testTogglingANotFoundItemTurnsItOn() {
        loginItem.state = .notFound

        config.toggleAtLogin()
        XCTAssertEqual(loginItem.registerCount, 1)
        XCTAssertEqual(loginItem.unregisterCount, 0)
    }

    // MARK: - Outcome depends on the requested direction

    /// Landing on `.requiresApproval` is progress when enabling and a failure when
    /// disabling. Reporting `.needsApproval` for a disable request used to pop System
    /// Settings open right after the user asked to turn the feature off.
    func testDisableLeftRegisteredIsAFailureNotAnApprovalPrompt() {
        loginItem.state = .enabled
        loginItem.stateAfterUnregister = .requiresApproval

        XCTAssertEqual(config.setAtLogin(false), .failed)
    }

    func testDisableLeftEnabledIsAFailure() {
        loginItem.state = .enabled
        loginItem.stateAfterUnregister = .enabled

        XCTAssertEqual(config.setAtLogin(false), .failed)
    }

    /// register() throws for an already-registered service. Reporting that as a blanket
    /// failure turned the awaiting-approval case back into a silent no-op.
    func testThrowingRegisterOnAnAwaitingApprovalItemStillReportsApproval() {
        loginItem.state = .requiresApproval
        loginItem.registerError = LoginItemError.unsupported

        XCTAssertEqual(config.setAtLogin(true), .needsApproval)
    }
}

/// Read-only checks against the real SMAppService adapter. Nothing here registers or
/// unregisters anything: a test must not touch the developer's actual Login Items.
final class SystemLoginItemTests: XCTestCase {

    func testStateIsUnsupportedExactlyBelowMacOS13() {
        let state = SystemLoginItem().state
        if #available(macOS 13.0, *) {
            XCTAssertNotEqual(state, .unsupported, "SMAppService exists here, so a real status must be mapped")
        } else {
            XCTAssertEqual(state, .unsupported)
        }
    }

    func testStateAgreesWithIsRegistered() {
        let state = SystemLoginItem().state
        XCTAssertEqual(state.isRegistered, state == .enabled || state == .requiresApproval)
    }

    func testMutatingThrowsWhereSMAppServiceIsMissing() throws {
        guard #unavailable(macOS 13.0) else {
            throw XCTSkip("SMAppService is available; calling register() would change the real Login Items")
        }
        XCTAssertThrowsError(try SystemLoginItem().register())
        XCTAssertThrowsError(try SystemLoginItem().unregister())
    }
}
