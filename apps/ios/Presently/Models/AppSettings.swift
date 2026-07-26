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

@Model
final class AppSettings {
    @Attribute(.unique) var id: String
    var saveToPhotos: Bool
    var saveToPhotosPreferenceRawValue: String?

    init(
        id: String = "primary",
        saveToPhotosPreference: SaveToPhotosPreference = .ask
    ) {
        self.id = id
        self.saveToPhotos = saveToPhotosPreference == .always
        self.saveToPhotosPreferenceRawValue = saveToPhotosPreference.rawValue
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
}
