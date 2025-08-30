//
// AppView.swift
// 
// The higher-order manager of the app's state, view, and application logic.
//

import SwiftUI
import WebKit
import Foundation
import Compression

class AppState: ObservableObject {
    @Published var selectedFile: URL?
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
        }.environmentObject(appState) // inject state into environment
    }

}

struct MainTabView: View {
    var body: some View {
        TabView {
            FooView()
                .tabItem { Label("Home", systemImage: "house")}

            LibraryView()
                .tabItem { Label("Library", systemImage: "books.vertical")}

            FooView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle")}
        }
    }
}

struct LibraryView: View {
    @EnvironmentObject var appState: AppState 
    @State private var showFilePicker = false

    var body: some View {
        VStack {
            Text("Your Library")
                .font(.largeTitle)
                .fontWeight(.bold)

            Button(action: { showFilePicker = true }) {
                Label("Browse files", systemImage: "folder")
                    .font(.headline)
                    .padding()
                    .cornerRadius(10)
            }
        }
        .sheet(isPresented: $showFilePicker) {
            FilePicker { url in
                print("picked!")
                // TODO: once file is picked, need to process it, load it
                // and then redirect to ReaderView
                print("file picked: \(url)")
                // onFileSelected(url)
                appState.selectedFile = url
            }
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

struct ReaderView: View {
    var body: some View {
        VStack {
            Text("Narfle reader")
        }
    }
}

