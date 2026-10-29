import SwiftUI

struct AccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    let auth: OAuthSessionManager
    private let searchClient: AccountSearchClient

    @State private var identifier = ""
    @State private var suggestions: [AccountSuggestion] = []
    @State private var selectedSuggestion: AccountSuggestion?
    @State private var isSearching = false
    @FocusState private var isAccountFieldFocused: Bool

    init(
        auth: OAuthSessionManager,
        searchClient: AccountSearchClient = AccountSearchClient()
    ) {
        self.auth = auth
        self.searchClient = searchClient
    }

    var body: some View {
        NavigationStack {
            Form {
                if let session = auth.session {
                    connectedSection(session: session)
                } else {
                    signedOutSections
                }
            }
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task(id: identifier) {
                await updateSuggestions()
            }
            .sensoryFeedback(.success, trigger: auth.session != nil)
        }
    }

    @ViewBuilder
    private var signedOutSections: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "camera.aperture")
                    .font(.system(size: 42, weight: .medium))
                    .foregroundStyle(.tint)
                    .frame(width: 72, height: 72)
                    .background(.tint.opacity(0.12), in: Circle())

                Text("Logging Into the Atmosphere")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                Text("Find your account to start sharing photos with Presently.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .listRowBackground(Color.clear)
        }

        Section {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Name or username", text: identifierBinding)
                    .focused($isAccountFieldFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.username)
                    .submitLabel(.continue)
                    .onSubmit(connect)

                if isSearching {
                    ProgressView()
                        .controlSize(.small)
                } else if !identifier.isEmpty {
                    Button {
                        identifier = ""
                        selectedSuggestion = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear Search")
                }
            }

            if let errorMessage = auth.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Button(action: connect) {
                HStack {
                    Spacer()
                    if auth.isAuthorizing {
                        ProgressView()
                    } else {
                        Text("Continue").fontWeight(.semibold)
                    }
                    Spacer()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canContinue || auth.isAuthorizing)
        } footer: {
            Label("Your password stays with your account provider. Presently only asks to share photos you choose.", systemImage: "lock.fill")
                .font(.footnote)
        }

        if shouldShowSuggestions {
            Section("Account Suggestions") {
                ForEach(suggestions) { suggestion in
                    Button {
                        select(suggestion)
                    } label: {
                        AccountSuggestionRow(suggestion: suggestion)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func connectedSection(session: OAuthSession) -> some View {
        Section {
            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.green)

                VStack(spacing: 4) {
                    Text("You’re Connected")
                        .font(.title2.bold())
                    Text("@\(session.handle ?? session.accountDID)")
                        .font(.headline)
                    Text("Presently is ready when you are.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .listRowBackground(Color.clear)
        }

        Section {
            Button("Disconnect Account", role: .destructive) {
                Task {
                    await auth.signOut()
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var identifierBinding: Binding<String> {
        Binding(
            get: { identifier },
            set: { newValue in
                identifier = newValue
                if newValue != selectedSuggestion?.handle {
                    selectedSuggestion = nil
                }
            }
        )
    }

    private var cleanIdentifier: String {
        let value = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.hasPrefix("@") ? String(value.dropFirst()) : value
    }

    private var canContinue: Bool {
        selectedSuggestion != nil
            || cleanIdentifier.hasPrefix("did:")
            || cleanIdentifier.contains(".")
    }

    private var shouldShowSuggestions: Bool {
        selectedSuggestion == nil && !suggestions.isEmpty
    }

    private func select(_ suggestion: AccountSuggestion) {
        selectedSuggestion = suggestion
        identifier = suggestion.handle
        suggestions = []
        isAccountFieldFocused = false
    }

    private func updateSuggestions() async {
        let query = cleanIdentifier
        guard auth.session == nil,
              !auth.isAuthorizing,
              selectedSuggestion?.handle != query,
              query.count >= 2
        else {
            suggestions = []
            isSearching = false
            return
        }

        do {
            try await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            isSearching = true
            let results = try await searchClient.suggestions(for: query)
            guard !Task.isCancelled, cleanIdentifier == query else { return }
            suggestions = results
        } catch is CancellationError {
            return
        } catch {
            guard cleanIdentifier == query else { return }
            suggestions = []
        }
        isSearching = false
    }

    private func connect() {
        guard !cleanIdentifier.isEmpty else { return }
        isAccountFieldFocused = false
        Task {
            await auth.signIn(identifier: cleanIdentifier)
        }
    }
}

private struct AccountSuggestionRow: View {
    let suggestion: AccountSuggestion

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: suggestion.avatar) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 36, height: 36)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.displayName ?? suggestion.handle)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("@\(suggestion.handle)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Selects this account")
    }
}
