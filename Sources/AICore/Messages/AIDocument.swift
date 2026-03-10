import Foundation

/// A provider-neutral document input payload.
public struct AIDocument: Sendable, Codable, Equatable {
    public let data: Data
    public let mediaType: AIMediaType
    public let filename: String?

    public init(data: Data, mediaType: AIMediaType, filename: String? = nil) {
        self.data = data
        self.mediaType = mediaType
        self.filename = filename
    }

    public enum AIMediaType: String, Sendable, Codable, Equatable {
        case pdf = "application/pdf"
        case plainText = "text/plain"
    }

    public static func from(fileURL: URL, mediaType: AIMediaType? = nil) throws -> AIDocument {
        guard fileURL.isFileURL else {
            throw AIError.invalidRequest("Document inputs must be loaded from a local file URL")
        }

        let resolvedMediaType = try mediaType ?? inferredMediaType(forPathExtension: fileURL.pathExtension)
        let data = try Data(contentsOf: fileURL)
        return AIDocument(data: data, mediaType: resolvedMediaType, filename: fileURL.lastPathComponent)
    }

    public static func from(base64: String, mediaType: AIMediaType, filename: String? = nil) throws -> AIDocument {
        guard let data = Data(base64Encoded: base64) else {
            throw AIError.invalidRequest("Document base64 data could not be decoded")
        }

        return AIDocument(data: data, mediaType: mediaType, filename: filename)
    }

    private static func inferredMediaType(forPathExtension pathExtension: String) throws -> AIMediaType {
        switch pathExtension.lowercased() {
        case "pdf":
            return .pdf
        case "txt", "text", "md":
            return .plainText
        default:
            throw AIError.invalidRequest("Unsupported document file type: \(pathExtension)")
        }
    }
}
