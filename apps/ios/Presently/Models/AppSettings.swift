import Foundation
import SwiftData

@Model
final class AppSettings {
    @Attribute(.unique) var id: String
    var saveToPhotos: Bool

    init(id: String = "primary", saveToPhotos: Bool = false) {
        self.id = id
        self.saveToPhotos = saveToPhotos
    }
}
