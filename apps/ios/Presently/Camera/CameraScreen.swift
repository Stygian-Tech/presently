import PresentlyKit
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
    @State private var capturedViewportAspectRatio: Double?
    @State private var isPublishing = false
    @State private var activeDraft: LocalStoryDraft?
    @State private var editor: StoryEditorSession?
    @Environment(\.scenePhase) private var scenePhase

    private var settings: AppSettings? {
        storedSettings.first
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let editor {
                review(editor: editor)
            } else {
                liveCamera
            }
        }
        .task {
            ensureSettingsExist()
            restoreDraft()
            let defaultCamera = settings?.defaultCamera ?? .back
            if #available(iOS 18.0, *) {
                try? await PresentlyCaptureIntent.updateAppContext(
                    PresentlyCaptureContext(
                        facing: defaultCamera.captureFacing
                    )
                )
            }
            await camera.start(
                preferredFacing: defaultCamera.cameraFacing
            )
        }
        .onChange(of: camera.capturedPhotoData) { _, data in
            guard let data else { return }
            beginDraft(data: data)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active, let editor {
                editor.endTransform()
                persistComposition(editor.composition)
            }
        }
        .onChange(of: settings?.defaultCamera) { _, preference in
            guard let preference else { return }
            Task {
                await camera.switchCamera(to: preference.cameraFacing)
            }
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
        CameraViewfinder(camera: camera, onCapture: capturePhoto)
            .overlay(alignment: .top) {
                CameraHeader(
                    isConnected: auth.session != nil,
                    openAccount: { presentedSheet = .account },
                    openSettings: { presentedSheet = .settings }
                )
            }
    }

    private func review(editor: StoryEditorSession) -> some View {
        VStack(spacing: 0) {
            StoryEditorView(session: editor, isEditable: !isPublishing && activeDraft?.recordKey == nil, onError: {
                feedbackMessage = $0
            })
            VStack(spacing: 14) {
                saveToPhotosReviewOption
                HStack {
                    Button("Discard", systemImage: "xmark", role: .cancel) { discardDraft() }
                        .disabled(isPublishing || !editor.canFinishEditing)
                    Spacer()
                    if isPublishing { ProgressView().tint(.white) }
                    Button(isPublishing ? "Posting…" : "Post Photo", systemImage: "checkmark") {
                        Task { await prepareAndPublish() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(isPublishing || !editor.canFinishEditing)
                }
            }
            .padding()
            .background(.regularMaterial)
        }
        .preferredColorScheme(.dark)
    }

    private func attachEditor(to draft: LocalStoryDraft) throws {
        draft.preserveOriginalForEditing()
        let session = try StoryEditorSession(photoData: draft.originalImageData ?? draft.imageData, recipe: draft.editorData)
        activeDraft = draft
        session.onChange = { composition in persistComposition(composition) }
        editor = session
    }

    private func capturePhoto(viewportAspectRatio: Double?) {
        guard camera.state == .ready, !camera.isCapturing else { return }
        saveThisPhoto = false
        capturedViewportAspectRatio = viewportAspectRatio
        camera.capture()
    }

    private func beginDraft(data: Data) {
        // A new camera capture owns a new draft; originals are never replaced by the flattened export.
        do {
            let draft = LocalStoryDraft(imageData: data)
            draft.originalImageData = data
            draft.editorData = try StoryComposition(usesStoryCrop: true, captureViewportAspectRatio: capturedViewportAspectRatio).encoded()
            try attachEditor(to: draft)
            modelContext.insert(draft)
            try modelContext.save()
        } catch { feedbackMessage = "Could not save your draft: \(error.localizedDescription)" }
    }

    private func restoreDraft() {
        guard editor == nil else { return }
        do {
            let descriptor = FetchDescriptor<LocalStoryDraft>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
            if let draft = try modelContext.fetch(descriptor).first(where: { $0.state != .published }) {
                if draft.state == .publishing { draft.state = .failed }
                try attachEditor(to: draft)
                try modelContext.save()
                return
            }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--editor-demo") {
                let renderer = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 1200))
                let image = renderer.image { context in
                    UIColor.systemTeal.setFill(); context.fill(CGRect(x: 0, y: 0, width: 900, height: 1200))
                    UIColor.systemIndigo.setFill(); context.fill(CGRect(x: 0, y: 750, width: 900, height: 450))
                }
                if let data = image.jpegData(compressionQuality: 0.9) { beginDraft(data: data) }
            }
            #endif
        } catch { feedbackMessage = "Could not restore your pending photo: \(error.localizedDescription)" }
    }

    private func persistComposition(_ composition: StoryComposition) {
        guard let draft = activeDraft, draft.recordKey == nil else { return }
        do {
            draft.editorData = try composition.encoded()
            try modelContext.save()
        } catch { feedbackMessage = "Your latest edits could not be saved: \(error.localizedDescription)" }
    }

    private func discardDraft() {
        if let draft = activeDraft { modelContext.delete(draft) }
        do { try modelContext.save() }
        catch { feedbackMessage = "Could not discard your draft: \(error.localizedDescription)"; return }
        activeDraft = nil
        editor = nil
        saveThisPhoto = false
        camera.retake()
    }

    @MainActor
    private func prepareAndPublish() async {
        guard let editor, let draft = activeDraft, editor.canFinishEditing, !isPublishing else { return }
        guard auth.session?.canPublishStory == true else { presentedSheet = .account; return }
        do {
            if draft.recordKey == nil {
                draft.editorData = try editor.composition.encoded()
                draft.imageData = try StoryRenderer.jpeg(photo: editor.photo, composition: editor.composition, maximumBytes: FlashesStoryContract.maximumImageBytes)
                try modelContext.save()
            }
            await publishStory(imageData: draft.imageData)
        } catch { feedbackMessage = "Could not prepare your photo: \(error.localizedDescription)" }
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

    @MainActor
    private func publishStory(imageData: Data) async {
        guard imageData.count <= FlashesStoryContract.maximumImageBytes else {
            feedbackMessage = "This image exceeds Flashes' 10 MiB story limit."
            return
        }
        guard auth.session?.canPublishStory == true else {
            presentedSheet = .account
            return
        }

        let draft: LocalStoryDraft
        if let activeDraft {
            draft = activeDraft
            draft.state = .publishing
            draft.lastError = nil
            if draft.recordKey == nil { draft.recordKey = ATProtoTID.make() }
        } else {
            draft = LocalStoryDraft(
                imageData: imageData,
                state: .publishing,
                recordKey: ATProtoTID.make()
            )
            activeDraft = draft
            modelContext.insert(draft)
        }
        do {
            try modelContext.save()
        } catch {
            feedbackMessage = "The photo could not be saved as a pending story: \(error.localizedDescription)"
            return
        }

        guard let recordKey = draft.recordKey else {
            draft.state = .failed
            draft.lastError = "The story is missing its publication key."
            try? modelContext.save()
            feedbackMessage = draft.lastError
            return
        }

        isPublishing = true
        defer { isPublishing = false }
        do {
            let published = try await auth.publishStory(
                jpegData: imageData,
                createdAt: draft.createdAt,
                recordKey: recordKey
            )
            draft.state = .published
            draft.publishedURI = published.uri
            draft.publishedCID = published.cid
            draft.lastError = nil
            try modelContext.save()

            let preference = settings?.saveToPhotosPreference ?? .ask
            if preference.shouldSave(whenAsked: saveThisPhoto) {
                do {
                    try await PhotoLibrarySaver.save(jpegData: imageData)
                    feedbackMessage = "Your story is live and saved to Photos."
                } catch {
                    feedbackMessage = "Your story is live, but it could not be saved to Photos."
                }
            } else {
                feedbackMessage = "Your story is live."
            }
            activeDraft = nil
            editor = nil
            saveThisPhoto = false
            camera.retake()
        } catch {
            draft.state = .failed
            draft.lastError = error.localizedDescription
            try? modelContext.save()
            feedbackMessage =
                "Your story couldn’t be posted. \(error.localizedDescription) Tap the checkmark to try again."
        }
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

                Section {
                    Picker(
                        "Default Camera",
                        selection: Binding(
                            get: { settings.defaultCamera },
                            set: updateDefaultCamera
                        )
                    ) {
                        ForEach(DefaultCameraPreference.allCases) { preference in
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
                    Text("Default Camera")
                } footer: {
                    Text("The camera switch button still changes cameras for the current session.")
                }

                Section {
                    Link(destination: PresentlyLinks.feedbackBoard) {
                        Label("Open Feedback Board", systemImage: "arrow.up.right.square")
                    }
                    .accessibilityHint("Opens the public Presently board on UserInput")
                } header: {
                    Text("Feedback")
                } footer: {
                    Text("Report a bug, request a feature, ask a question, or leave a comment.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func updateSavePreference(_ preference: SaveToPhotosPreference) {
        settings.saveToPhotosPreference = preference
        try? modelContext.save()
    }

    private func updateDefaultCamera(_ preference: DefaultCameraPreference) {
        settings.defaultCamera = preference
        try? modelContext.save()
        guard #available(iOS 18.0, *) else { return }
        Task {
            try? await PresentlyCaptureIntent.updateAppContext(
                PresentlyCaptureContext(facing: preference.captureFacing)
            )
        }
    }
}

private extension DefaultCameraPreference {
    var cameraFacing: CameraController.Facing {
        switch self {
        case .back:
            .back
        case .front:
            .front
        }
    }

    var captureFacing: PresentlyCaptureFacing {
        switch self {
        case .back:
            .back
        case .front:
            .front
        }
    }
}

#Preview {
    CameraScreen()
        .modelContainer(for: [LocalStoryDraft.self, AppSettings.self], inMemory: true)
        .environment(OAuthSessionManager())
}

private struct CameraHeader: View {
    let isConnected: Bool
    let openAccount: () -> Void
    let openSettings: () -> Void

    var body: some View {
        HStack {
            Text("Presently")
                .font(.headline)
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .modifier(PresentlyControlSurface())
            Spacer()
            Button(action: openAccount) {
                Label(
                    isConnected ? "Connected account" : "Connect account",
                    systemImage: isConnected
                        ? "person.crop.circle.fill.badge.checkmark"
                        : "person.crop.circle"
                )
            }
            Button("Settings", systemImage: "gearshape", action: openSettings)
        }
        .labelStyle(.iconOnly)
        .modifier(PresentlyGlassButtonStyle())
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .foregroundStyle(.white)
        .padding()
        .environment(\.colorScheme, .dark)
    }
}
