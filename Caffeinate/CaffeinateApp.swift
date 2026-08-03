//
//  CaffeinateApp.swift
//  Caffeinate
//
//  Created by sxwebdev.
//

import SwiftUI

@main
struct CaffeinateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
        
    var body: some Scene {
        // This is done so no window is spawned on launch
        Settings{
            EmptyView()
        }
    }
}
