import AuthenticationServices
import Observation
import SwiftUI

@MainActor
@Observable
final class OAuthSessionManager {
    enum State {
        case signedOut
        case authorizing
        case signedIn(OAuthSession)
        case failed(String)
    }

    private(set) var state: State = .signedOut
    private let client: ATProtoOAuthClient
    private let webAuthentication: SystemWebAuthentication

    init(client: ATProtoOAuthClient = ATProtoOAuthClient()) {
        self.client = client
        webAuthentication = SystemWebAuthentication()
        Task {
            await restore()
        }
    }

    var session: OAuthSession? {
        if case let .signedIn(session) = state {
            return session
        }
        return nil
    }

    var isAuthorizing: Bool {
        if case .authorizing = state { return true }
        return false
    }

    var errorMessage: String? {
        if case let .failed(message) = state { return message }
        return nil
    }

    func signIn(identifier: String) async {
        state = .authorizing
        do {
            let authorizationURL = try await client.prepareAuthorization(
                identifier: identifier
            )
            let callbackURL = try await webAuthentication.start(
                url: authorizationURL,
                callbackScheme: PresentlyOAuthConfiguration.callbackScheme
            )
            let session = try await client.completeAuthorization(
                callbackURL: callbackURL
            )
            state = .signedIn(session)
        } catch is CancellationError {
            await restore()
        } catch let error as ASWebAuthenticationSessionError
            where error.code == .canceledLogin {
            await restore()
        } catch {
            state = .failed(Self.userFacingMessage(for: error))
        }
    }

    func handleCallback(_ url: URL) async {
        guard url.scheme == PresentlyOAuthConfiguration.callbackScheme else {
            return
        }
        guard !webAuthentication.isRunning else {
            return
        }
        state = .authorizing
        do {
            state = .signedIn(
                try await client.completeAuthorization(callbackURL: url)
            )
        } catch {
            state = .failed(Self.userFacingMessage(for: error))
        }
    }

    func refreshIfNeeded() async {
        guard session != nil else { return }
        do {
            state = .signedIn(try await client.validSession())
        } catch {
            state = .failed(Self.userFacingMessage(for: error))
        }
    }

    func signOut() async {
        do {
            try await client.signOut()
            state = .signedOut
        } catch {
            state = .failed(Self.userFacingMessage(for: error))
        }
    }

    private func restore() async {
        do {
            if let session = try await client.currentSession() {
                state = .signedIn(session)
                await refreshIfNeeded()
            } else {
                state = .signedOut
            }
        } catch {
            state = .failed(Self.userFacingMessage(for: error))
        }
    }

    nonisolated static func userFacingMessage(for error: Error) -> String {
        if let validationError = error as? OAuthValidationError,
           validationError == .clientMetadataOutOfDate {
            return validationError.localizedDescription
        }
        return "We couldn’t connect that account. Check the username and try again."
    }
}

@MainActor
final class SystemWebAuthentication: NSObject,
    ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    var isRunning: Bool { session != nil }

    func start(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { [weak self] callbackURL, error in
                self?.session = nil
                if let error {
                    continuation.resume(throwing: error)
                } else if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(
                        throwing: OAuthValidationError.invalidCallback
                    )
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            guard session.start() else {
                self.session = nil
                continuation.resume(
                    throwing: OAuthValidationError.invalidCallback
                )
                return
            }
        }
    }

    func presentationAnchor(
        for session: ASWebAuthenticationSession
    ) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        return scenes
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}
