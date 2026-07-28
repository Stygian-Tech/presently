import SwiftUI
import WidgetKit

@main
struct PresentlyControls: WidgetBundle {
    var body: some Widget {
        PresentlyCameraControl()
    }
}

struct PresentlyCameraControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: "tech.stygian.presently.open-camera"
        ) {
            ControlWidgetButton(action: PresentlyCaptureIntent()) {
                Label("Presently", systemImage: "camera.fill")
            }
        }
        .displayName("Presently Camera")
        .description("Open Presently to capture a story.")
    }
}
