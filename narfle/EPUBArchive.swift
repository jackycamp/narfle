import Foundation
import Compression
import UniformTypeIdentifiers
import os
import SwiftSoup
import SWXMLHash 

enum EPUBParseError: Error {
    case elementNotFound(String?)
    case attributeNotFound(String?)
    case missingFile(String?)
    case invalidOpf(String?)
}

enum EPUBError: Error {
    case extractError(String?)
}

struct EPUBMetadata {
    let title: String?
    let creator: String? 
    let language: String?
}

struct EPUBSpineItem {
    let id: String
    // let htmlUrl: String?
    let htmlUrl: URL?
}


func readUInt16(data: Data, at offset: Int) -> UInt16 {
    guard offset + 2 <= data.count else { return 0 }
    return data.subdata(in: offset..<offset + 2).withUnsafeBytes { bytes in
        bytes.load(as: UInt16.self)
    }
}

func readUInt32(data: Data, at offset: Int) -> UInt32 {
    guard offset + 4 <= data.count else { return 0 }
    return data.subdata(in: offset..<offset + 4).withUnsafeBytes { bytes in
        bytes.load(as: UInt32.self)
    }
}

struct EPUBArchive {
    static func extract(from sourceUrl: URL, to destinationUrl: URL) throws {
        let logger = Logger.init()
        guard sourceUrl.startAccessingSecurityScopedResource() else {
            throw EPUBError.extractError("Cannot access scoped resource for sourceUrl: \(sourceUrl)")
        }
        defer { sourceUrl.stopAccessingSecurityScopedResource() }

        let data = try Data(contentsOf: sourceUrl)
        let signature = readUInt32(data: data, at: 0)

        if signature != 0x04034b50 {
            throw EPUBError.extractError("Signature mismatch. Expected: \(0x04034b50) found: \(signature)")
        }

        var offset = 0
        while offset < data.count - 30 {
            let localSignature = readUInt32(data: data, at: offset)

            // FIXME: should warn here
            if localSignature != 0x04034b50 { break }

            let compressionMethod = readUInt16(data: data, at: offset + 8)
            let compressedSize = Int(readUInt32(data: data, at: offset + 18))
            let uncompressedSize = Int(readUInt32(data: data, at: offset + 22))
            let filenameLength = Int(readUInt16(data: data, at: offset + 26))
            let extraFieldLength = Int(readUInt16(data: data, at: offset + 28))

            let filenameStart = offset + 30
            let dataStart = filenameStart + filenameLength + extraFieldLength
            let filenameData = data.subdata(in: filenameStart..<filenameStart + filenameLength)
            let filename = String(data: filenameData, encoding: .utf8)

            // FIXME: should warn here or throw?
            guard let filename = String(data: filenameData, encoding: .utf8),
                !filename.isEmpty else {
                    offset = dataStart + compressedSize
                    continue
                }

            let fileUrl = destinationUrl.appendingPathComponent(filename)
            let isDirectory = filename.hasSuffix("/")

            if isDirectory {
                try FileManager.default.createDirectory(at: fileUrl, withIntermediateDirectories: true)
            }

            if !isDirectory {
                let parentDir = fileUrl.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

                let compressedData = data.subdata(in: dataStart..<dataStart + compressedSize)
                let decompressedData: Data

                switch compressionMethod {
                    case 0:
                        decompressedData = compressedData

                    case 8:
                        decompressedData = try compressedData.withUnsafeBytes { bytes in
                            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: uncompressedSize)
                            defer {buffer.deallocate()}

                            // Using Apple's decompression lib to decompress
                            let decompressedSize = compression_decode_buffer(
                                buffer, uncompressedSize,
                                bytes.bindMemory(to: UInt8.self).baseAddress!, compressedData.count,
                                nil, COMPRESSION_ZLIB
                            )

                            guard decompressedSize > 0 else {
                                throw EPUBError.extractError("Decmopression failed, decompressedSize is not greater than 0.")
                            }

                            return Data(bytes: buffer, count: decompressedSize)
                        }

                    default:
                        logger.warning("Unsupported compression method: \(compressionMethod), extracted contents may appear strange.")
                        decompressedData = compressedData
                }

                try decompressedData.write(to: fileUrl)
            }

            offset = dataStart + compressedSize
        }
    }


    static func extract(_ url: URL) -> URL {
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
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent("epub_structure_\(UUID().uuidString)")
        
        // let appSupportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!

        guard url.startAccessingSecurityScopedResource() else { return tempDir }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            print("created sandbox dir: \(tempDir)")
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
                // print("compressionMethod: \(compressionMethod)")
                let compressedSize = Int(readUInt32(data: data, at: offset + 18))
                // print("compressedSize: \(compressedSize)")
                let uncompressedSize = Int(readUInt32(data: data, at: offset + 22))
                // print("uncompressedSize: \(uncompressedSize)")
                let filenameLength = Int(readUInt16(data: data, at: offset + 26))
                // print("filenameLength: \(filenameLength)")
                let extraFieldLength = Int(readUInt16(data: data, at: offset + 28))
                // print("extraFieldLength: \(extraFieldLength)")

                let filenameStart = offset + 30
                let dataStart = filenameStart + filenameLength + extraFieldLength


                let filenameData = data.subdata(in: filenameStart..<filenameStart + filenameLength)
                // print("filenameData: \(filenameData)")

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
            print("error extracting epub archive: \(error)")
        }

        return tempDir
    }

    static func findHTMLFiles(_ url: URL) -> [String] {
        var htmlFiles: [String] = []
        let fileManager = FileManager.default

        func searchDirectory(_ dir: URL, relativePath: String = "") {
            do {
                print("checking contents")
                let contents = try fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey])
                print("got contents")
                
                for item in contents {
                    let resourceValues = try item.resourceValues(forKeys: [.isDirectoryKey])
                    let filename = item.lastPathComponent
                    print("filename: \(filename)")
                    let fullPath = relativePath.isEmpty ? filename : "\(relativePath)/\(filename)"
                    print("fullpath: \(fullPath)")
                    
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

        print("searching directory: \(url)")
        searchDirectory(url)

        return htmlFiles.sorted { a, b in
            let aNum = extractNumber(from: a)
            let bNum = extractNumber(from: b)
            return aNum < bNum
        }

    }

    static func getOpfPath(_ url: URL) throws -> String? {
        let logger = Logger.init()
        let metaUrl = url.appendingPathComponent("META-INF")
        let containerUrl = metaUrl.appendingPathComponent("container.xml")
        logger.debug("Looking for container.xml at: \(containerUrl)")

        let containerXmlString = try String(contentsOf: containerUrl, encoding: .utf8)
        print("containerXmlString \(containerXmlString)")
        let containerXml = XMLHash.parse(containerXmlString)
        let rootfileElement = containerXml["container"]["rootfiles"]["rootfile"].element

        guard let rootfile = rootfileElement else {
            throw EPUBParseError.elementNotFound("Could not find rootfile element.")
        }

        guard let opfPathAttribute = rootfile.attribute(by: "full-path") else {
            throw EPUBParseError.attributeNotFound("'full-path' attribute does not exist on rootfile element.")
        }

        return opfPathAttribute.text
    }

    static func getOpfUrl(_ url: URL) throws -> URL? {
        guard let opfPath = try EPUBArchive.getOpfPath(url) else {
            throw EPUBParseError.missingFile("Cannot find opf file path")
        }

        let opfUrl = url.appendingPathComponent(opfPath)
        return opfUrl
    }

    static func getTitle(_ url: URL) -> String? {
        let logger = Logger.init()
//        let fileManager = FileManager.default
        do {
            // FIXME: parse location of contentOpf from container.xml?
//            logger.debug("looking for container.xml")
//            let metaUrl = url.appendingPathComponent("META-INF")
//            let containerUrl = metaUrl.appendingPathComponent("container.xml")
//            logger.debug("container.xml path: \(containerUrl)")
//
//            let containerXmlString = try String(contentsOf: containerUrl, encoding: .utf8)
//
//            let containerXml = XMLHash.parse(containerXmlString)
//            let rootfile = containerXml["container"]["rootfiles"]["rootfile"].element
//            print("root file: \(rootfile)")
//            let opfPath = rootfile!.attribute(by: "full-path")?.text
//            print("opfPath: \(opfPath)")

            let opfPath = try EPUBArchive.getOpfPath(url)

            let opfUrl = url.appendingPathComponent(opfPath!)
            print("opfUrl \(opfUrl)")

            let opfXmlString = try String(contentsOf: opfUrl, encoding: .utf8)
            print("opfXml \(opfXmlString)")

            let opfXml = XMLHash.parse(opfXmlString)
            // let titleElement = opfXml["package"]["metadata"]["dc:title"].element
            // print("titleElement: \(titleElement)")
            // Try the standard EPUB location first
            if let title = opfXml["package"]["metadata"]["dc:title"].element?.text {
                return title
            }

            // let containerParser = XMLParser.init()
            // try containerParser.parse(containerXmlString)
            // logger.debug("containerParsing finished")
            // logger.debug("containerParser elements: \(containerParser.numElements())")
            //
            // print("containerXml string \(containerXmlString)")
            //
            // let rootFileElement = containerParser.findFirst(name: "rootfile")
            // print("rootFileElement: \(rootFileElement)")

            // find element with name rootFile
            // check attributes for "full-path"
            // which should give us the location of the .opf file


            // logger.debug("looking for opf")
            // let contentOpf = url.appendingPathComponent("content.opf")
            // logger.debug("opf path: \(contentOpf)")
            //
            // let xmlString = try String(contentsOf: contentOpf, encoding: .utf8)
            // let parser = XMLParser.init()
            // try parser.parse(xmlString)
            // let doc = try SwiftSoup.parse(xmlString)
            // logger.debug("parsed xml: \(doc)")
            //
            // let titleElement = try doc.select("dc\\:title").first()
            //
            // print("title element: \(titleElement)")


            return "Sample Title"
        } catch {
           logger.error("Cannot get title from url: \(error)") 
            return nil
        }
    }

    static func getMetadata(_ url: URL) throws -> EPUBMetadata {
        guard let opfPath = try EPUBArchive.getOpfPath(url) else {
            throw EPUBParseError.missingFile("Cannot find opf file")
        }
        let opfUrl = url.appendingPathComponent(opfPath)

        let opfXmlString = try String(contentsOf: opfUrl, encoding: .utf8)
        let opfXml = XMLHash.parse(opfXmlString)

        var title: String?
        var creator: String?
        var language: String?

        if let titleElement = opfXml["package"]["metadata"]["dc:title"].element {
           title = titleElement.text 
        }

        if let creatorElement = opfXml["package"]["metadata"]["dc:creator"].element {
            creator = creatorElement.text
        }

        if let langElement = opfXml["package"]["metadata"]["dc:language"].element {
            language = langElement.text
        }

        return EPUBMetadata(
            title: title,
            creator: creator,
            language: language
        )
    }

    static func getManifest(_ url: URL) {

    }

    static func getOpfXML(_ url: URL) throws -> XMLIndexer? {
        guard let opfPath = try EPUBArchive.getOpfPath(url) else {
            throw EPUBParseError.missingFile("Cannot find opf file")
        }

        let opfUrl = url.appendingPathComponent(opfPath)
        let opfXmlString = try String(contentsOf: opfUrl, encoding: .utf8)
        let opfXml = XMLHash.parse(opfXmlString)

        return opfXml
    }

    static func getSpine(_ url: URL) throws -> [EPUBSpineItem] {

        guard let opfUrl = try EPUBArchive.getOpfUrl(url) else {
            throw EPUBParseError.invalidOpf("Cannot determine opf url")
        }
        print("opf url: \(opfUrl)")

        guard let opfXml = try EPUBArchive.getOpfXML(url) else {
            throw EPUBParseError.invalidOpf("Cannot parse xml in opf file")
        }

        let opfParentUrl = opfUrl.deletingLastPathComponent()
        print("opf parent url: \(opfParentUrl)")

        var manifest: [String: URL] = [:]

        // First capture the entire manfiest. Building out a dictionary where:
        // {"id": "path to html file"}
        for item in opfXml["package"]["manifest"]["item"].all {
            print("manifest item: \(item)")
            let id = item.element!.attribute(by: "id")!.text
            let href = item.element!.attribute(by: "href")!.text
            let htmlUrl = opfParentUrl.appendingPathComponent(href)
            // manifest[id] = href
            manifest[id] = htmlUrl
        }

        print("got manifest: \(manifest)")

        // var spine: [String: EPUBSpineItem] = [:]
        var spine: [EPUBSpineItem] = []

        for elem in opfXml["package"]["spine"]["itemref"].all {
            // Capture idref for spine item.
            let id = elem.element!.attribute(by: "idref")!.text

            // Use idref to find corresponding item in manifest.
            // From here, we are interested in the href attribute of the manifest item.
            // let href = manifest[id] 
            let htmlUrl = manifest[id]

            let spineItem = EPUBSpineItem(
                id: id,
                htmlUrl: htmlUrl
            )

            // spine[id] = spineItem
            spine.append(spineItem)
        }
        return spine
    }
}
