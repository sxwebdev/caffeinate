//
//  SettingsTabView.swift
//  Caffeinate
//
//  Created by sxwebdev.
//

import SwiftUI

enum SettingsTab: Int, CaseIterable, Identifiable {
    case about
    case settings

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .about: return "About"
        case .settings: return "Settings"
        }
    }
}

struct SettingsTabView: View {
    /// Shared by the window, the hosting view and the previews so they cannot drift apart.
    static let windowSize = CGSize(width: 450, height: 220)

    @EnvironmentObject private var configHandler: ConfigHandler

    var body: some View {
        Group {
            switch configHandler.currentTab {
            case .about:
                About()
            case .settings:
                SettingsView()
            }
        }
        .padding(20)
        .frame(width: Self.windowSize.width, height: Self.windowSize.height, alignment: .topLeading)
    }
}

struct SettingsTabView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsTabView()
            .environmentObject(ConfigHandler())
    }
}
