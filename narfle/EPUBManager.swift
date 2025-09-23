import Foundation
import Compression
import UniformTypeIdentifiers
import os
import SwiftSoup
import SWXMLHash

enum EPUBError: Error {
    case extractError(String?)
    case decodeError(String?)
}

/// FIXME: is this always the expected sig?
let SIG = 0x04034b50

/// TODO: DOC
///
struct EPUBManager {

    /// TODO: DOC
    static func extract(from sourceURL: URL, to destinationURL: URL) throws {
        guard sourceURL.startAccessingSecurityScopedResource() else {
            throw EPUBError.extractError("Cannot access scoped resource for sourceURL: \(sourceURL)")
        }
        defer { sourceURL.stopAccessingSecurityScopedResource() }

        let data = try Data(contentsOf: sourceURL)
        let signature = EPUBManager.readUInt32(data: data, at: 0)

        if signature != SIG {
            throw EPUBError.extractError("Signature mismatch. Expected: \(SIG) found: \(signature)")
        }

        var offset = 0
        // FIXME: why 30?
        while offset < data.count - 30 {
            let chunkSignature = EPUBManager.readUInt32(data: data, at: offset)

            if chunkSignature != SIG { 
                throw EPUBError.extractError("Signature mismatch for chunk signature. Expected: \(SIG) found: \(chunkSignature)")
            }

            let compressionMethod = EPUBManager.readUInt16(data: data, at: offset + 8)
            let compressedSize = Int(EPUBManager.readUInt32(data: data, at: offset + 18))
            let uncompressedSize = Int(EPUBManager.readUInt32(data: data, at: offset + 22))
            let filenameLength = Int(EPUBManager.readUInt16(data: data, at: offset + 26))
            let extraFieldLength = Int(EPUBManager.readUInt16(data: data, at: offset + 28))

            let filenameStart = offset + 30
            let dataStart = filenameStart + filenameLength + extraFieldLength
            let filenameData = data.subdata(in: filenameStart..<filenameStart + filenameLength)

            // FIXME: under what circumstances would the filename be empty?
            // should this be an error condition instead?
            guard let filename = String(data: filenameData, encoding: .utf8),
                !filename.isEmpty else {
                    offset = dataStart + compressedSize
                    continue
                }

            let fileURL = destinationURL.appendingPathComponent(filename)
            let isDirectory = filename.hasSuffix("/")

            if isDirectory {
                try FileManager.default.createDirectory(at: fileURL, withIntermediateDirectories: true)
            } else {
                let decompressedData = try EPUBManager.decodeDataChunk(
                    data, 
                    compressionAlgorithm: compressionMethod, 
                    start: dataStart, 
                    end: compressedSize, 
                    capacity: uncompressedSize)

                let parentDir = fileURL.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
                try decompressedData.write(to: fileURL)
            }

            offset = dataStart + compressedSize
        }

    }

    static func decodeDataChunk(
        _ data: Data, 
        compressionAlgorithm: UInt16,
        start: Int,
        end: Int,
        capacity: Int
    ) throws -> Data {
        let compressedData = data.subdata(in: start..<start + end)
        let decompressedData: Data

        switch compressionAlgorithm {
            case 0:
                decompressedData = compressedData 

            case 8:
                decompressedData = try compressedData.withUnsafeBytes { bytes in
                    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
                    defer {buffer.deallocate()}

                    let decompressedSize = compression_decode_buffer(
                        buffer,
                        capacity,
                        bytes.bindMemory(to: UInt8.self).baseAddress!,
                        compressedData.count,
                        nil,
                        COMPRESSION_ZLIB
                    )

                    guard decompressedSize > 0 else {
                        throw EPUBError.decodeError("Decoding data chunk failed, decompressedSize is not greater than 0.")
                    }

                    return Data(bytes: buffer, count: decompressedSize)
                }

            default:
                throw EPUBError.decodeError("Unsupported compression algorithm: \(compressionAlgorithm)")
        }

        return decompressedData
    }

    static func readUInt16(data: Data, at offset: Int) -> UInt16 {
        guard offset + 2 <= data.count else { return 0 }
        return data.subdata(in: offset..<offset + 2).withUnsafeBytes { bytes in
            bytes.load(as: UInt16.self)
        }
    }

    static func readUInt32(data: Data, at offset: Int) -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        return data.subdata(in: offset..<offset + 4).withUnsafeBytes { bytes in
            bytes.load(as: UInt32.self)
        }
    }

}


