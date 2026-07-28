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
            ScrollView {
                if let session = auth.session {
                    connectedContent(session: session)
                } else {
                    signedOutContent
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGroupedBackground))
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
        }
    }

    private var signedOutContent: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                Image(systemName: "camera.aperture")
                    .font(.system(size: 38, weight: .medium))
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
            .padding(.horizontal)

            VStack(spacing: 12) {
                accountField

                if shouldShowSuggestions {
                    suggestionList
                }

                if let errorMessage = auth.errorMessage {
                    Label(
                        errorMessage,
                        systemImage: "exclamationmark.circle.fill"
                    )
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button(action: connect) {
                    Group {
                        if auth.isAuthorizing {
                            ProgressView()
                        } else {
                            Text("Continue")
                        }
                    }
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .frame(height: 24)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canContinue || auth.isAuthorizing)
            }

            Label {
                Text(
                    "Your password stays with your account provider. Presently only asks to share photos you choose."
                )
            } icon: {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.tint)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 16))
        }
        .padding(20)
    }

    private var accountField: some View {
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
                .accessibilityLabel("Clear Search")
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 52)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(.separator.opacity(0.45), lineWidth: 0.5)
        }
    }

    private var suggestionList: some View {
        VStack(spacing: 0) {
            ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                Button {
                    select(suggestion)
                } label: {
                    AccountSuggestionRow(suggestion: suggestion)
                }
                .buttonStyle(.plain)

                if index < suggestions.count - 1 {
                    Divider()
                        .padding(.leading, 62)
                }
            }
        }
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func connectedContent(session: OAuthSession) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            VStack(spacing: 8) {
                Text("You’re Connected")
                    .font(.title2.bold())
                Text("@\(session.handle ?? session.accountDID)")
                    .font(.headline)
                Text("Presently is ready when you are.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)

            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)

            Button("Disconnect Account", role: .destructive) {
                Task {
                    await auth.signOut()
                }
            }
            .font(.footnote)
        }
        .padding(24)
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
            .frame(width: 40, height: 40)
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
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Selects this account")
    }
}
