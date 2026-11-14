import CoreGraphics
import CoreMedia
import EditorCore
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Saves one frame of the Short as a picture, e.g. for its thumbnail.
public enum FrameExport {
    public enum Format: String, CaseIterable, Identifiable, Sendable {
        case jpeg, png

        public var id: String { rawValue }
        public var type: UTType { self == .jpeg ? .jpeg : .png }
        public var displayName: String { self == .jpeg ? "JPEG" : "PNG" }
    }

    public enum WriteError: LocalizedError {
        case cannotWrite

        public var errorDescription: String? { "The picture couldn't be saved there." }
    }

    /// The frame at `time` as it plays, at full size (1080 × 1920), with titles and captions.
    public static func frame(of project: Project, at time: CMTime) async throws -> CGImage {
        try await ProjectPoster.frame(of: project, at: time.clamped(.zero, max(.zero, project.duration - .oneFrame)))
    }

    /// Writes `image` to `url` (replacing a file there). JPEG at high quality.
    public static func write(_ image: CGImage, to url: URL, format: Format) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, format.type.identifier as CFString, 1, nil) else {
            throw WriteError.cannotWrite
        }
        let options: [CFString: Any] = format == .jpeg ? [kCGImageDestinationLossyCompressionQuality: 0.92] : [:]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw WriteError.cannotWrite }
    }
}
