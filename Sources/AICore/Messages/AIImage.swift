import Foundation

/// A provider-neutral image input payload.
public struct AIImage: Sendable, Codable, Equatable {
    public let data: Data
    public let mediaType: AIMediaType

    public init(data: Data, mediaType: AIMediaType) {
        self.data = data
        self.mediaType = mediaType
    }

    public enum AIMediaType: String, Sendable, Codable, Equatable {
        case jpeg = "image/jpeg"
        case png = "image/png"
        case gif = "image/gif"
        case webp = "image/webp"
    }

    public static func from(fileURL: URL) throws -> AIImage {
        guard fileURL.isFileURL else {
            throw AIError.invalidRequest("Image inputs must be loaded from a local file URL")
        }

        let data = try Data(contentsOf: fileURL)
        let mediaType = try mediaType(forPathExtension: fileURL.pathExtension)
        return AIImage(data: data, mediaType: mediaType)
    }

    public static func from(base64: String, mediaType: AIMediaType) throws -> AIImage {
        guard let data = Data(base64Encoded: base64) else {
            throw AIError.invalidRequest("Image base64 data could not be decoded")
        }

        return AIImage(data: data, mediaType: mediaType)
    }

    private static func mediaType(forPathExtension pathExtension: String) throws -> AIMediaType {
        switch pathExtension.lowercased() {
        case "jpg", "jpeg":
            return .jpeg
        case "png":
            return .png
        case "gif":
            return .gif
        case "webp":
            return .webp
        default:
            throw AIError.invalidRequest("Unsupported image file type: \(pathExtension)")
        }
    }
}
