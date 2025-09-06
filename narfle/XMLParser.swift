import Foundation

enum XMLParserError: Error {
    case invalidEncoding
}

class XMLParser: NSObject, XMLParserDelegate {
    func parse(_ xmlString: String) throws {
        guard let data = xmlString.data(using: .utf8) else {
            throw XMLParserError.invalidEncoding 
        }

        let parser = Foundation.XMLParser(data: data)
        parser.delegate = self

        parser.parse()
    }

    func findElement(_ elementName: String) {

    }

    // XMLParserDelegate callbacks called by Foundation's XMLParser
    // as it encounters certain content - as if triggering eventsj

    // Called when parser encounters an opening XML tag
    // Captures element name including element prefix like `dc:title`
    func parser(_ parser: Foundation.XMLParser, didStartElement elementName: String, namespaceURI: String?, 
                qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        print("elementName: \(elementName)")
        print("namespaceURI: \(namespaceURI)")
        print("qName: \(qName)")
        print("attributes \(attributeDict)")
      }

    // Called when parser encounters text content between XML tags
    func parser(_ parser: Foundation.XMLParser, foundCharacters string: String) {
        print("foundCharacters \(string)")
    }

    // Called when parser encounters closing XML tag
    func parser(_ parser: Foundation.XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        print("didEndElement \(elementName)")
        print("namespaceURI \(namespaceURI)")
        print("qName \(qName)")

    }
}
