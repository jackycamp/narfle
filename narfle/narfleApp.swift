//
//  narfleApp.swift
//  narfle
//
//  Created by jack on 8/30/25.
//

import SwiftUI
import SwiftData

@main
struct narfleApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [NarfBundle.self])
    }
}
