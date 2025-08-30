import SwiftUI
import WebKit
import Foundation
import Compression
import UniformTypeIdentifiers

struct EPUBPageReader: UIViewRepresentable {
    let epubURL: URL
    let htmlFiles: [String]
    let currentPageIndex: Int
    
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        loadCurrentPage(into: webView)
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        // triggered when going to next or previous page
        loadCurrentPage(into: webView)
    }
    
    private func loadCurrentPage(into webView: WKWebView) {
        guard currentPageIndex < htmlFiles.count else {
            webView.loadHTMLString("<html><body><h1>Page not found</h1></body></html>", baseURL: nil)
            return
        }
        
        guard epubURL.startAccessingSecurityScopedResource() else {
            webView.loadHTMLString("<html><body><h1>Cannot access EPUB file</h1><p>Permission denied</p></body></html>", baseURL: nil)
            return
        }
        
        defer { epubURL.stopAccessingSecurityScopedResource() }
        
        do {
            let epubData = try Data(contentsOf: epubURL)
            
            if let extractedContent = extractSpecificHTMLContent(from: epubData, filename: htmlFiles[currentPageIndex]) {
                webView.loadHTMLString(extractedContent, baseURL: nil)
            } else {
                webView.loadHTMLString("<html><body><h1>Could not load page</h1><p>File: \(htmlFiles[currentPageIndex])</p></body></html>", baseURL: nil)
            }
            
        } catch {
            webView.loadHTMLString("<html><body><h1>Error loading page</h1><p>\(error.localizedDescription)</p></body></html>", baseURL: nil)
        }
    }
    
    private func extractSpecificHTMLContent(from data: Data, filename: String) -> String? {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("epub_page_\(UUID().uuidString)")
        
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }
            
            let archive = Archive(data: data)
            if archive.extractAll(to: tempDir) {
                if let htmlContent = findSpecificHTMLContent(in: tempDir, filename: filename) {
                    print("html content: \(htmlContent)")
                    return addBasicStyling(to: htmlContent)
                }
            }
            
        } catch {
            print("Error creating temp directory: \(error)")
        }
        
        return nil
    }
    
    private func findSpecificHTMLContent(in directory: URL, filename: String) -> String? {
        let fileManager = FileManager.default
        
        func searchDirectory(_ dir: URL) -> String? {
            do {
                let contents = try fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey])
                
                for item in contents {
                    let resourceValues = try item.resourceValues(forKeys: [.isDirectoryKey])
                    
                    if resourceValues.isDirectory == true {
                        if let content = searchDirectory(item) {
                            return content
                        }
                    } else {
                        if item.lastPathComponent == filename {
                            do {
                                return try String(contentsOf: item, encoding: .utf8)
                            } catch {
                                print("Error reading specific file \(filename): \(error)")
                            }
                        }
                    }
                }
            } catch {
                print("Error reading directory: \(error)")
            }
            
            return nil
        }
        
        return searchDirectory(directory)
    }
    
    private func addBasicStyling(to htmlContent: String) -> String {
        let css = """
        <style>
            body {
                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                line-height: 1.6;
                max-width: 800px;
                margin: 0 auto;
                padding: 20px;
                font-size: 16px;
                color: #333;
            }
            h1, h2, h3, h4, h5, h6 {
                color: #2c3e50;
                margin-top: 1.5em;
                margin-bottom: 0.5em;
            }
            p {
                margin-bottom: 1em;
                text-align: justify;
            }
            .chapter {
                margin-bottom: 2em;
            }
        </style>
        """
        
        if htmlContent.lowercased().contains("<head>") {
            return htmlContent.replacingOccurrences(of: "</head>", with: css + "</head>")
        } else {
            return "<html><head><meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">" + css + "</head><body>" + htmlContent + "</body></html>"
        }
    }
}

class Archive {
    private let data: Data
    
    init(data: Data) {
        self.data = data
    }
    
    func extractAll(to destination: URL) -> Bool {
        guard data.count >= 30 else { return false }
        
        let signature = readUInt32(at: 0)
        if signature != 0x04034b50 {
            return false
        }
        
        var offset = 0
        let dataCount = data.count
        
        while offset < dataCount - 30 {
            let localSignature = readUInt32(at: offset)
            
            if localSignature != 0x04034b50 { break }
            
            // reading zip file headers byte-by-byte
            let compressionMethod = readUInt16(at: offset + 8)
            let compressedSize = Int(readUInt32(at: offset + 18))
            let uncompressedSize = Int(readUInt32(at: offset + 22))
            let filenameLength = Int(readUInt16(at: offset + 26))
            let extraFieldLength = Int(readUInt16(at: offset + 28))
            
            let filenameStart = offset + 30
            let dataStart = filenameStart + filenameLength + extraFieldLength
            
            guard filenameStart + filenameLength <= dataCount,
                  dataStart + compressedSize <= dataCount else { break }
            
            let filenameData = data.subdata(in: filenameStart..<filenameStart + filenameLength)
            guard let filename = String(data: filenameData, encoding: .utf8),
                  !filename.isEmpty else {
                offset = dataStart + compressedSize
                continue
            }
            
            let compressedData = data.subdata(in: dataStart..<dataStart + compressedSize)
            let fileURL = destination.appendingPathComponent(filename)
            
            do {
                if filename.hasSuffix("/") {
                    try FileManager.default.createDirectory(at: fileURL, withIntermediateDirectories: true)
                } else {
                    let parentDir = fileURL.deletingLastPathComponent()
                    try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
                    
                    // attempts to detect compression type
                    let decompressedData: Data
                    if compressionMethod == 0 {
                        decompressedData = compressedData
                    } else if compressionMethod == 8 {
                        decompressedData = try decompressData(compressedData, expectedSize: uncompressedSize)
                    } else {
                        print("Unsupported compression method \(compressionMethod) for \(filename)")
                        decompressedData = compressedData
                    }
                    
                    try decompressedData.write(to: fileURL)
                }
            } catch {
                print("Error writing file \(filename): \(error)")
            }
            
            offset = dataStart + compressedSize
        }
        
        return true
    }
    
    private func decompressData(_ data: Data, expectedSize: Int) throws -> Data {
        return try data.withUnsafeBytes { bytes in
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: expectedSize)
            defer { buffer.deallocate() }
            
            // using apple's compression lib to decompress
            let decompressedSize = compression_decode_buffer(
                buffer, expectedSize,
                bytes.bindMemory(to: UInt8.self).baseAddress!, data.count,
                nil, COMPRESSION_ZLIB
            )
            
            guard decompressedSize > 0 else {
                throw NSError(domain: "ZIPError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Decompression failed"])
            }
            
            return Data(bytes: buffer, count: decompressedSize)
        }
    }
    
    private func readUInt16(at offset: Int) -> UInt16 {
        guard offset + 2 <= data.count else { return 0 }
        return data.subdata(in: offset..<offset + 2).withUnsafeBytes { bytes in
            bytes.load(as: UInt16.self)
        }
    }
    
    private func readUInt32(at offset: Int) -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        return data.subdata(in: offset..<offset + 4).withUnsafeBytes { bytes in
            bytes.load(as: UInt32.self)
        }
    }
}

struct EPUBReaderView: View {
    @State private var selectedEpubURL: URL?
    @State private var currentPageIndex = 0
    @State private var htmlFiles: [String] = []
    @State private var isLoading = false
    @State private var showingDocumentPicker = false
    
    var body: some View {
        NavigationView {
            VStack {
                if selectedEpubURL == nil {
                    // File selection screen
                    VStack(spacing: 20) {
                        Image(systemName: "book.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.blue)
                        
                        Text("Narfle")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Text("Select a file to start reading")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        
                        Button(action: {
                            showingDocumentPicker = true
                        }) {
                            Label("Browse files", systemImage: "folder")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.blue)
                                .cornerRadius(10)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                } else if isLoading {
                    ProgressView("Loading book...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        
                } else {
                    // Reading interface
                    EPUBPageReader(
                        epubURL: selectedEpubURL!,
                        htmlFiles: htmlFiles,
                        currentPageIndex: currentPageIndex
                    )
                    
                    HStack {
                        Button("Previous") {
                            if currentPageIndex > 0 {
                                currentPageIndex -= 1 // triggers EPUBReader.updateUIView
                            }
                        }
                        .disabled(currentPageIndex == 0)
                        
                        Spacer()
                        
                        Text("Page \(currentPageIndex + 1) of \(htmlFiles.count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Button("Next") {
                            if currentPageIndex < htmlFiles.count - 1 {
                                currentPageIndex += 1
                            }
                        }
                        .disabled(currentPageIndex >= htmlFiles.count - 1)
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .shadow(radius: 1)
                }
            }
            .navigationTitle("EPUB Reader")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if selectedEpubURL != nil {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("New Book") {
                            selectedEpubURL = nil
                            htmlFiles = []
                            currentPageIndex = 0
                        }
                    }
                }
            }
            .sheet(isPresented: $showingDocumentPicker) {
                DocumentPicker { url in
                    selectedEpubURL = url
                    loadBookStructure()
                }
            }
        }
    }
    
    private func loadBookStructure() {
        guard let url = selectedEpubURL else { return }
        
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let files = self.extractHTMLFileList(from: url)
            DispatchQueue.main.async {
                self.htmlFiles = files
                self.isLoading = false
            }
        }
    }
    
    private func extractHTMLFileList(from url: URL) -> [String] {
        // gets permission to read the file
        guard url.startAccessingSecurityScopedResource() else { return [] }

        // once this function exits, release this defer block executes
        // and here, it releases the file permissions. That way we avoid
        // leaking permissions and hitting system limits
        defer { url.stopAccessingSecurityScopedResource() }
        
        let fileManager = FileManager.default
        
        do {
            // FIXME: loads entire epub into memory
            let epubData = try Data(contentsOf: url)
            let tempDir = fileManager.temporaryDirectory.appendingPathComponent("epub_structure_\(UUID().uuidString)")
            
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? fileManager.removeItem(at: tempDir) }
            
            // decompresses all files
            let archive = Archive(data: epubData)
            if archive.extractAll(to: tempDir) {
                // locates all readable chapters
                return findAllHTMLFiles(in: tempDir)
            }
            
        } catch {
            print("Error loading book structure: \(error)")
        }
        
        return []
    }
    
    private func findAllHTMLFiles(in directory: URL) -> [String] {
        let fileManager = FileManager.default
        var htmlFiles: [String] = []
        
        func searchDirectory(_ dir: URL, relativePath: String = "") {
            do {
                let contents = try fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey])
                
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
        
        searchDirectory(directory)
        return htmlFiles.sorted { a, b in
            let aNum = extractNumber(from: a)
            let bNum = extractNumber(from: b)
            return aNum < bNum
        }
    }
    
    private func extractNumber(from filename: String) -> Int {
        let numbers = filename.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap { Int($0) }
        return numbers.first ?? 0
    }
}

struct DocumentPicker: UIViewControllerRepresentable {
    let onDocumentPicked: (URL) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [
            UTType(filenameExtension: "epub") ?? UTType.data
        ])
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onDocumentPicked: onDocumentPicked)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onDocumentPicked: (URL) -> Void
        
        init(onDocumentPicked: @escaping (URL) -> Void) {
            self.onDocumentPicked = onDocumentPicked
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onDocumentPicked(url)
        }
    }
}
