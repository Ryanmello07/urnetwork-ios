//
//  NetworkApp.swift
//  network
//
//  Created by brien on 11/18/24.
//

import SwiftUI
import URnetworkSdk
import GoogleSignIn

@main
struct NetworkApp: App {
    
#if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
#elseif os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var mainWindow: NSWindow?
#endif
    
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = true
    
    @State private var isWindowVisible = true
    @State private var keyEventMonitor: Any?
    
    let themeManager = ThemeManager.shared
    
    @StateObject var deviceManager: DeviceManager

    @StateObject var connectViewModel = ConnectViewModel()

    @StateObject var throughputStore = ThroughputStore()
    @StateObject var blockActionsStore = BlockActionsStore()
    @StateObject var dnsSettingsStore = DnsSettingsStore()
    @StateObject var networkPeersStore = NetworkPeersStore()

    init() {
        let deviceManager = DeviceManager()
        _deviceManager = StateObject(wrappedValue: deviceManager)
        appDelegate.deviceManager = deviceManager

        #if os(iOS)
        // for styling NavigationTitle
        // todo - can probably be moved to top of app
        if let largeFont = UIFont(name: "ABCGravity-Extended", size: 32) {
            UINavigationBar.appearance().largeTitleTextAttributes = [.font: largeFont]
        }
        if let titleFont = UIFont(name: "PP NeueBit", size: 24) {
            UINavigationBar.appearance().titleTextAttributes = [.font: titleFont]
        }
        #endif
    }
    
    func setupConnectViewModel(_ device: SdkDeviceRemote) {
        
        let connectViewController = device.openConnectViewController()
        
        self.connectViewModel.setup(
            api: deviceManager.api,
            device: device,
            connectViewController: connectViewController
        )
        
    }

    func updateConnectViewModel(_ device: SdkDeviceRemote?) {
        if let device = device {
            if connectViewModel.device == device && connectViewModel.connectViewController != nil {
                return
            }
            setupConnectViewModel(device)
            setupDeviceStores(device)
        } else {
            connectViewModel.reset()
            resetDeviceStores()
        }
    }

    private func setupDeviceStores(_ device: SdkDeviceRemote) {
        throughputStore.setup(device)
        blockActionsStore.setup(device)
        dnsSettingsStore.setup(device)
        networkPeersStore.setup(device)
    }

    private func resetDeviceStores() {
        throughputStore.reset()
        blockActionsStore.reset()
        dnsSettingsStore.reset()
        networkPeersStore.reset()
    }
    
    private var connectEnabled: Bool {
        
        guard let device = deviceManager.device else {
            return false
        }
        
        return device.getConnectEnabled()
        
    }
    
    private var provideEnabled: Bool {
        guard let device = deviceManager.device else {
            return false
        }
        
        return device.getProvideEnabled()
    }

    private var menuBarImage: String {
        
        if self.connectEnabled {
            
            // connect and provide enabled
            if self.provideEnabled {
                return "MenuBarProvideConnect"
            }
            
            // connected and provide disabled
            return "MenuBarNoProvideConnect"
            
        } else {
            
            // disconnected with provide enabled
            if self.provideEnabled {
                return "MenuBarProvideNoConnect"
            }
            
            // disconnected and provide disabled
            return "MenuBarNoProvideNoConnect"
            
        }
        
    }
    
    
    var body: some Scene {
        WindowGroup {
            
            
            #if os(iOS)
            ContentView()
                .environmentObject(themeManager)
                .environmentObject(deviceManager)
                .environmentObject(connectViewModel)
                .environmentObject(throughputStore)
                .environmentObject(blockActionsStore)
                .environmentObject(dnsSettingsStore)
                .environmentObject(networkPeersStore)
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
                .preferredColorScheme(.dark)
                .background(themeManager.currentTheme.backgroundColor)
                .onReceive(deviceManager.$device) { device in
                    updateConnectViewModel(device)
                }
            #elseif os(macOS)
            ContentView()
                .environmentObject(themeManager)
                .environmentObject(deviceManager)
                .environmentObject(connectViewModel)
                .environmentObject(throughputStore)
                .environmentObject(blockActionsStore)
                .environmentObject(dnsSettingsStore)
                .environmentObject(networkPeersStore)
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
                .preferredColorScheme(.dark)
                .background(themeManager.currentTheme.backgroundColor)
                .onAppear {
                    if keyEventMonitor == nil {
                        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                            if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "q" {
                                hideWindow()
                                return nil
                            }
                            return event
                        }
                    }
                }
                .onReceive(deviceManager.$device) { device in
                    updateConnectViewModel(device)
                }
                .onAppear {
                    if mainWindow == nil {
                        mainWindow = NSApplication.shared.windows.first { window in
                            window.styleMask.contains(.titled) &&
                            window.styleMask.contains(.closable) &&
                            !window.styleMask.contains(.nonactivatingPanel)
                        }
                        mainWindow?.isReleasedWhenClosed = false
                    }
                }
            #endif
            
        }
        #if os(macOS)
        .defaultSize(CGSize(width: 1024, height: 768))
        #endif
        .commands {
            
            /**
             * macOS menu items
             */
            
            #if os(macOS)
            CommandGroup(replacing: .appTermination) {
                Button("Quit URnetwork") {
                    connectViewModel.disconnect()
                    
                    NSApplication.shared.terminate(nil)
                }
            }
            #endif
            
            if deviceManager.device != nil {
             
                CommandMenu("Account") {
                    Button("Sign out") {
                        
                        connectViewModel.disconnect()
                        
                        Task {
                            deviceManager.logout()
                        }
                        
                    }
                }
                
            }
            
        }
        #if os(macOS)
        MenuBarExtra(
            "URnetwork System Menu",
            image: menuBarImage,
            isInserted: $showMenuBarExtra
        ) {
            
            Text("URnetwork Status")
                .font(.headline)
            

            Button(action: {}) {
                HStack {
                    Image(systemName: self.connectEnabled ? "checkmark" : "xmark")
                    Text("Connected")
                }
            }
            .buttonStyle(.plain)
            .disabled(true)

            Button(action: {}) {
                HStack {
                    Image(systemName: self.provideEnabled ? "checkmark" : "xmark")
                    Text("Providing")
                }
            }
            .buttonStyle(.plain)
            .disabled(true)
            
            Divider()
            
            if connectViewModel.connectionStatus == .disconnected {
                Button("Connect", action: {
                    connectViewModel.connect()
                })
            } else {
                Button("Disconnect", action: {
                    connectViewModel.disconnect()
                })
            }
            
            Button("Show", action: {
                showWindow()
            })
            
            Button("Quit URnetwork", action: {
                connectViewModel.disconnect()
                
                NSApplication.shared.terminate(nil)
                
            })
            
            
        }
        #endif
    }
    
    #if os(macOS)
    
    private func hideWindow() {
        mainWindow?.orderOut(nil)  // Hide the window without destroying it
        NSApp.setActivationPolicy(.accessory)  // Remove from Dock
        isWindowVisible = false
    }

    private func showWindow() {
        NSApp.setActivationPolicy(.regular)  // Show in Dock

        if let window = mainWindow {
            window.makeKeyAndOrderFront(nil)
        }
        
        NSApplication.shared.activate(ignoringOtherApps: true)
        isWindowVisible = true
    }
    
    #endif
    
}
