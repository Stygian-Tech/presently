import Foundation
import SwiftData

enum SaveToPhotosPreference: String, CaseIterable, Identifiable {
    case always
    case ask
    case never

    var id: Self { self }

    var title: String {
        switch self {
        case .always:
            "Always"
        case .ask:
            "Ask"
        case .never:
            "Never"
        }
    }

    var explanation: String {
        switch self {
        case .always:
            "Save every photo you post to your library."
        case .ask:
            "Show a Save to Photos option before each post."
        case .never:
            "Post without adding a copy to your library."
        }
    }

    func shouldSave(whenAsked saveThisPhoto: Bool) -> Bool {
        switch self {
        case .always:
            true
        case .ask:
            saveThisPhoto
        case .never:
            false
        }
    }
}

enum DefaultCameraPreference: String, CaseIterable, Identifiable {
    case back
    case front

    var id: Self { self }

    var title: String {
        switch self {
        case .back:
            "Rear Camera"
        case .front:
            "Front Camera"
        }
    }

    var explanation: String {
        switch self {
        case .back:
            "Open Presently ready to photograph what’s in front of you."
        case .front:
            "Open Presently ready to take a selfie."
        }
    }
}

@Model
final class AppSettings {
    @Attribute(.unique) var id: String
    var saveToPhotos: Bool
    var saveToPhotosPreferenceRawValue: String?
    var defaultCameraRawValue: String?

    init(
        id: String = "primary",
        saveToPhotosPreference: SaveToPhotosPreference = .ask,
        defaultCamera: DefaultCameraPreference = .back
    ) {
        self.id = id
        self.saveToPhotos = saveToPhotosPreference == .always
        self.saveToPhotosPreferenceRawValue = saveToPhotosPreference.rawValue
        self.defaultCameraRawValue = defaultCamera.rawValue
    }

    var saveToPhotosPreference: SaveToPhotosPreference {
        get {
            guard let saveToPhotosPreferenceRawValue else {
                return saveToPhotos ? .always : .ask
            }
            return SaveToPhotosPreference(rawValue: saveToPhotosPreferenceRawValue) ?? .ask
        }
        set {
            saveToPhotosPreferenceRawValue = newValue.rawValue
            saveToPhotos = newValue == .always
        }
    }

    var defaultCamera: DefaultCameraPreference {
        get {
            guard let defaultCameraRawValue else {
                return .back
            }
            return DefaultCameraPreference(rawValue: defaultCameraRawValue) ?? .back
        }
        set {
            defaultCameraRawValue = newValue.rawValue
        }
    }
}
