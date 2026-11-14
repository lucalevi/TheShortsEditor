import AppKit
import CoreMedia
import EditorCore
import Photos

/// The user's Photos library, read with their permission: what is in it, small pictures of it,
/// and copying an item in as a file (from iCloud first when it is only there).
enum PhotosLibrary {
    enum Kind: String, CaseIterable, Identifiable {
        case videos, photos, all

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .videos: "Videos"
            case .photos: "Photos"
            case .all: "All"
            }
        }
    }

    enum ImportError: LocalizedError {
        case noFile

        var errorDescription: String? { "This item has no picture or video file that can be copied." }
    }

    static var status: PHAuthorizationStatus { PHPhotoLibrary.authorizationStatus(for: .readWrite) }

    static var canRead: Bool { status == .authorized || status == .limited }

    static func requestAccess() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    /// The newest items first, at most `limit`.
    static func items(_ kind: Kind, limit: Int = 600) -> [PHAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = limit
        let result: PHFetchResult<PHAsset> =
            switch kind {
            case .videos: PHAsset.fetchAssets(with: .video, options: options)
            case .photos: PHAsset.fetchAssets(with: .image, options: options)
            case .all:
                {
                    options.predicate = NSPredicate(
                        format: "mediaType == %d || mediaType == %d", PHAssetMediaType.video.rawValue, PHAssetMediaType.image.rawValue)
                    return PHAsset.fetchAssets(with: options)
                }()
            }
        var items: [PHAsset] = []
        items.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in items.append(asset) }
        return items
    }

    private static let imageManager = PHCachingImageManager()

    /// A small picture of `asset` (from iCloud too, so it may take a moment).
    static func thumbnail(of asset: PHAsset, side: CGFloat = 180) async -> NSImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            imageManager.requestImage(for: asset, targetSize: CGSize(width: side, height: side), contentMode: .aspectFill, options: options) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    /// Where copies of library items are kept.
    static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Shorts Editor/From Photos", directoryHint: .isDirectory)
    }

    /// The file to use for `asset`: the edited version if it was edited in Photos, else the original.
    private static func resource(of asset: PHAsset) -> PHAssetResource? {
        let resources = PHAssetResource.assetResources(for: asset)
        let preferred: [PHAssetResourceType] = asset.mediaType == .video ? [.fullSizeVideo, .video] : [.fullSizePhoto, .photo]
        for type in preferred {
            if let match = resources.first(where: { $0.type == type }) { return match }
        }
        return nil
    }

    /// Copies `asset` into the app's folder (once; later it is reused), downloading it from
    /// iCloud first when needed. `progress` gets 0…1 while it downloads.
    static func file(for asset: PHAsset, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        guard let resource = resource(of: asset) else { throw ImportError.noFile }
        let safeID = asset.localIdentifier.replacingOccurrences(of: "/", with: "-")
        let name = resource.originalFilename.isEmpty ? "\(safeID).\(asset.mediaType == .video ? "mov" : "jpg")" : resource.originalFilename
        let folder = folder.appending(path: safeID, directoryHint: .isDirectory)
        let url = folder.appending(path: name)
        // Edited later in Photos: the copy is made again.
        let edited = asset.modificationDate ?? asset.creationDate ?? .distantPast
        if let made = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate, made >= edited {
            return url
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: url)
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        options.progressHandler = { progress($0) }
        try await PHAssetResourceManager.default().writeData(for: resource, toFile: url, options: options)
        return url
    }
}

extension PHAsset {
    /// "0:12" for a video, nil for a photo.
    var lengthLabel: String? {
        guard mediaType == .video else { return nil }
        return TimeFormat.string(CMTime(seconds: duration, preferredTimescale: 600)).replacingOccurrences(of: #"\.\d$"#, with: "", options: .regularExpression)
    }
}

extension EditorModel {
    /// Copies library items in (from iCloud when needed, with progress on their tiles), then adds
    /// them like files: to Media, the end of the timeline, or over the clips at the playhead.
    func importFromPhotos(_ assets: [PHAsset], to destination: ImportDestination) {
        let fresh = assets.filter { photoDownloads[$0.localIdentifier] == nil }
        guard !fresh.isEmpty else { return }
        for asset in fresh { photoDownloads[asset.localIdentifier] = 0 }
        Task {
            var urls: [URL] = []
            var failed: [String] = []
            for asset in fresh {
                let id = asset.localIdentifier
                do {
                    let url = try await PhotosLibrary.file(for: asset) { fraction in
                        Task { @MainActor in if self.photoDownloads[id] != nil { self.photoDownloads[id] = fraction } }
                    }
                    urls.append(url)
                } catch {
                    Log.media.failure("importFromPhotos", error)
                    failed.append(error.localizedDescription)
                }
                photoDownloads[id] = nil
            }
            if !urls.isEmpty { importFiles(urls, to: destination) }
            if !failed.isEmpty {
                alert = AlertMessage(
                    title: failed.count == 1 ? "An item couldn't be added" : "\(failed.count) items couldn't be added",
                    message: (Array(Set(failed)).joined(separator: "\n")) + "\n\nIf it is in iCloud, check that this Mac is online.")
            }
        }
    }
}
