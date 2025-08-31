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
    @State private var htmlFiles = []

    var body: some View {
        VStack {
            Text("Narfle reader")
        }
        .onAppear {
            loadFile()
        }
    }

    private func loadFile() {
        // FIXME: this implementation is severely naive, there are a few security holes here
        // one of the most critical is directory traversal and hidden files
        // we could also check compression ratios for suspicious ones, to prevent decompression bombs
        // we could also have a timeout mechanism
        // we could also have checks for large epubs and have user approve if we detected large files
        //
        // What iOS Protects You From:
        // - Filesystem damage: App sandbox prevents writing outside your container
        // - System files: Can't access other apps or system directories
        // - Memory limits: iOS will terminate your app if it uses too much memory (better than system crash)
        //
        print("loading file: \(appState.selectedFile)")
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent("epub_structure_\(UUID().uuidString)")
        print("created sandbox dir: \(tempDir)")

        // extraction here
        do {
            let url = appState.selectedFile!
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }


            let data = try Data(contentsOf: url)
            
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
            // defer { try? fileManager.removeItem(at: tempDir) }

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

                let filename = String(data: filenameData, encoding: .utf8)
                print("filename: \(filename)")

                guard let filename = String(data: filenameData, encoding: .utf8),
                    !filename.isEmpty else {
                        offset = dataStart + compressedSize
                        continue
                    }
                
                // extracting actual compressed file content from the archive
                // zip files store multiple files concatenated together so we slice out
                // the content we are currently interested in
                // e.g. data.subdata(in: 1024..<1524)  // Extract bytes 1024-1524
                // ZIP File Structure:
                //  [Header][File1 Header][File1 Data][File2 Header][File2 Data][File3 Header][File3 Data]
                //                        ^---------^
                //                  This is what subdata extracts
                //                  dataStart to dataStart + compressedSize
                let compressedData = data.subdata(in: dataStart..<dataStart + compressedSize)

                let fileUrl = tempDir.appendingPathComponent(filename)

                // a zip archive can have directories in order to preserve folder structure when extracting
                // so we need to account for those here
                if filename.hasSuffix("/") {
                    try FileManager.default.createDirectory(at: fileUrl, withIntermediateDirectories: true)
                } else {
                    // decompressing actual file content in the zip
                    let parentDir = fileUrl.deletingLastPathComponent()
                    try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

                    // actually attempt decompress
                    // FIXME: what are all of the possible compression methods?
                    // should support more here?
                    let decompressedData: Data
                    if compressionMethod == 0 {
                        decompressedData = compressedData
                    } else if compressionMethod == 8 {
                        decompressedData = try compressedData.withUnsafeBytes { bytes in
                            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: uncompressedSize)
                            defer {buffer.deallocate()}

                            // using apple's compression lib to decompress
                            let decompressedSize = compression_decode_buffer(
                                buffer, uncompressedSize,
                                bytes.bindMemory(to: UInt8.self).baseAddress!, compressedData.count,
                                nil, COMPRESSION_ZLIB
                            )

                            guard decompressedSize > 0 else {
                                throw NSError(domain: "ZIPError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Decompression failed"])
                            }

                            return Data(bytes: buffer, count: decompressedSize)
                        }

                    } else {
                        print("Unsupported compression method \(compressionMethod)")
                        decompressedData = compressedData
                    }

                    try decompressedData.write(to: fileUrl)
                }
                offset = dataStart + compressedSize
            }
            
        } catch {
            print("Error loading file: \(error)")
        }

        var htmlFiles: [String] = []

        func searchDirectory(_ dir: URL, relativePath: String = "") {
            do {
                print("checking contents")
                let contents = try fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey])
                print("got contents")
                
                for item in contents {
                    let resourceValues = try item.resourceValues(forKeys: [.isDirectoryKey])
                    let filename = item.lastPathComponent
                    let fullPath = relativePath.isEmpty ? filename : "\(relativePath)/\(filename)"
                    
                    if resourceValues.isDirectory == true {
                        searchDirectory(item, relativePath: fullPath)
                    } else {
                        let ext = item.pathExtension.lowercased()
                        if ext == "html" || ext == "xhtml" || ext == "htm" {
                            htmlFiles.append(fullPath)
                        }
                    }
                }
            } catch {
                print("Error reading directory: \(error)")
            }
        }

        func extractNumber(from filename: String) -> Int {
            let numbers = filename.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap { Int($0) }
            return numbers.first ?? 0
        }

        print("searching directory: \(tempDir)")
        searchDirectory(tempDir)
        self.htmlFiles = htmlFiles.sorted { a, b in
            let aNum = extractNumber(from: a)
            let bNum = extractNumber(from: b)
            return aNum < bNum
        }

        print("html files: \(self.htmlFiles)")
        // consider using Application Support directory or caches instead of temp directory
        // let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        // let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        // defer { try? fileManager.removeItem(at: tempDir) }

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

