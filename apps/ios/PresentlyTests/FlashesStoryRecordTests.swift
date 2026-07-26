import Foundation
import Testing
@testable import Presently

struct FlashesStoryRecordTests {
    @Test
    func createsCurrentFlashesStoryShape() throws {
        let blob = ATProtoBlob(
            cid: "bafkreiexample",
            mimeType: "image/jpeg",
            size: 512_000
        )
        let date = Date(timeIntervalSince1970: 1_753_488_000)

        let record = try FlashesStoryRecordFactory.make(blob: blob, createdAt: date)
        let data = try JSONEncoder().encode(record)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["$type"] as? String == "blue.flashes.story.post")
        #expect(json["expiresInMinutes"] as? Int == 1_440)
        #expect(json["createdAt"] as? String == "2025-07-26T00:00:00.000Z")

        let image = try #require(json["image"] as? [String: Any])
        #expect(image["$type"] as? String == "blob")
        #expect(image["mimeType"] as? String == "image/jpeg")
        #expect(image["size"] as? Int == 512_000)
    }

    @Test
    func rejectsImagesOverPublishedLimit() {
        let blob = ATProtoBlob(
            cid: "bafkreiexample",
            mimeType: "image/jpeg",
            size: FlashesStoryContract.maximumImageBytes + 1
        )

        #expect(throws: StoryContractError.imageTooLarge(blob.size)) {
            try FlashesStoryRecordFactory.make(blob: blob, createdAt: Date())
        }
    }

    @Test
    func rejectsNonJPEGForMVP() {
        let blob = ATProtoBlob(
            cid: "bafkreiexample",
            mimeType: "image/png",
            size: 10
        )

        #expect(throws: StoryContractError.unsupportedMIMEType("image/png")) {
            try FlashesStoryRecordFactory.make(blob: blob, createdAt: Date())
        }
    }
}

struct CameraSessionQueueTests {
    @Test
    func performsCameraWorkOffTheMainThread() async throws {
        let queue = CameraSessionQueue(label: "tech.stygian.presently.camera-session.tests")

        let ranOnMainThread = try await queue.perform {
            Thread.isMainThread
        }

        #expect(!ranOnMainThread)
    }
}

struct SelfieFramingModeTests {
    @Test
    func exposesPortraitAndLandscapeControlsInStableOrder() {
        #expect(SelfieFramingMode.allCases == [.portrait, .landscape])
        #expect(SelfieFramingMode.portrait.title == "Portrait")
        #expect(SelfieFramingMode.landscape.title == "Landscape")
    }
}

struct SaveToPhotosPreferenceTests {
    @Test
    func alwaysSavesRegardlessOfPerPhotoChoice() {
        #expect(SaveToPhotosPreference.always.shouldSave(whenAsked: false))
        #expect(SaveToPhotosPreference.always.shouldSave(whenAsked: true))
    }

    @Test
    func askUsesThePerPhotoChoice() {
        #expect(!SaveToPhotosPreference.ask.shouldSave(whenAsked: false))
        #expect(SaveToPhotosPreference.ask.shouldSave(whenAsked: true))
    }

    @Test
    func neverSkipsSavingRegardlessOfPerPhotoChoice() {
        #expect(!SaveToPhotosPreference.never.shouldSave(whenAsked: false))
        #expect(!SaveToPhotosPreference.never.shouldSave(whenAsked: true))
    }

    @Test
    func legacyBooleanMigratesToAlwaysOrAsk() {
        let settings = AppSettings()
        settings.saveToPhotosPreferenceRawValue = nil

        settings.saveToPhotos = true
        #expect(settings.saveToPhotosPreference == .always)

        settings.saveToPhotos = false
        #expect(settings.saveToPhotosPreference == .ask)
    }
}
