import SwiftData
import SwiftUI

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
