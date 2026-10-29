import AppIntents
import Observation

enum PresentlyCaptureFacing: String, Codable, Sendable {
    case back
    case front
}

struct PresentlyCaptureContext: Codable, Equatable, Sendable {
    var facing: PresentlyCaptureFacing = .back
}

/// Process-local routing; the capture extension always opens its own viewfinder.
@MainActor
@Observable
final class PresentlyCaptureLaunch {
    static let shared = PresentlyCaptureLaunch()
    var requestID = 0
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
        PresentlyCaptureLaunch.shared.requestID += 1
        return .result()
    }
}
