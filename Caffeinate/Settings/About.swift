//
//  About.swift
//  Caffeinate
//
//  Created by sxwebdev.
//

import AppKit
import SwiftUI

struct About: View {
    private static let profileURL = URL(string: "https://github.com/sxwebdev")!

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .accessibilityLabel("Caffeinate app icon")

            VStack(alignment: .leading, spacing: 4) {
                Text("Caffeinate")
                    .font(.largeTitle)
                    .bold()
                    .padding(.bottom, 6)
                Text("Version: \(version)")
                    .font(.subheadline)
                Text("Author: sxwebdev")
                    .font(.subheadline)
                Link("My GitHub", destination: Self.profileURL)
                    .font(.subheadline)
                    .padding(.top, 5)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct About_Previews: PreviewProvider {
    static var previews: some View {
        About()
            .frame(width: SettingsTabView.windowSize.width, height: SettingsTabView.windowSize.height)
    }
}
