import Foundation
import SwiftData
import SwiftUI

enum PresentlyLinks {
    static let feedbackBoard = URL(
        string: "https://userinput.app/s/did:plc:qy5pluw2bsuq2x6albsgkvx3/3msgekt2gyt2p"
    )!
}

@main
struct PresentlyApp: App {
    private let modelContainer: ModelContainer
    @State private var auth = OAuthSessionManager()

    init() {
        do {
            modelContainer = try ModelContainer(
                for: LocalStoryDraft.self,
                AppSettings.self
            )
        } catch {
            fatalError("Unable to create Presently's local store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            CameraScreen()
                .environment(auth)
                .onOpenURL { url in
                    Task {
                        await auth.handleCallback(url)
                    }
                }
        }
        .modelContainer(modelContainer)
    }
}
