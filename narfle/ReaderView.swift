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
    @State private var pageIndex = 0 
    @State private var isLoading = true
    @State private var showControls = false
    @State private var title = "Sample Title"

    var body: some View {
        VStack {
            if isLoading {
                Text("Narfle reader (loading)")
            } else {
                HStack {
                    Spacer()

                    Text(title)
                        .font(.body)
                        .lineLimit(1)
                        .foregroundColor(.secondary)
                        .fontWeight(.bold)
                        .opacity(showControls ? 1.0 : 0.0)
                        .animation(.easeInOut(duration: 0.3), value: showControls) 

                    Spacer()
                    Button(action: { appState.selectedFile = nil }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .foregroundColor(.secondary)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                    }
                    // .padding()
                    .opacity(showControls ? 1.0 : 0.0)
                    .animation(.easeInOut(duration: 0.3), value: showControls) 
                    // .border(.green)
                }
                .padding(.trailing, 8)
                .padding(.leading, 8)
                // .border(.red)
                // TabView to achieve swipe for page turning
                TabView(selection: $pageIndex) {
                    ForEach(Array(appState.pages.enumerated()), id: \.offset) { index, page in
                        PageReaderView(page: page, pageIndex: pageIndex, baseDir: dir!)
                            .tag(index)
                            // .environmentObject(appState)
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
        .onTapGesture() {
            showControls = !showControls
        }
        .onAppear {
            loadFile()
        }
    }

    private func loadFile() {
        // TODO: when loading from a user picked file:
        // - Generate ID of document (will be used later when creating record)
        // - Perhaps we create the record here with status "pending"
        // - Retrieve application support directory
        // - Generate new directory in app support directory with the given id
        // - Extract document at selectedFile to this new directory
        // - Retrieve metadata from document at the extracted location
        // - Update record with metadata information
        // - Generate first few pages of content with buffer
        // - Set status of record to ready
        // - Render first page


        // NOTE: Other things to note:
        // - Perhaps the model that represents a "File" or "Book" or whatever
        //   should be called NarfDoc or NarFile. Perhaps bundle makes sense here.
        //   Consider: NarfBundle, NarfBdl, NarBdl, NarBundle. Leaning towards NarfBundle.

        let bundleId = UUID()
        let fileManager = FileManager.default

        // FIXME: check the robustness of this
        let appDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!

        let bundleDir = appDir.appendingPathComponent(bundleId.uuidString)

        do {
            try fileManager.createDirectory(at: bundleDir, withIntermediateDirectories: true)
            try EPUBArchive.extract(from: appState.selectedFile!, to: bundleDir)
        } catch {
            print("error: \(error)")

        }

        self.dir = EPUBArchive.extract(appState.selectedFile!)
        print("extracted file to \(self.dir)")
        self.htmlFiles = EPUBArchive.findHTMLFiles(self.dir!)
        print("found html files: \(self.htmlFiles)")

        let title = EPUBArchive.getTitle(self.dir!)
        print("got title: \(title)")
        self.title = title!

        do {
            let metadata = try EPUBArchive.getMetadata(self.dir!)
            print("got metadata: \(metadata)")
        } catch {
            print("error getting metadata \(error)")
            
        }

        let screenDimensions = UIScreen.main.bounds.size
        print("screen dimensions \(screenDimensions)")

        var pages: [[ContentElement]] = []

        do {
            let spine = try EPUBArchive.getSpine(self.dir!)
            print("got spine: \(spine)")

            for item in spine {
                // let htmlUrl = self.dir!.appendingPathComponent(item.htmlUrl!)
                let htmlUrl = item.htmlUrl!
                print("chunking html file at url: \(htmlUrl)")

                let htmlString = try String(contentsOf: htmlUrl, encoding: .utf8)
                if htmlUrl.absoluteString.hasSuffix("Chapter001.html") {
                    print("chapter 1 html")
                    print(htmlString)
                }
                let elements = HTMLParser.fromString(htmlString)
                print("captured \(elements.count) elements from \(htmlUrl)")

                let chunkedPages = chunkContent(elements, maxHeight: screenDimensions.height - 200, maxWidth: screenDimensions.width - 100)
                print("captured \(chunkedPages.count) pages for this html file")
                
                pages.append(contentsOf: chunkedPages)
            }
        } catch {
            print("error processing spine \(error)")
        }

        print("number of pages built: \(pages.count)")
        // FIXME: shoving it in global state for now
        appState.pages = pages

        // consider using Application Support directory or caches instead of temp directory
        // let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        // let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        // defer { try? fileManager.removeItem(at: tempDir) }
        self.isLoading = false

        return
    }

    private func chunkContent(_ elements: [ContentElement], maxHeight: CGFloat, maxWidth: CGFloat) -> [[ContentElement]] {
        var pages: [[ContentElement]] = []
        var currentPage: [ContentElement] = []
        var currentHeight: CGFloat = 0

        for element in elements {
            let estimatedHeight = estimateHeight(for: element, containerWidth: maxWidth)
            // print("element: \(element)")
            // print("estimated height: \(estimatedHeight)")

            // FIXME: this will behave strangely for long paragraphs...

            if currentHeight + estimatedHeight > maxHeight && !currentPage.isEmpty {
                pages.append(currentPage)
                currentPage = [element]
                currentHeight = estimatedHeight
            } else {
                currentPage.append(element)
                currentHeight += estimatedHeight
            }
        }

        // it's possible that we may have gone through all elements but not reached
        // max height, so we capture the final page if it has any elements
        if !currentPage.isEmpty {
            pages.append(currentPage)
        }

        return pages
    }

    private func estimateHeight(for element: ContentElement, containerWidth: CGFloat) -> CGFloat {
        switch element {
            case .heading: return 40
            case .heading2: return 36
            case .heading3: return 34
            case .paragraph(let text):
                // Rough estimation: ~20 chars per line, 20pt line height
                let lines = text.count / Int(containerWidth / 10) + 1
                return CGFloat(lines) * 8
            case .image: return 200 // or parse actual dimensions if available
            case .lineBreak: return 2
        }
    }

}

struct PageReaderView: View {
    let page: [ContentElement]
    let pageIndex: Int
    // let filePath: String
    let baseDir: URL

    @EnvironmentObject var appState: AppState
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
                .padding(.horizontal, 24)
                .padding(.vertical, 0)
                // .border(.red)
            }
        }
        .onAppear {
            // loadPage()
            loadContent()
        }
    }

    @ViewBuilder
    private func buildContentView(for element: ContentElement) -> some View {
        switch element {
        case .heading(let text):
            Text(text)
                .font(.title)

        case .heading2(let text):
            Text(text)
                .font(.title2)
        
        case .heading3(let text):
            Text(text)
                .font(.title3)

        case .paragraph(let text):
            Text(text)
                // .font(.body)
                .font(.system(size: 14))
                .lineLimit(nil)
                // .textSelection(.enabled)
                .lineSpacing(1)
                .opacity(0.9)

        // case .emphasis(let text):
        //     Text(text)

        case .lineBreak:
            Spacer()
                .frame(height: 2)

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

    private func loadContent() {
        // let page = appState.pages[pageIndex]
        print("loading new page \(pageIndex)")
        print("number of elements on page: \(page.count)")
        self.parsedContent = page
        self.isLoading = false
    }

    // private func loadPage() {
    //     let fileUrl = baseDir.appendingPathComponent(filePath)
    //     do {
    //         let htmlString = try String(contentsOf: fileUrl, encoding: .utf8)
    //         // let parser = HTMLContentParser()
    //         // self.parsedContent = parser.fromString(htmlString)
    //         self.parsedContent = HTMLParser.fromString(htmlString)
    //         self.isLoading = false
    //     } catch {
    //         print("failed to load page \(error)")
    //     }
    // }
}
