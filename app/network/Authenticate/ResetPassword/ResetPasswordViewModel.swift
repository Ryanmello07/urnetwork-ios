//
//  ResetPasswordViewModel.swift
//  URnetwork
//
//  Created by Stuart Kuentzel on 2024/12/07.
//

import Foundation
import URnetworkSdk

enum SendPasswordResetError: Error {
    case inProgress
}


extension ResetPasswordView {
    
    @MainActor
    class ViewModel: ObservableObject {

        private var api: SdkApi

        @Published var sendInProgress: Bool = false
        
        let domain = "ResetPasswordViewModel"
        
        init(api: SdkApi) {
            self.api = api
        }
        
        func sendResetLink(_ userAuth: String) async -> Result<Void, Error> {
            
            if sendInProgress {
                return .failure(SendPasswordResetError.inProgress)
            }
            
            self.sendInProgress = true

            do {

                let result: Void = try await withCheckedThrowingContinuation { continuation in
                    
                    let callback = AuthPasswordResetCallback { result, error in
                        
                        if let err = error {
                            continuation.resume(throwing: err)
                            return
                        }
                        
                        guard let result = result else {
                            continuation.resume(throwing: NSError(domain: "ResetPasswordViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "No result found"]))
                            
                            return
                        }
                        
                        return continuation.resume(returning: ())
                        
                    }
                    
                    
                    let args = SdkAuthPasswordResetArgs()
                    args.userAuth = userAuth
                    
                    self.api.authPasswordReset(args, callback: callback)
                    
                }
                
                self.sendInProgress = false

                return .success(result)

            } catch(let error) {
                self.sendInProgress = false
                return .failure(error)
            }
            
        }
        
    }
    
}

private class AuthPasswordResetCallback: SdkCallback<SdkAuthPasswordResetResult, SdkAuthPasswordResetCallbackProtocol>, SdkAuthPasswordResetCallbackProtocol {
    func result(_ result: SdkAuthPasswordResetResult?, err: Error?) {
        handleResult(result, err: err)
    }
}
