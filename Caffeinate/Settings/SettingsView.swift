//
//  SettingsView.swift
//  Caffeinate
//
//  Created by sxwebdev.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var configHandler: ConfigHandler

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !configHandler.macOS13 {
                Text("Start at login is only available on macOS 13 and later. You can manually add the app to the login items in System Settings.")
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Picker("When active:", selection: $configHandler.sleepMode) {
                ForEach(SleepMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 320)
            Text(configHandler.sleepMode.explanation)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle("Start at login:", isOn: $configHandler.atLogin)
                .toggleStyle(.checkbox)
                .onChange(of: configHandler.atLogin) { _ in
                    configHandler.applyAtLogin()
                }
                .disabled(!configHandler.macOS13)
            Spacer(minLength: 0)
            Button("Quit") {
                configHandler.quitApp()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct Settings_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .environmentObject(ConfigHandler())
            .frame(width: SettingsTabView.windowSize.width, height: SettingsTabView.windowSize.height)
    }
}
