//
//  LoginItem.swift
//  Caffeinate
//
//  Created by sxwebdev.
//

import Foundation
import ServiceManagement
import os

/// SMAppService's status, reduced to the cases Caffeinate reacts to and with an
/// explicit `unsupported` for macOS 11 and 12 where the API does not exist.
enum LoginItemState: Equatable {
    case unsupported
    case notRegistered
    /// Registered with launchd, but switched off by the user in System Settings.
    /// Registration succeeds and throws nothing, yet the app will not launch.
    case requiresApproval
    case enabled
    case notFound

    /// Known to launchd, whether or not the user has approved it. Turning the item off
    /// has to be driven by this rather than by "is it enabled": `.requiresApproval` is
    /// registered but reports as not enabled, so keying off enabled-ness would make
    /// that state impossible to clear.
    var isRegistered: Bool {
        self == .enabled || self == .requiresApproval
    }
}

enum LoginItemError: Error {
    case unsupported
}

/// The launchd-backed login item behind a seam, so the surrounding logic can be
/// tested without touching the real background-task database.
protocol LoginItemManaging {
    var state: LoginItemState { get }
    func register() throws
    func unregister() throws
    func openSystemSettings()
}

struct SystemLoginItem: LoginItemManaging {

    var state: LoginItemState {
        guard #available(macOS 13.0, *) else { return .unsupported }
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notRegistered: return .notRegistered
        case .notFound: return .notFound
        @unknown default: return .notRegistered
        }
    }

    func register() throws {
        guard #available(macOS 13.0, *) else { throw LoginItemError.unsupported }
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        guard #available(macOS 13.0, *) else { throw LoginItemError.unsupported }
        try SMAppService.mainApp.unregister()
    }

    func openSystemSettings() {
        guard #available(macOS 13.0, *) else { return }
        SMAppService.openSystemSettingsLoginItems()
    }
}
