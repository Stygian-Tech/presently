import SwiftData
import SwiftUI
import UIKit

struct CameraScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var storedSettings: [AppSettings]
    @State private var camera = CameraController()
    @State private var feedbackMessage: String?

    private var settings: AppSettings? {
        storedSettings.first
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let imageData = camera.capturedPhotoData,
               let image = UIImage(data: imageData) {
                review(image: image, imageData: imageData)
            } else {
                liveCamera
            }
        }
        .task {
            ensureSettingsExist()
            await camera.start()
        }
        .onDisappear {
            camera.stop()
        }
        .alert(
            "Presently",
            isPresented: Binding(
                get: { feedbackMessage != nil },
                set: { if !$0 { feedbackMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(feedbackMessage ?? "")
        }
    }

    private var liveCamera: some View {
        ZStack {
            CameraPreview(session: camera.session)
                .ignoresSafeArea()

            VStack {
                HStack {
                    Text("Presently")
                        .font(.headline)
                    Spacer()
                    Label("OAuth next", systemImage: "person.crop.circle.badge.exclamationmark")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(.black.opacity(0.55), in: Capsule())
                }
                .foregroundStyle(.white)
                .padding()

                Spacer()

                cameraStateMessage

                Button {
                    camera.capture()
                } label: {
                    ZStack {
                        Circle()
                            .fill(.white.opacity(0.25))
                            .frame(width: 84, height: 84)
                        Circle()
                            .fill(.white)
                            .frame(width: 68, height: 68)
                    }
                }
                .disabled(camera.state != .ready || camera.isCapturing)
                .accessibilityLabel("Take photo")
                .padding(.bottom, 28)
            }
        }
    }

    @ViewBuilder
    private var cameraStateMessage: some View {
        switch camera.state {
        case .idle, .ready:
            EmptyView()
        case .requestingPermission:
            ProgressView("Opening camera…")
                .foregroundStyle(.white)
                .padding()
        case .denied:
            Text("Camera access is required. Enable it in Settings.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .padding()
        case let .unavailable(message):
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .padding()
        }
    }

    private func review(image: UIImage, imageData: Data) -> some View {
        ZStack {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack {
                HStack {
                    Button("Retake", systemImage: "arrow.counterclockwise") {
                        camera.retake()
                    }
                    .buttonStyle(.borderedProminent)
                    Spacer()
                }
                .padding()

                Spacer()

                VStack(spacing: 14) {
                    Toggle(
                        "Save to Photos",
                        isOn: Binding(
                            get: { settings?.saveToPhotos ?? false },
                            set: updateSavePreference
                        )
                    )

                    Button {
                        queueDraft(imageData: imageData)
                    } label: {
                        Label("Post story", systemImage: "paperplane.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Text("The publishing transport is intentionally gated until native OAuth and DPoP are wired.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
                .padding()
            }
        }
    }

    private func ensureSettingsExist() {
        guard storedSettings.isEmpty else { return }
        modelContext.insert(AppSettings())
        try? modelContext.save()
    }

    private func updateSavePreference(_ enabled: Bool) {
        let value = settings ?? AppSettings()
        if settings == nil {
            modelContext.insert(value)
        }
        value.saveToPhotos = enabled
        try? modelContext.save()
    }

    private func queueDraft(imageData: Data) {
        guard imageData.count <= FlashesStoryContract.maximumImageBytes else {
            feedbackMessage = "This image exceeds Flashes' 10 MiB story limit."
            return
        }

        modelContext.insert(LocalStoryDraft(imageData: imageData))
        do {
            try modelContext.save()
        } catch {
            feedbackMessage = "The photo could not be saved as a pending story: \(error.localizedDescription)"
            return
        }

        if settings?.saveToPhotos == true {
            Task {
                do {
                    try await PhotoLibrarySaver.save(jpegData: imageData)
                    feedbackMessage = "Story saved as a pending draft and copied to Photos. OAuth publishing is the next slice."
                } catch {
                    feedbackMessage = "Draft saved, but Photos failed: \(error.localizedDescription)"
                }
            }
        } else {
            feedbackMessage = "Story saved as a pending draft. OAuth publishing is the next slice."
        }
        camera.retake()
    }
}

#Preview {
    CameraScreen()
        .modelContainer(for: [LocalStoryDraft.self, AppSettings.self], inMemory: true)
}
