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

    // per-session rpc transport (client/server self-signed material + listen port)
    private var rpcRemoteChangeSub: SdkSubProtocol?
    private var rpcConnectTimeoutWork: DispatchWorkItem?
    private var currentRpcSession: RpcSession?
    private let rpcConnectTimeout: TimeInterval = 15

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

        self.rpcRemoteChangeSub?.close()
        self.rpcRemoteChangeSub = nil
        self.rpcConnectTimeoutWork?.cancel()
        self.rpcConnectTimeoutWork = nil
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
        // the tunnel is the packet router: it must run whenever the device is
        // connected, providing (any mode — including Network, which relays for
        // same-network peers), or routing remotely
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

        #if DEBUG
        print("provideEnabled is: \(provideEnabled)")
        print("connect enabled: \(connectEnabled)")
        print("routeLocal is: \(routeLocal)")
        print("provideMode is: \(device.getProvideMode())")
        print("provideControlMode is: \(device.getProvideControlMode())")
        #endif

        if (provideEnabled || connectEnabled || !routeLocal) {
            #if DEBUG
            print("[VPNManager]start")
            #endif

            // if provide paused, keep the vpn on but do not keep the locks
            setIdleTimerDisabled(!providePaused)
            
            self.startVpnTunnel(index: index, reset: reset, completion: completion)
            
        } else {
            #if DEBUG
            print("[VPNManager]stop")
            #endif

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

    // prepareRpcSession returns the rpc session to use for this start: the
    // in-flight session if one is pending (so internal retries are stable), the
    // last known good session if present, or fresh mTLS material on a random
    // listen port.
    private func prepareRpcSession() -> RpcSession? {
        if let session = self.currentRpcSession {
            return session
        }
        if let session = RpcSessionStore.load() {
            self.currentRpcSession = session
            return session
        }
        var err: NSError?
        guard let keyMaterial = SdkGenerateDeviceRpcKeyMaterial(&err), err == nil else {
            return nil
        }
        // the getters return non-optional strings (Go string); validate non-empty
        let clientPem = keyMaterial.getClientPem()
        let clientCertPem = keyMaterial.getClientCertPem()
        let serverPem = keyMaterial.getServerPem()
        let serverCertPem = keyMaterial.getServerCertPem()
        guard !clientPem.isEmpty, !clientCertPem.isEmpty, !serverPem.isEmpty, !serverCertPem.isEmpty else {
            return nil
        }
        let session = RpcSession(
            clientPem: clientPem,
            clientCertPem: clientCertPem,
            serverPem: serverPem,
            serverCertPem: serverCertPem,
            host: "127.0.0.1",
            port: Int.random(in: 12000...12100)
        )
        self.currentRpcSession = session
        return session
    }

    // applyRpcSession resets the app device's rpc transport to dial the
    // extension's listener with this session, then arms an observer: on a
    // successful rpc connection the session is persisted as last known good.
    // Only fresh (never-connected) material is put on a connect deadline; a
    // session that already connected before is kept and reused, so repeated
    // restarts (e.g. switching locations) never discard known-good material.
    private func applyRpcSession(_ session: RpcSession, device: SdkDeviceRemote, tunnelInstance: Int) {
        do {
            try device.setRpcServer(session.clientPem, serverCertPem: session.serverCertPem, hostPort: session.hostPort)
        } catch {
            print("[VPNManager]setRpcServer failed: \(error.localizedDescription)")
        }

        self.rpcRemoteChangeSub?.close()
        self.rpcConnectTimeoutWork?.cancel()

        self.rpcRemoteChangeSub = device.add(RemoteChangeListener { [weak self] remoteConnected in
            DispatchQueue.main.async {
                guard let self = self, tunnelInstance == self.tunnelInstance else { return }
                guard remoteConnected else { return }
                // this material connected; persist it as last-known-good and stop the timeout
                self.rpcConnectTimeoutWork?.cancel()
                self.rpcConnectTimeoutWork = nil
                RpcSessionStore.save(session)
            }
        })

        // Only fresh, never-connected material is put on a connect deadline. If a
        // session is already the persisted last-known-good it has connected
        // before, so keep reusing it — a transient timeout while the tunnel keeps
        // restarting (e.g. switching locations repeatedly, which calls
        // updateVpnService over and over) must not discard good key material or
        // force a new port on the next start.
        guard RpcSessionStore.load() == nil else { return }

        let timeoutWork = DispatchWorkItem { [weak self] in
            guard let self = self, tunnelInstance == self.tunnelInstance else { return }
            // the rpc channel never came up with this fresh material; drop it so
            // the next start generates new material on a new port
            self.currentRpcSession = nil
        }
        self.rpcConnectTimeoutWork = timeoutWork
        DispatchQueue.main.asyncAfter(deadline: .now() + self.rpcConnectTimeout, execute: timeoutWork)
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

                    guard let rpcSession = self.prepareRpcSession() else {
                        self.failVpnUpdate(
                            makeVPNManagerError("Failed to generate rpc key material", code: 9),
                            operation: "start.buildProviderConfiguration",
                            tunnelInstance: tunnelInstance,
                            completion: completion
                        )
                        return
                    }

                    tunnelProtocol.providerConfiguration = [
                        "by_jwt": byJwt,
                        // self-signed server cert + private key the extension presents
                        "rpc_server_pem": rpcSession.serverPem,
                        // client cert (public only) the extension pins for mTLS;
                        // the client private key stays in the app
                        "rpc_client_pem": rpcSession.clientCertPem,
                        // host:port the extension listens on and the app dials
                        "rpc_listen_hostport": rpcSession.hostPort,
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
                                        // point the app's rpc transport at the extension's listener
                                        // (pinning the matching client cert) and watch for a
                                        // successful connection
                                        self.applyRpcSession(rpcSession, device: device, tunnelInstance: tunnelInstance)
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
        // forget the rpc transport material so the next login regenerates it
        RpcSessionStore.clear()
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

// RpcSession is the per-vpn-session rpc transport material: the self-signed
// client cert (pinned by the app), the server cert+key (presented by the
// extension), and the loopback host/port the extension listens on.
// The PEM values are opaque strings produced by the SDK; the app stores and
// forwards them verbatim and never manipulates the material itself.
struct RpcSession: Codable {
    let clientPem: String       // client cert + private key (app presents; stays in app)
    let clientCertPem: String   // client cert only (public; sent to the extension to pin)
    let serverPem: String       // server cert + private key (sent to the extension to present)
    let serverCertPem: String   // server cert only (public; the app pins)
    let host: String
    let port: Int

    var hostPort: String { "\(host):\(port)" }
}

// RpcSessionStore persists the last known good RpcSession in the app process so
// reconnects reuse the same material/port (avoiding an extension device
// recreation) until a connection fails.
enum RpcSessionStore {
    private static let key = "network.ur.rpcSessionLastGood"

    static func load() -> RpcSession? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(RpcSession.self, from: data)
    }

    static func save(_ session: RpcSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
