import Foundation

enum XMLParserError: Error {
    case invalidEncoding(String?)
    case elementMismatch(String?)
}

struct XMLElement {
    let name: String
    let attributes: [String: String]
    var text: String?
    let namespace: String?
}

class XMLParser: NSObject {
    private var elements: [XMLElement] = []
    private var currentElement: XMLElement?
    private var error: XMLParserError?

    func parse(_ xmlString: String) throws {
        guard let data = xmlString.data(using: .utf8) else {
            throw XMLParserError.invalidEncoding("Only UTF-8 encoding is supported")
        }

        let parser = Foundation.XMLParser(data: data)
        parser.delegate = self

        // FIXME: check if error was set
        parser.parse()

        print("is there an error? \(error)")
    }

    func findFirst(name: String) -> XMLElement? {
        return elements.first(where: { $0.name == name })

    }

    func find(name: String) -> [XMLElement] { 
        return elements.filter { $0.name == name}
    }

    func numElements() -> Int {
        return elements.count
    }
}

// Extends the base XMLParser. Implements the XMLParserDelegate parser functions
// required by Foundation.XMLParser
//
// FIXME: this has no concept of the inherent tree structure
// that is there is no concept of children
extension XMLParser: XMLParserDelegate {
    // Called when parser encounters an opening XML tag
    // Captures element name including element prefix like `dc:title`
    func parser(_ parser: Foundation.XMLParser, didStartElement elementName: String, namespaceURI: String?, 
                qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {

        print("elementName: \(elementName)")
        print("namespaceURI: \(namespaceURI)")
        print("qName: \(qName)")
        print("attributes \(attributeDict)")

        var newElement = XMLElement(
            name: qName ?? elementName,
            attributes: attributeDict,
            namespace: namespaceURI,
        )

        currentElement = newElement
      }

    // Called when parser encounters text content between XML tags
    func parser(_ parser: Foundation.XMLParser, foundCharacters string: String) {
        print("foundCharacters \(string)")
        guard var current = currentElement else {
            error = XMLParserError.elementMismatch("Found characters for element but currentElement is not set")
            parser.abortParsing()
            return
        }
        current.text = string
        currentElement = current
    }

    // Called when parser encounters closing XML tag
    func parser(_ parser: Foundation.XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        print("didEndElement \(elementName)")
        print("namespaceURI \(namespaceURI)")
        print("qName \(qName)")

        let name = qName ?? elementName

        guard var current = currentElement else {
            error = XMLParserError.elementMismatch("Got end tag for element: \(name) but we aren't processing a currentElement")
            parser.abortParsing()
            return
        }

        if name != current.name {
            error = XMLParserError.elementMismatch("Got end tag for element: \(name) which does not match currentElement: \(current.name)")
            parser.abortParsing()
            return
        }
        print("capturing element \(current)")

        elements.append(current)
        currentElement = nil
    }

}
