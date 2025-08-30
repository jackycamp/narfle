//
// AppView.swift
// 
// The higher-order manager of the app's state, view, and application logic.
//

import SwiftUI
import WebKit
import Foundation
import Compression
import UniformTypeIdentifiers

import SwiftSoup

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
    @EnvironmentObject var appState: AppState 

    var body: some View {
        VStack {
            Text("Narfle reader")
        }
        .onAppear {
            loadFile()
        }
    }

    private func loadFile() {
        print("loading file: \(appState.selectedFile)")

        do {
            let url = appState.selectedFile!
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }

            let fileManager = FileManager.default

            let data = try Data(contentsOf: url)
            let tempDir = fileManager.temporaryDirectory.appendingPathComponent("epub_structure_\(UUID().uuidString)")
            
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? fileManager.removeItem(at: tempDir) }

            print("data count: \(data.count)")

            let signature = readUInt32(data: data, at: 0)
            print("signature: \(signature)")

            if signature != 0x04034b50 {
                print("signatures don't match!")
            }

            var offset = 0

            while offset < data.count - 30 {
                let localSignature = readUInt32(data: data, at: offset)
                
                if localSignature != 0x04034b50 { break }

                let compressionMethod = readUInt16(data: data, at: offset + 8)
                print("compressionMethod: \(compressionMethod)")
                let compressedSize = Int(readUInt32(data: data, at: offset + 18))
                print("compressedSize: \(compressedSize)")
                let uncompressedSize = Int(readUInt32(data: data, at: offset + 22))
                print("uncompressedSize: \(uncompressedSize)")
                let filenameLength = Int(readUInt16(data: data, at: offset + 26))
                print("filenameLength: \(filenameLength)")
                let extraFieldLength = Int(readUInt16(data: data, at: offset + 28))
                print("extraFieldLength: \(extraFieldLength)")

                let filenameStart = offset + 30
                let dataStart = filenameStart + filenameLength + extraFieldLength


                let filenameData = data.subdata(in: filenameStart..<filenameStart + filenameLength)
                print("filenameData: \(filenameData)")


                offset = dataStart + compressedSize
            }

            
        } catch {
            print("Error loading file: \(error)")
            
        }
        return

    }

    private func readUInt16(data: Data, at offset: Int) -> UInt16 {
        guard offset + 2 <= data.count else { return 0 }
        return data.subdata(in: offset..<offset + 2).withUnsafeBytes { bytes in
            bytes.load(as: UInt16.self)
        }
    }
    
    private func readUInt32(data: Data, at offset: Int) -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        return data.subdata(in: offset..<offset + 4).withUnsafeBytes { bytes in
            bytes.load(as: UInt32.self)
        }
    }
}

