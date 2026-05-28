//
//  VPNManager.swift
//  URnetwork
//
//  Created by Stuart Kuentzel on 2024/12/20.
//

import Foundation
import NetworkExtension
import URnetworkSdk
import Network
import Combine
#if os(iOS)
import BackgroundTasks
#endif

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

//enum TunnelRequestStatus {
//    case started
//    case stopped
//    case none
//}

let TunnelCheckTimeout: TimeInterval = 10
private let TunnelLogoutProviderMessage = Data("logout".utf8)

private struct VPNManagerOperationError: LocalizedError {
    let operation: String
    let underlyingError: Error

    var errorDescription: String? {
        "[VPNManager][\(operation)] \(underlyingError.localizedDescription)"
    }
}

private func makeVPNManagerError(_ description: String, code: Int = 0) -> NSError {
    NSError(
        domain: "VPNManager",
        code: code,
        userInfo: [NSLocalizedDescriptionKey: description]
    )
}

private final class VPNUpdateWaiter {
    private let lock = NSLock()
    private var didResume = false
    private let continuation: CheckedContinuation<Result<Void, Error>, Never>

    init(_ continuation: CheckedContinuation<Result<Void, Error>, Never>) {
        self.continuation = continuation
    }

    func resume(_ result: Result<Void, Error>) {
        lock.lock()
        guard !didResume else {
            lock.unlock()
            return
        }
        didResume = true
        lock.unlock()

        continuation.resume(returning: result)
    }
}

@MainActor
class VPNManager: ObservableObject {
    
    var device: SdkDeviceRemote
    @Published private(set) var lastError: Error?
    
//    var tunnelRequestStatus: TunnelRequestStatus = .none
    
    private var routeLocalSub: SdkSubProtocol?
    
    private var deviceOfflineSub: SdkSubProtocol?
    
    private var deviceConnectSub: SdkSubProtocol?
    
//    var deviceRemoteSub: SdkSubProtocol?
    
    private var tunnelSub: SdkSubProtocol?
    
    private var deviceProvideSub: SdkSubProtocol?
    private var deviceProvidePausedSub: SdkSubProtocol?
    
//    private var tunnelStarted: Bool = false
    private var tunnelInstance: Int = 0
    
    var contractStatusSub: SdkSubProtocol?
    
    let monitor = NWPathMonitor()
    let queue = DispatchQueue(label: "NetworkMonitor")
    
    
    init(device: SdkDeviceRemote) {
        print("[VPNManager]init")
        self.device = device
        
        self.monitor.start(queue: queue)
        
        self.routeLocalSub = device.add(RouteLocalChangeListener { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateVpnService()
            }
        })
             
        self.deviceOfflineSub = device.add(OfflineChangeListener { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.updateVpnService()
            }
        })
        
        self.deviceConnectSub = device.add(ConnectChangeListener { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateVpnService()
            }
        })
        
//        self.tunnelSub = device.add(TunnelChangeListener { [weak self] _ in
//            DispatchQueue.main.async {
//                self?.updateTunnel()
//            }
//        })
        
//        self.contractStatusSub = device.add(ContractStatusChangeListener { [weak self] _ in
//            DispatchQueue.main.async {
//                self?.updateContractStatus()
//            }
//        })
        
        self.deviceProvidePausedSub = device.add(ProvidePausedChangeListener { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateVpnService()
            }
        })
        
        self.deviceProvideSub = device.add(ProvideChangeListener { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateVpnService()
            }
        })
        
//        updateTunnel()
//        updateContractStatus()
        
        DispatchQueue.main.async {
            self.updateVpnService()
        }
    }
    
    #if os(iOS)
    func scheduleBackgroundUpdate() {
       let request = BGAppRefreshTaskRequest(identifier: "network.ur.update-tunnel")
       request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)

       do {
          try BGTaskScheduler.shared.submit(request)
       } catch {
          print("Could not schedule background update: \(error)")
       }
    }
    
    func handleBackgroundUpdate(task: BGTask) {
        task.setTaskCompleted(success: true)
    }
    #endif
    
    
    
//    deinit {
//        print("VPN Manager deinit")
//        
//        self.close()
//    }
    
    func close() {
        self.tunnelInstance += 1
        self.monitor.cancel()
        self.setIdleTimerDisabled(false)
        
        self.routeLocalSub?.close()
        self.routeLocalSub = nil
        
        self.deviceOfflineSub?.close()
        self.deviceOfflineSub = nil
        
        self.deviceConnectSub?.close()
        self.deviceConnectSub = nil
        
//        self.deviceRemoteSub?.close()
//        self.deviceRemoteSub = nil
        
        self.tunnelSub?.close()
        self.tunnelSub = nil
        
        self.contractStatusSub?.close()
        self.contractStatusSub = nil
        
        self.deviceProvideSub?.close()
        self.deviceProvideSub = nil
        
        self.deviceProvidePausedSub?.close()
        self.deviceProvidePausedSub = nil
    }
    
    
    private func getPasswordReference() -> Data? {
        // Retrieve the password reference from the keychain
        return nil
    }
    
    
//    private func updateTunnel() {
//        let tunnelStarted = self.device.getTunnelStarted()
//        print("[VPNManager][tunnel]started=\(tunnelStarted)")
//    }
    
//    private func updateContractStatus() {
//        if let contractStatus = self.device.getContractStatus() {
//            print("[VPNManager][contract]insufficent=\(contractStatus.insufficientBalance) nopermission=\(contractStatus.noPermission) premium=\(contractStatus.premium)")
//        } else {
//            print("[VPNManager][contract]no contract status")
//        }
//    }
    
    func updateVpnService() {
        updateVpnService(completion: nil)
    }

    func updateVpnServiceAndWait(timeout: TimeInterval = 30) async -> Result<Void, Error> {
        let expectedTunnelStarted = device.getProvideEnabled() || device.getConnectEnabled() || !device.getRouteLocal()

        let updateResult: Result<Void, Error> = await withCheckedContinuation { continuation in
            let waiter = VPNUpdateWaiter(continuation)

            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                waiter.resume(.failure(makeVPNManagerError("Timed out updating VPN service", code: 5)))
            }

            updateVpnService { error in
                if let error {
                    waiter.resume(.failure(error))
                } else {
                    waiter.resume(.success(()))
                }
            }
        }

        if case .failure = updateResult {
            return updateResult
        }

        return await waitForTunnelState(started: expectedTunnelStarted, timeout: timeout)
    }

    private func waitForTunnelState(started: Bool, timeout: TimeInterval) async -> Result<Void, Error> {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if device.getTunnelStarted() == started {
                return .success(())
            }

            if let lastError {
                return .failure(lastError)
            }

            try? await Task.sleep(nanoseconds: 250_000_000)
        }

        if let lastError {
            return .failure(lastError)
        }

        let operation = started ? "start" : "stop"
        return .failure(makeVPNManagerError("Timed out waiting for VPN tunnel to \(operation)", code: 6))
    }

    private func updateVpnService(completion: ((Error?) -> Void)?) {
        #if os(iOS)
        scheduleBackgroundUpdate()
        #endif
        updateVpnServiceWithReset(index: 0, reset: false, completion: completion)
    }
    
    private func updateVpnServiceWithReset(index: Int, reset: Bool, completion: ((Error?) -> Void)? = nil) {
        let provideEnabled = device.getProvideEnabled()
        let connectEnabled = device.getConnectEnabled()
        let routeLocal = device.getRouteLocal()
        let providePaused = device.getProvidePaused()
        let provideMode = device.getProvideMode()
        let provideControlMode = device.getProvideControlMode()
        
        print("provideEnabled is: \(provideEnabled)")
        print("connect enabled: \(connectEnabled)")
        print("routeLocal is: \(routeLocal)")
        print("provideMode is: \(provideMode)")
        print("provideControlMode is: \(provideControlMode)")
        
        if (provideEnabled || connectEnabled || !routeLocal) {
            print("[VPNManager]start")
            print("[VPNManager]start")
            
            // if provide paused, keep the vpn on but do not keep the locks
            setIdleTimerDisabled(!providePaused)
            
            self.startVpnTunnel(index: index, reset: reset, completion: completion)
            
        } else {
            print("[VPNManager]stop")

            self.setIdleTimerDisabled(false)
            
            self.stopVpnTunnel(index: index, reset: reset, completion: completion)
        }
    }
    
    private func setIdleTimerDisabled(_ disabled: Bool) {
        // see https://developer.apple.com/documentation/uikit/uiapplication/isidletimerdisabled
        #if canImport(UIKit)
        UIApplication.shared.isIdleTimerDisabled = disabled
        #elseif canImport(AppKit)
        ProcessInfo.processInfo.automaticTerminationSupportEnabled = !disabled
        #endif
    }

    private func clearVpnError() {
        lastError = nil
    }

    @discardableResult
    private func reportVpnError(_ error: Error, operation: String, tunnelInstance: Int) -> Error? {
        guard tunnelInstance == self.tunnelInstance else { return nil }

        let wrappedError = VPNManagerOperationError(operation: operation, underlyingError: error)
        lastError = wrappedError
        setIdleTimerDisabled(false)
        print(wrappedError.localizedDescription)
        return wrappedError
    }

    private func failVpnUpdate(
        _ error: Error,
        operation: String,
        tunnelInstance: Int,
        completion: ((Error?) -> Void)?
    ) {
        completion?(reportVpnError(error, operation: operation, tunnelInstance: tunnelInstance) ?? error)
    }

    private func retryStartOrReport(
        _ error: Error,
        operation: String,
        index: Int,
        reset: Bool,
        managerCount: Int,
        tunnelInstance: Int,
        completion: ((Error?) -> Void)?
    ) {
        guard tunnelInstance == self.tunnelInstance else { return }

        if !reset {
            print("[VPNManager][\(operation)] \(error.localizedDescription); retrying after reset")
            updateVpnServiceWithReset(index: index, reset: true, completion: completion)
        } else if index + 1 < managerCount {
            print("[VPNManager][\(operation)] \(error.localizedDescription); trying next VPN profile")
            updateVpnServiceWithReset(index: index + 1, reset: false, completion: completion)
        } else {
            completion?(reportVpnError(error, operation: operation, tunnelInstance: tunnelInstance) ?? error)
        }
    }

    private func retryStopOrReport(
        _ error: Error,
        operation: String,
        index: Int,
        reset: Bool,
        managerCount: Int,
        tunnelInstance: Int,
        completion: ((Error?) -> Void)?
    ) {
        guard tunnelInstance == self.tunnelInstance else { return }

        if !reset {
            print("[VPNManager][\(operation)] \(error.localizedDescription); retrying after reset")
            updateVpnServiceWithReset(index: index, reset: true, completion: completion)
        } else if index + 1 < managerCount {
            print("[VPNManager][\(operation)] \(error.localizedDescription); trying next VPN profile")
            updateVpnServiceWithReset(index: index + 1, reset: false, completion: completion)
        } else {
            completion?(reportVpnError(error, operation: operation, tunnelInstance: tunnelInstance) ?? error)
        }
    }
    
    
    private func startVpnTunnel(index: Int, reset: Bool, completion: ((Error?) -> Void)? = nil) {
//        if tunnelStarted {
//            return
//        }
//        tunnelStarted = true
        self.tunnelInstance += 1
        let tunnelInstance = self.tunnelInstance
        
        // Load all configurations first
        NETunnelProviderManager.loadAllFromPreferences { [weak self] (managers, error) in
            DispatchQueue.main.async {
                guard let self = self, tunnelInstance == self.tunnelInstance else { return }
                if let error {
                    self.failVpnUpdate(
                        error,
                        operation: "start.loadAllFromPreferences",
                        tunnelInstance: tunnelInstance,
                        completion: completion
                    )
                    return
                }

                let device = self.device

                var tunnelManager: NETunnelProviderManager
                var n: Int
                if let managers = managers {
                    n = managers.count
                    tunnelManager = index < n ? managers[index] : NETunnelProviderManager()
                } else {
                    n = 0
                    tunnelManager = NETunnelProviderManager()
                }

                let startTunnel = {
                    guard tunnelInstance == self.tunnelInstance else { return }

                    guard let networkSpace = device.getNetworkSpace() else {
                        self.failVpnUpdate(
                            makeVPNManagerError("Missing network space", code: 1),
                            operation: "start.buildProviderConfiguration",
                            tunnelInstance: tunnelInstance,
                            completion: completion
                        )
                        return
                    }

                    var err: NSError?
                    let networkSpaceJson = networkSpace.toJson(&err)
                    if let err {
                        self.failVpnUpdate(
                            err,
                            operation: "start.networkSpaceToJson",
                            tunnelInstance: tunnelInstance,
                            completion: completion
                        )
                        return
                    }
                    guard !networkSpaceJson.isEmpty else {
                        self.failVpnUpdate(
                            makeVPNManagerError("Network space JSON is empty", code: 2),
                            operation: "start.buildProviderConfiguration",
                            tunnelInstance: tunnelInstance,
                            completion: completion
                        )
                        return
                    }
                    guard let byJwt = device.getApi()?.getByJwt(), !byJwt.isEmpty else {
                        self.failVpnUpdate(
                            makeVPNManagerError("Missing by_jwt", code: 3),
                            operation: "start.buildProviderConfiguration",
                            tunnelInstance: tunnelInstance,
                            completion: completion
                        )
                        return
                    }
                    guard let instanceId = device.getInstanceId()?.string(), !instanceId.isEmpty else {
                        self.failVpnUpdate(
                            makeVPNManagerError("Missing instance_id", code: 4),
                            operation: "start.buildProviderConfiguration",
                            tunnelInstance: tunnelInstance,
                            completion: completion
                        )
                        return
                    }

                    let tunnelProtocol = NETunnelProviderProtocol()
                    tunnelProtocol.serverAddress = networkSpace.getHostName()
                    tunnelProtocol.providerBundleIdentifier = "network.ur.extension"
                    tunnelProtocol.disconnectOnSleep = false
                    tunnelProtocol.excludeLocalNetworks = true
                    tunnelProtocol.excludeCellularServices = true
                    tunnelProtocol.excludeAPNs = true
                    if #available(iOS 17.4, macOS 14.4, *) {
                        tunnelProtocol.excludeDeviceCommunication = true
                    }

                    tunnelProtocol.providerConfiguration = [
                        "by_jwt": byJwt,
                        "rpc_public_key": "test",
                        "network_space": networkSpaceJson,
                        "instance_id": instanceId,
                    ]

                    tunnelManager.protocolConfiguration = tunnelProtocol
                    tunnelManager.localizedDescription = "URnetwork [\(networkSpace.getHostName()) \(networkSpace.getEnvName())]"
                    tunnelManager.isEnabled = true
                    tunnelManager.isOnDemandEnabled = false
                    let connectRule = NEOnDemandRuleConnect()
                    connectRule.interfaceTypeMatch = NEOnDemandRuleInterfaceType.any
                    tunnelManager.onDemandRules = [connectRule]

                    tunnelManager.saveToPreferences { [weak self] error in
                        DispatchQueue.main.async {
                            guard let self = self, tunnelInstance == self.tunnelInstance else { return }
                            if let error {
                                self.retryStartOrReport(
                                    error,
                                    operation: "start.saveToPreferences",
                                    index: index,
                                    reset: reset,
                                    managerCount: n,
                                    tunnelInstance: tunnelInstance,
                                    completion: completion
                                )
                                return
                            }

                            tunnelManager.loadFromPreferences { [weak self] error in
                                DispatchQueue.main.async {
                                    guard let self = self, tunnelInstance == self.tunnelInstance else { return }
                                    if let error {
                                        self.retryStartOrReport(
                                            error,
                                            operation: "start.loadFromPreferences",
                                            index: index,
                                            reset: reset,
                                            managerCount: n,
                                            tunnelInstance: tunnelInstance,
                                            completion: completion
                                        )
                                        return
                                    }

                                    do {
                                        try tunnelManager.connection.startVPNTunnel()
                                        self.clearVpnError()
                                        device.sync()
                                        completion?(nil)

                                        if !reset || index+1<n {
                                            DispatchQueue.main.asyncAfter(deadline: .now() + TunnelCheckTimeout) {
                                                if tunnelInstance == self.tunnelInstance && !device.getTunnelStarted() {
                                                    if !reset {
                                                        self.updateVpnServiceWithReset(index: index, reset: true)
                                                    } else if index+1<n {
                                                        self.updateVpnServiceWithReset(index: index+1, reset: false)
                                                    }
                                                }
                                            }
                                        }
                                    } catch {
                                        self.retryStartOrReport(
                                            error,
                                            operation: "start.startVPNTunnel",
                                            index: index,
                                            reset: reset,
                                            managerCount: n,
                                            tunnelInstance: tunnelInstance,
                                            completion: completion
                                        )
                                    }
                                }
                            }
                        }
                    }
                }

                if reset {
                    tunnelManager.removeFromPreferences() { [weak self] error in
                        DispatchQueue.main.async {
                            guard let self = self, tunnelInstance == self.tunnelInstance else { return }
                            if let error {
                                self.retryStartOrReport(
                                    error,
                                    operation: "start.removeFromPreferences",
                                    index: index,
                                    reset: reset,
                                    managerCount: n,
                                    tunnelInstance: tunnelInstance,
                                    completion: completion
                                )
                                return
                            }
                            startTunnel()
                        }
                    }
                } else {
                    startTunnel()
                }
            }
        }
    }

    private func stopVpnTunnel(index: Int, reset: Bool, completion: ((Error?) -> Void)? = nil) {
        self.tunnelInstance += 1
        let tunnelInstance = self.tunnelInstance

        NETunnelProviderManager.loadAllFromPreferences { [weak self] (managers, error) in
            DispatchQueue.main.async {
                guard let self = self, tunnelInstance == self.tunnelInstance else { return }
                if let error {
                    self.failVpnUpdate(
                        error,
                        operation: "stop.loadAllFromPreferences",
                        tunnelInstance: tunnelInstance,
                        completion: completion
                    )
                    return
                }

                let device = self.device

                guard let managers = managers, index < managers.count else {
                    self.clearVpnError()
                    completion?(nil)
                    return
                }
                let n = managers.count
                let tunnelManager = managers[index]

                tunnelManager.isEnabled = false
                tunnelManager.isOnDemandEnabled = false
                tunnelManager.onDemandRules = nil

                tunnelManager.saveToPreferences { [weak self] error in
                    DispatchQueue.main.async {
                        guard let self = self, tunnelInstance == self.tunnelInstance else { return }
                        if let error {
                            self.retryStopOrReport(
                                error,
                                operation: "stop.saveToPreferences",
                                index: index,
                                reset: reset,
                                managerCount: n,
                                tunnelInstance: tunnelInstance,
                                completion: completion
                            )
                            return
                        }

                        tunnelManager.connection.stopVPNTunnel()
                        self.clearVpnError()

                        let checkTunnel = {
                            DispatchQueue.main.asyncAfter(deadline: .now() + TunnelCheckTimeout) {
                                if tunnelInstance == self.tunnelInstance && device.getTunnelStarted() {
                                    if !reset {
                                        self.updateVpnServiceWithReset(index: index, reset: true)
                                    } else if index+1<n {
                                        self.updateVpnServiceWithReset(index: index+1, reset: false)
                                    }
                                }
                            }
                        }

                        if reset {
                            tunnelManager.removeFromPreferences() { [weak self] error in
                                DispatchQueue.main.async {
                                    guard let self = self, tunnelInstance == self.tunnelInstance else { return }
                                    if let error {
                                        self.retryStopOrReport(
                                            error,
                                            operation: "stop.removeFromPreferences",
                                            index: index,
                                            reset: reset,
                                            managerCount: n,
                                            tunnelInstance: tunnelInstance,
                                            completion: completion
                                        )
                                        return
                                    }
                                    checkTunnel()
                                    completion?(nil)
                                }
                            }
                        } else if index+1<n {
                            checkTunnel()
                            completion?(nil)
                        } else {
                            completion?(nil)
                        }
                    }
                }
            }
        }
    }
    
    
    func stopVpnTunnelOnQuit(completion: @escaping (Error?) -> Void) {
        // remove all vpn profiles
        self.tunnelInstance += 1
        VPNManager.removeAllVpnProfiles(completion: completion)
    }

    func stopVpnTunnelOnLogout(completion: @escaping (Error?) -> Void) {
        self.tunnelInstance += 1
        VPNManager.clearTunnelLocalStateAndRemoveAllVpnProfiles(completion: completion)
    }

    func stopVpnTunnelOnQuitAndWait() async -> Error? {
        await withCheckedContinuation { continuation in
            stopVpnTunnelOnQuit { error in
                continuation.resume(returning: error)
            }
        }
    }

    static func removeAllVpnProfiles(completion: @escaping (Error?) -> Void) {
        removeAllVpnProfilesWithIndex(index: 0, completion: completion)
    }

    static func clearTunnelLocalStateAndRemoveAllVpnProfiles(completion: @escaping (Error?) -> Void) {
        sendLogoutMessageToTunnelProviders {
            removeAllVpnProfiles(completion: completion)
        }
    }

    private static func sendLogoutMessageToTunnelProviders(completion: @escaping () -> Void) {
        NETunnelProviderManager.loadAllFromPreferences { (managers, _) in
            DispatchQueue.main.async {
                guard let managers = managers, !managers.isEmpty else {
                    completion()
                    return
                }

                let group = DispatchGroup()
                var sentMessage = false
                var didComplete = false

                let finish = {
                    guard !didComplete else { return }
                    didComplete = true
                    completion()
                }

                for manager in managers {
                    guard let session = manager.connection as? NETunnelProviderSession else {
                        continue
                    }

                    do {
                        group.enter()
                        try session.sendProviderMessage(TunnelLogoutProviderMessage) { _ in
                            group.leave()
                        }
                        sentMessage = true
                    } catch {
                        group.leave()
                        print("[VPNManager][logout] failed to send provider logout message: \(error.localizedDescription)")
                    }
                }

                guard sentMessage else {
                    finish()
                    return
                }

                group.notify(queue: .main) {
                    finish()
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    finish()
                }
            }
        }
    }

    private static func removeAllVpnProfilesWithIndex(index: Int, completion: @escaping (Error?) -> Void) {
        NETunnelProviderManager.loadAllFromPreferences { (managers, error) in
            DispatchQueue.main.async {
                if let error = error {
                    completion(error)
                    return
                }

                guard let managers = managers, !managers.isEmpty else {
                    completion(nil)
                    return
                }

                let tunnelManager = managers[0]
                tunnelManager.removeFromPreferences() { error in
                    DispatchQueue.main.async {
                        if let error = error {
                            completion(error)
                            return
                        }
                        VPNManager.removeAllVpnProfilesWithIndex(index: index + 1, completion: completion)
                    }
                }
            }
        }
    }
}


private class RouteLocalChangeListener: NSObject, SdkRouteLocalChangeListenerProtocol {
    
    private let c: (_ routeLocal: Bool) -> Void

    init(c: @escaping (_ routeLocal: Bool) -> Void) {
        self.c = c
    }
    
    func routeLocalChanged(_ routeLocal: Bool) {
        c(routeLocal)
    }
}

private class OfflineChangeListener: NSObject, SdkOfflineChangeListenerProtocol {
    
    private let c: (_ offline: Bool, _ vpnInterfaceWhileOffline: Bool) -> Void

    init(c: @escaping (_ offline: Bool, _ vpnInterfaceWhileOffline: Bool) -> Void) {
        self.c = c
    }
    
    func offlineChanged(_ offline: Bool, vpnInterfaceWhileOffline: Bool) {
        c(offline, vpnInterfaceWhileOffline)
    }
}

private class ConnectChangeListener: NSObject, SdkConnectChangeListenerProtocol {
    
    private let c: (_ connectEnabled: Bool) -> Void

    init(c: @escaping (_ connectEnabled: Bool) -> Void) {
        self.c = c
    }
    
    func connectChanged(_ connectEnabled: Bool) {
        c(connectEnabled)
    }
}

private class RemoteChangeListener: NSObject, SdkRemoteChangeListenerProtocol {
    
    private let c: (_ remoteConnected: Bool) -> Void

    init(c: @escaping (_ remoteConnected: Bool) -> Void) {
        self.c = c
    }
    
    func remoteChanged(_ remoteConnected: Bool) {
        c(remoteConnected)
    }
}

private class ProvideChangeListener: NSObject, SdkProvideChangeListenerProtocol {
    
    private let c: (_ provideEnabled: Bool) -> Void

    init(c: @escaping (_ provideEnabled: Bool) -> Void) {
        self.c = c
    }
    
    func provideChanged(_ provideEnabled: Bool) {
        c(provideEnabled)
    }
}

private class ProvidePausedChangeListener: NSObject, SdkProvidePausedChangeListenerProtocol {
    
    private let c: (_ providePaused: Bool) -> Void

    init(c: @escaping (_ providePaused: Bool) -> Void) {
        self.c = c
    }
    
    func providePausedChanged(_ providePaused: Bool) {
        c(providePaused)
    }
}
