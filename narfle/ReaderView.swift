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
    // @State private var dragOffset: CGFloat = 0

    var body: some View {
        VStack {
            if isLoading {
                Text("Narfle reader (loading)")
            } else {
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
        .onAppear {
            loadFile()
        }
    }

    private func loadFile() {
        self.dir = EPUBArchive.extract(appState.selectedFile!)
        print("extracted file to \(self.dir)")
        self.htmlFiles = EPUBArchive.findHTMLFiles(self.dir!)
        print("found html files: \(self.htmlFiles)")

        // TODO: given a epub archive, extract the html content from it
        // then split the html content into chunks
        // the chunk size is determined by the screen size
        // each chunk will be a container of content
        // we go through the html content and iteratively fill the containers
        // each container is then a "single page" 
        //
        // for now, all of this will be kept in memory
        //
        // could eventually have a data structure like:
        // content = [
        //  id: cover, elements: [],
        //  id: page1, elements: [],
        //  id: page2, elements: []
        // ]

        let screenDimensions = UIScreen.main.bounds.size
        print("screen dimensions \(screenDimensions)")

        var pages: [[ContentElement]] = []

        // layoutManager with text container won't work when we have image elements..
        // let layoutManager = NSLayoutManager()
        // let textContainer = NSTextContainer(size: screenDimensions)
        // let textStorage = NSTextStorage()
        // textStorage.addLayoutManager(layoutManager)

        for htmlFile in self.htmlFiles {
            do {
                print("chunking html file \(htmlFile)")

                let fullUrl = self.dir!.appendingPathComponent(htmlFile)
                let htmlString = try String(contentsOf: fullUrl, encoding: .utf8)

                let elements = HTMLParser.fromString(htmlString)
                print("captured \(elements.count) elements from html")

                let chunkedPages = chunkContent(elements, maxHeight: screenDimensions.height - 100, maxWidth: screenDimensions.width)
                print("captured \(chunkedPages.count) pages for this html file")

                // helpful for debugging
                // if htmlFile == "ops/xhtml/ch01.html" {
                //     print("htmlString: \(htmlString)")
                //     print("elements: \(elements)")
                // }

                pages.append(contentsOf: chunkedPages)
            } catch {
                print("error chunking html file \(error)")
                
            }
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
            case .paragraph(let text):
                // Rough estimation: ~20 chars per line, 20pt line height
                let lines = text.count / Int(containerWidth / 10) + 1
                return CGFloat(lines) * 20
            case .image: return 200 // or parse actual dimensions if available
            case .lineBreak: return 8
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
                .padding()
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
