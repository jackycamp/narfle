import SwiftSoup

struct HTMLParser {
    static func fromString(_ htmlString: String) -> [ContentElement] {
        var elements: [ContentElement] = []

        // a basic DFS algorithm to parse html documents
        do {
            let doc = try SwiftSoup.parse(htmlString)
            let body = try doc.select("body").first() ?? doc

            var stack: [Element] = Array(try body.children().reversed())

            while !stack.isEmpty {
                let node = stack.removeLast()
                let children = try node.children()

                if children.isEmpty {
                    // leaf node - parse and map it to an internal ContentElement
                    if let parsed = try HTMLParser.parseElement(node) {
                        elements.append(parsed)
                    }
                } else {
                    // if node has children but still has direct text we parse it
                    let ownText = try node.ownText().trimmingCharacters(in: .whitespacesAndNewlines)
                    if !ownText.isEmpty {
                        if let parsed = try parseElementWithOwnText(node, ownText) {
                            elements.append(parsed)
                        }
                    }

                    // add this nodes children to the stack 
                    // (reversed so that we maintain the document's order)
                    for child in children.reversed() {
                        stack.append(child)
                    }
                }
            }
            
        } catch {
            print("HTML parsing error: \(error)")
        }

        print("parsed elements: \(elements.count)")
        return elements
    }

    private static func parseElement(_ element: Element) throws -> ContentElement? {
        let tagName = try element.tagName().lowercased()
        let text = try element.text()

        switch tagName {
        case "h1": return .heading(text: text)
        case "h2": return .heading(text: text)
        case "h3": return .heading(text: text)
        case "p": return .paragraph(text: text)
        case "br": return .lineBreak
        case "img":
            let src = try element.attr("src")
            let alt = try element.attr("alt")
            return .image(src: src, alt: alt.isEmpty ? nil : alt)

        default:
            // For unknown tags, just return the text as paragraph
            return text.isEmpty ? nil : .paragraph(text: text)
        }
    }

    private static func parseElementWithOwnText(_ element: Element, _ text: String) throws -> ContentElement? {
        let tagName = try element.tagName().lowercased()

        switch tagName {
        case "h1": return .heading(text: text)
        case "h2": return .heading(text: text)
        case "h3": return .heading(text: text)
        case "p": return .paragraph(text: text)
        case "br": return .lineBreak
        default:
            // For unknown tags, just return the text as paragraph
            return text.isEmpty ? nil : .paragraph(text: text)
        }
    }
}
