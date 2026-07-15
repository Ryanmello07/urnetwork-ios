//
//  LoginSeedphraseViewModel.swift
//  URnetwork
//

import Foundation
import URnetworkSdk

extension LoginSeedphraseView {

    @MainActor
    class ViewModel: ObservableObject {

        private let urApiService: UrApiServiceProtocol

        @Published var seedphrase: String = "" {
            didSet {
                errorMessage = nil
            }
        }

        @Published private(set) var isLoggingIn: Bool = false

        @Published private(set) var errorMessage: String?

        let domain = "LoginSeedphraseViewModel"

        init(urApiService: UrApiServiceProtocol) {
            self.urApiService = urApiService
        }

        var isSeedphraseValid: Bool {
            !seedphrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        func login() async -> AuthLoginResult {

            if isLoggingIn {
                return .failure(NSError(domain: domain, code: 0, userInfo: [NSLocalizedDescriptionKey: "Login already in progress"]))
            }

            guard isSeedphraseValid else {
                return .failure(NSError(domain: domain, code: 0, userInfo: [NSLocalizedDescriptionKey: "Seedphrase is empty"]))
            }

            isLoggingIn = true
            errorMessage = nil

            defer {
                isLoggingIn = false
            }

            do {
                let result = try await urApiService.loginWithSeedphrase(seedphrase: seedphrase)
                return result
            } catch {
                return .failure(error)
            }

        }

    }

}
