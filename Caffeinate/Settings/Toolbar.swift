//
//  Toolbar.swift
//  Caffeinate
//
//  Created by sxwebdev.
//

import SwiftUI

struct Toolbar: View {
    @EnvironmentObject private var configHandler: ConfigHandler

    var body: some View {
        Picker("", selection: $configHandler.currentTab) {
            ForEach(SettingsTab.allCases) { tab in
                Text(tab.title).tag(tab)
            }
        }
        .pickerStyle(SegmentedPickerStyle())
        .frame(width: 100)
    }
}

struct Toolbar_Previews: PreviewProvider {
    static var previews: some View {
        Toolbar()
            .environmentObject(ConfigHandler())
    }
}
