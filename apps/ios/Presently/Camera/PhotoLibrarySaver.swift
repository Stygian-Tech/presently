import Photos

enum PhotoLibrarySaver {
    static func save(jpegData: Data) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw PhotoLibraryError.permissionDenied
        }

        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: jpegData, options: nil)
        }
    }
}

private enum PhotoLibraryError: LocalizedError {
    case permissionDenied

    var errorDescription: String? {
        "Allow Presently to add photos in Settings, or turn off Save to Photos."
    }
}
