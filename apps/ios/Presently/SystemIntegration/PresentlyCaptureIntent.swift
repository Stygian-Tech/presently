import AppIntents

enum PresentlyCaptureFacing: String, Codable, Sendable {
    case back
    case front
}

struct PresentlyCaptureContext: Codable, Equatable, Sendable {
    var facing: PresentlyCaptureFacing = .back
}

@available(iOS 18.0, *)
struct PresentlyCaptureIntent: CameraCaptureIntent {
    typealias AppContext = PresentlyCaptureContext

    static let title: LocalizedStringResource = "Open Presently Camera"
    static let description = IntentDescription(
        "Open Presently directly into its camera."
    )

    @MainActor
    func perform() async throws -> some IntentResult {
        .result()
    }
}
