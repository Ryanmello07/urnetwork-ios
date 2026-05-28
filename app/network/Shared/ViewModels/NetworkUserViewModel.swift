//
//  NetworkUserViewModel.swift
//  URnetwork
//
//  Created by Stuart Kuentzel on 2025/01/11.
//

import Foundation
import URnetworkSdk

@MainActor
class NetworkUserViewModel: ObservableObject {
    
    @Published private(set) var networkUser: SdkNetworkUser?
    
    @Published private(set) var isFetchingNetworkUser: Bool = false
    
    private var api: SdkApi
    
    init(api: SdkApi) {
        self.api = api
        self.initializeNetworkUser()
    }
    
    func initializeNetworkUser() {
        Task {
            await refreshNetworkUser()
        }
    }
    
    func refreshNetworkUser() async -> Result<Void, Error> {
        
        if isFetchingNetworkUser {
            return .failure(FetchNetworkUserError.isFetchingNetworkUser)
        }
        
        isFetchingNetworkUser = true
        
        do {
            let networkUser: SdkNetworkUser = try await withCheckedThrowingContinuation { continuation in
                
                let callback = GetNetworkUserCallback { result, err in
                    
                    if let err = err {
                        continuation.resume(throwing: err)
                        return
                    }
                    
                    guard let result = result else {
                        continuation.resume(throwing: FetchNetworkUserError.networkUserNotFound)
                        return
                    }

                    if let resultError = result.error {
                        continuation.resume(throwing: NSError(domain: "NetworkUserViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: resultError.message]))
                        return
                    }

                    guard let networkUser = result.networkUser else {
                        continuation.resume(throwing: FetchNetworkUserError.networkUserNotFound)
                        return
                    }
                    
                    continuation.resume(returning: networkUser)
                    
                }
                
                api.getNetworkUser(callback)
                
            }
            
            self.networkUser = networkUser
            self.isFetchingNetworkUser = false

            return .success(())

        } catch(let error) {
            self.isFetchingNetworkUser = false
            return .failure(error)
        }
        
    }
    
}

private class GetNetworkUserCallback: SdkCallback<SdkGetNetworkUserResult, SdkGetNetworkUserCallbackProtocol>, SdkGetNetworkUserCallbackProtocol {
    func result(_ result: SdkGetNetworkUserResult?, err: Error?) {
        handleResult(result, err: err)
    }
}

enum FetchNetworkUserError: Error {
    case networkUserNotFound
    case isFetchingNetworkUser
}
