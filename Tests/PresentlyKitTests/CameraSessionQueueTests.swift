import Foundation
import Testing
@testable import PresentlyKit

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
