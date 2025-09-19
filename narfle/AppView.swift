//
// AppView.swift
// 
// The higher-order manager of the app's state, view, and application logic.
//

import SwiftUI

class AppState: ObservableObject {
    @Published var selectedFile: URL?
    @Published var pages: [[ContentElement]] = []
}

struct AppView: View {
    @StateObject private var appState = AppState()

    var body: some View {
        Group {
            if let file = appState.selectedFile {
                ReaderView()
            } else {
                MainTabView()
            }
        }.environmentObject(appState)
    }

}

struct MainTabView: View {
    var body: some View {
        TabView {
            FooView()
                .tabItem { Label("Home", systemImage: "house")}

            LibraryView()
                .tabItem { Label("Library", systemImage: "books.vertical")}

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle")}
        }
    }
}

struct FooView: View {
    var body: some View {
        VStack {
            Text("Narfle")
                .font(.largeTitle)
                .fontWeight(.bold)
        }
    }
}


