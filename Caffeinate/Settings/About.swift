//
//  About.swift
//  Caffeinate
//
//  Created by sxwebdev.
//

import AppKit
import SwiftUI

struct About: View {
    static let windowSize = CGSize(width: 420, height: 170)

    private static let projectURL = URL(string: "https://github.com/sxwebdev/caffeinate")!

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .accessibilityLabel(NSLocalizedString("Caffeinate app icon", comment: "Accessibility label"))

            VStack(alignment: .leading, spacing: 4) {
                // The app name is a proper noun, so it is deliberately not localized.
                Text(verbatim: "Caffeinate")
                    .font(.largeTitle)
                    .bold()
                    .padding(.bottom, 6)
                Text(String(format: NSLocalizedString("Version: %@", comment: "About window; %@ is a version number"), version))
                    .font(.subheadline)
                Text(NSLocalizedString("Author: sxwebdev", comment: "About window"))
                    .font(.subheadline)
                Link(NSLocalizedString("GitHub", comment: "About window link to the project page"), destination: Self.projectURL)
                    .font(.subheadline)
                    .padding(.top, 5)
            }
        }
        .padding(20)
        .frame(width: Self.windowSize.width, height: Self.windowSize.height, alignment: .topLeading)
    }
}

struct About_Previews: PreviewProvider {
    static var previews: some View {
        About()
    }
}
