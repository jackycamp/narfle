import SwiftUI
import WebKit
import Foundation
import Compression
import UniformTypeIdentifiers
import SwiftSoup

struct ReaderView: View {
    @EnvironmentObject var appState: AppState 
    @State private var dir: URL?
    @State private var htmlFiles: [String] = []
    @State private var pageIndex = 0 // FIXME: 
    @State private var isLoading = true
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        VStack {
            if isLoading {
                Text("Narfle reader (loading)")
            } else {
                // TabView to achieve swipe for page turning
                TabView(selection: $pageIndex) {
                    ForEach(Array(htmlFiles.enumerated()), id: \.offset) { index, file in
                        PageReaderView(filePath: file, baseDir: dir!)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                // PageReaderView(
                //     filePath: htmlFiles[pageIndex],
                //     baseDir: dir! // FIXME:
                // )
                // .id(htmlFiles[pageIndex])

                // HStack {
                //     Button("Previous") {
                //         if pageIndex > 0 {
                //             pageIndex -= 1
                //         }
                //     }
                //     .disabled(pageIndex == 0)
                //
                //     Spacer()
                //
                //     Text("Page \(pageIndex + 1)")
                //         .font(.caption)
                //         .foregroundColor(.secondary)
                //
                //     Spacer()
                //
                //     Button("Next") {
                //         pageIndex += 1
                //     }
                //     .disabled(pageIndex >= htmlFiles.count - 1)
                // }
                // .padding()
            }
        }
        .onAppear {
            loadFile()
        }
    }

    private func loadFile() {
        self.dir = EPUBArchive.extract(appState.selectedFile!)
        print("extracted file to \(self.dir)")
        self.htmlFiles = EPUBArchive.findHTMLFiles(self.dir!)
        print("found html files: \(self.htmlFiles)")
        self.isLoading = false

        // consider using Application Support directory or caches instead of temp directory
        // let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        // let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        // defer { try? fileManager.removeItem(at: tempDir) }

        return
    }

}

struct PageReaderView: View {
    let filePath: String
    let baseDir: URL

    @State private var parsedContent: [ContentElement] = []
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            if isLoading {
                Text("page loading")
            } else {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(parsedContent.enumerated()), id: \.offset) { index, element in
                        buildContentView(for: element)
                    }

                }
                .padding()
            }
        }
        .onAppear {
            loadPage()
        }
    }

    @ViewBuilder
    private func buildContentView(for element: ContentElement) -> some View {
        switch element {
        case .heading(let text):
            Text(text)
                .font(.title2)

        case .paragraph(let text):
            Text(text)
                .font(.body)
                .lineLimit(nil)
                .textSelection(.enabled)

        // case .emphasis(let text):
        //     Text(text)

        case .lineBreak:
            Spacer()
                .frame(height: 8)

        // FIXME: images aren't appearing
        case .image(let src, let alt):
            AsyncImage(url: imageURL(for: src)) { image in
                image
                .resizable()
                .aspectRatio(contentMode: .fit)
            } placeholder: {
                Rectangle()
                .fill(.gray.opacity(0.3))
                .frame(height: 200)
            }

        // case .image(let url, let alt):
        //     buildImage(url: url, alt: alt)
        }
    }

    private func imageURL(for src: String) -> URL? {
        if src.hasPrefix("http") {
            return URL(string: src)
        } else {
            return baseDir.appendingPathComponent(src)
        }
    }

    private func loadPage() {

        let fullscreen = UIScreen.main.bounds.size
        print("full screen \(fullscreen)")
        // FIXME: compute container, add stuff to container
        // and figure out how to determine pages

        // let layoutManager = NSLayoutManager()
        // let textContainer = NSTextContainer(size: containerSize)
        // let textStorage = NSTextStorage(string: text)
        // textStorage.addLayoutManager(layoutManager)

        let fileUrl = baseDir.appendingPathComponent(filePath)
        do {
            let htmlString = try String(contentsOf: fileUrl, encoding: .utf8)
            // let parser = HTMLContentParser()
            // self.parsedContent = parser.fromString(htmlString)
            self.parsedContent = HTMLParser.fromString(htmlString)
            self.isLoading = false
        } catch {
            print("failed to load page \(error)")
        }
    }
}
