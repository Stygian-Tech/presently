import LockedCameraCapture
import SwiftData
import SwiftUI
import UIKit

struct CameraScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(OAuthSessionManager.self) private var auth
    @Query private var storedSettings: [AppSettings]
    @State private var camera = CameraController()
    @State private var feedbackMessage: String?
    @State private var presentedSheet: CameraSheet?
    @State private var saveThisPhoto = false
    @State private var zoomAtGestureStart: Double?

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
        .task {
            guard #available(iOS 18.0, *) else { return }
            await importLockedCameraCaptures()
        }
        .onDisappear {
            camera.stop()
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .settings:
                if let settings {
                    CameraSettingsSheet(settings: settings)
                }
            case .account:
                AccountSheet(auth: auth)
            }
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
            CameraPreview(
                session: camera.session,
                isCaptureEnabled: camera.state == .ready && !camera.isCapturing,
                onCapture: camera.capture
            )
                .ignoresSafeArea()
                .gesture(
                    MagnifyGesture()
                        .onChanged { value in
                            guard !camera.supportsSmartSelfieFraming else { return }
                            let startingZoom = zoomAtGestureStart ?? camera.zoomFactor
                            zoomAtGestureStart = startingZoom
                            camera.setZoomFactor(startingZoom * value.magnification)
                        }
                        .onEnded { _ in
                            zoomAtGestureStart = nil
                        }
                )

            VStack {
                HStack {
                    Text("Presently")
                        .font(.headline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.45), in: Capsule())
                    Spacer()
                    Button {
                        presentedSheet = .account
                    } label: {
                        Image(
                            systemName: auth.session == nil
                                ? "person.crop.circle"
                                : "person.crop.circle.fill.badge.checkmark"
                        )
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.45), in: Circle())
                    }
                    .accessibilityLabel(
                        auth.session == nil
                            ? "Connect account"
                            : "Connected account"
                    )
                    Button {
                        presentedSheet = .settings
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.body.weight(.semibold))
                            .frame(width: 44, height: 44)
                            .background(.black.opacity(0.45), in: Circle())
                    }
                    .accessibilityLabel("Camera settings")
                }
                .foregroundStyle(.white)
                .padding()

                Spacer()

                cameraStateMessage

                cameraControls
            }
        }
    }

    private var cameraControls: some View {
        VStack(spacing: 20) {
            if camera.facing == .front, camera.supportsSmartSelfieFraming {
                Picker("Selfie framing", selection: Binding(
                    get: { camera.selfieFramingMode },
                    set: { camera.setSelfieFramingMode($0) }
                )) {
                    ForEach(SelfieFramingMode.allCases) { mode in
                        Label(
                            mode.title,
                            systemImage: mode == .portrait
                                ? "rectangle.portrait"
                                : "rectangle"
                        )
                        .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 260)
                .accessibilityHint("Changes the Center Stage photo orientation")
            } else {
                zoomControls
            }

            HStack {
                Color.clear
                    .frame(width: 54, height: 54)

                Spacer()

                Button {
                    saveThisPhoto = false
                    camera.capture()
                } label: {
                    ZStack {
                        Circle()
                            .stroke(.white, lineWidth: 4)
                            .frame(width: 78, height: 78)
                        Circle()
                            .fill(.white)
                            .frame(width: 66, height: 66)
                    }
                }
                .disabled(camera.state != .ready || camera.isCapturing)
                .accessibilityLabel("Take photo")

                Spacer()

                Button {
                    Task {
                        await camera.switchCamera()
                    }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath.camera.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 54, height: 54)
                        .background(.black.opacity(0.5), in: Circle())
                }
                .disabled(!camera.canSwitchCamera || camera.isSwitchingCamera)
                .accessibilityLabel("Switch camera")
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    private var zoomControls: some View {
        HStack(spacing: 8) {
            ForEach(camera.quickZoomFactors, id: \.self) { zoomFactor in
                Button {
                    camera.setZoomFactor(zoomFactor)
                } label: {
                    Text(formatZoom(zoomFactor))
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(
                            abs(camera.zoomFactor - zoomFactor) < 0.05 ? .yellow : .white
                        )
                        .frame(width: 42, height: 32)
                        .background(.black.opacity(0.5), in: Capsule())
                }
                .accessibilityLabel("Zoom \(formatZoom(zoomFactor))")
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
                        saveThisPhoto = false
                        camera.retake()
                    }
                    .buttonStyle(.borderedProminent)
                    Spacer()
                }
                .padding()

                Spacer()

                VStack(spacing: 14) {
                    saveToPhotosReviewOption

                    Button {
                        queueDraft(imageData: imageData)
                    } label: {
                        Label("Post Story", systemImage: "paperplane.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Text(
                        auth.session == nil
                            ? "Log Into the Atmosphere before posting."
                            : "This account has the upload and create-story permissions required to publish."
                    )
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

    @available(iOS 18.0, *)
    private func importLockedCameraCaptures() async {
        for await update in LockedCameraCaptureManager.shared.sessionContentUpdates {
            switch update {
            case let .initial(urls):
                for url in urls {
                    await importLockedCameraCapture(at: url)
                }
            case let .added(url):
                await importLockedCameraCapture(at: url)
            case .removed:
                break
            @unknown default:
                break
            }
        }
    }

    @available(iOS 18.0, *)
    private func importLockedCameraCapture(at directoryURL: URL) async {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        )) ?? []
        let imageFiles = files.filter {
            ["jpg", "jpeg"].contains($0.pathExtension.lowercased())
        }

        for fileURL in imageFiles {
            guard let data = try? Data(contentsOf: fileURL),
                  data.count <= FlashesStoryContract.maximumImageBytes
            else {
                continue
            }
            modelContext.insert(LocalStoryDraft(imageData: data))
        }

        guard !imageFiles.isEmpty else { return }
        do {
            try modelContext.save()
            try await LockedCameraCaptureManager.shared
                .invalidateSessionContent(at: directoryURL)
            feedbackMessage = imageFiles.count == 1
                ? "Camera Control capture saved as a pending story."
                : "\(imageFiles.count) Camera Control captures saved as pending stories."
        } catch {
            feedbackMessage = "Camera Control captures could not be imported: \(error.localizedDescription)"
        }
    }

    @ViewBuilder
    private var saveToPhotosReviewOption: some View {
        switch settings?.saveToPhotosPreference ?? .ask {
        case .always:
            Label("A copy will be saved to Photos", systemImage: "photo.badge.checkmark")
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .ask:
            Toggle("Save this photo", isOn: $saveThisPhoto)
        case .never:
            EmptyView()
        }
    }

    private func queueDraft(imageData: Data) {
        guard imageData.count <= FlashesStoryContract.maximumImageBytes else {
            feedbackMessage = "This image exceeds Flashes' 10 MiB story limit."
            return
        }
        guard auth.session?.canPublishStory == true else {
            presentedSheet = .account
            return
        }

        modelContext.insert(LocalStoryDraft(imageData: imageData))
        do {
            try modelContext.save()
        } catch {
            feedbackMessage = "The photo could not be saved as a pending story: \(error.localizedDescription)"
            return
        }

        let preference = settings?.saveToPhotosPreference ?? .ask
        if preference.shouldSave(whenAsked: saveThisPhoto) {
            Task {
                do {
                    try await PhotoLibrarySaver.save(jpegData: imageData)
                    feedbackMessage = "Story saved as a pending draft and copied to Photos. Your account is connected for publishing."
                } catch {
                    feedbackMessage = "Draft saved, but Photos failed: \(error.localizedDescription)"
                }
            }
        } else {
            feedbackMessage = "Story saved as a pending draft. Your account is connected for publishing."
        }
        saveThisPhoto = false
        camera.retake()
    }

    private func formatZoom(_ zoomFactor: Double) -> String {
        if zoomFactor.rounded() == zoomFactor {
            return "\(Int(zoomFactor))×"
        }
        return String(format: "%.1f×", zoomFactor)
    }
}

private enum CameraSheet: String, Identifiable {
    case settings
    case account

    var id: Self { self }
}

private struct CameraSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let settings: AppSettings

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(
                        "Save to Photos",
                        selection: Binding(
                            get: { settings.saveToPhotosPreference },
                            set: updateSavePreference
                        )
                    ) {
                        ForEach(SaveToPhotosPreference.allCases) { preference in
                            VStack(alignment: .leading) {
                                Text(preference.title)
                                Text(preference.explanation)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .tag(preference)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Save Captured Photos")
                } footer: {
                    Text("This controls whether posted photos are also added to your photo library.")
                }
            }
            .navigationTitle("Camera Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func updateSavePreference(_ preference: SaveToPhotosPreference) {
        settings.saveToPhotosPreference = preference
        try? modelContext.save()
    }
}

#Preview {
    CameraScreen()
        .modelContainer(for: [LocalStoryDraft.self, AppSettings.self], inMemory: true)
        .environment(OAuthSessionManager())
}
