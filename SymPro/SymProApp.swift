//
//  SymProApp.swift
//  SymPro
//
//  Created by 黄伟华 on 2026/3/17.
//

import SwiftUI
import DWARFSymbolication
import DWARF
import UserNotifications
#if os(macOS)
import AppKit
#endif


extension Notification.Name {
    static let symProOpenRecentFile = Notification.Name("SymPro.openRecentFile")
    static let symProOpenAIInsight = Notification.Name("SymPro.openAIInsight")
}

private final class SymProAppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
    }

    // Disable macOS state restoration so the app always starts fresh (e.g. show welcome).
    func applicationShouldRestoreApplicationState(_ app: NSApplication) -> Bool {
        false
    }

    func applicationShouldRestoreSecureApplicationState(_ app: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in sender.windows {
                if window.canBecomeMain {
                    window.makeKeyAndOrderFront(self)
                    return false
                }
            }
        }
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.notification.request.identifier == "sympro.ai.analysis.ready" else { return }
        #if os(macOS)
        await MainActor.run {
            NSApp.activate(ignoringOtherApps: true)
            NotificationCenter.default.post(name: .symProOpenAIInsight, object: nil)
        }
        #endif
    }
}

@main
struct SymProApp: App {
    @NSApplicationDelegateAdaptor(SymProAppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow
    @StateObject private var workspaceState = SymbolicateWorkspaceState()
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var recentStore = RecentCrashLogStore.shared

    #if os(macOS)
    private var mainWindowIdentifier: NSUserInterfaceItemIdentifier {
        NSUserInterfaceItemIdentifier("MainWorkspaceWindow")
    }

    private var manualWindowIdentifier: NSUserInterfaceItemIdentifier {
        NSUserInterfaceItemIdentifier("ManualSymbolicationWindow")
    }

    private func allMainWindows() -> [NSWindow] {
        NSApp.windows.filter { window in
            window.identifier == mainWindowIdentifier || window.title == "SymPro"
        }
    }

    @discardableResult
    private func keepSingleMainWindow(preferred: NSWindow? = nil) -> NSWindow? {
        let mains = allMainWindows()
        guard !mains.isEmpty else { return nil }

        let keeper = preferred.flatMap { p in mains.first(where: { $0 === p }) } ?? mains[0]
        for window in mains where window !== keeper {
            window.close()
        }
        return keeper
    }

    private func ensureMainWindowVisible() {
        if let main = keepSingleMainWindow() {
            main.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openOrFocusManualWindow() {
        if let existing = NSApp.windows.first(where: { $0.identifier == manualWindowIdentifier }) {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            openWindow(id: "manual_symbolication")
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    #endif

    var body: some Scene {
        WindowGroup("SymPro", id: "main") {
            RootView()
                .environmentObject(workspaceState)
                .preferredColorScheme(settings.appearanceMode.preferredColorScheme)
        }
        
        WindowGroup(L10n.t("Manual Symbolication"), id: "manual_symbolication") {
            ManualSymbolicationWindowView()
                .preferredColorScheme(settings.appearanceMode.preferredColorScheme)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(L10n.t("Open…")) {
                    Task { @MainActor in
                        ensureMainWindowVisible()
                        workspaceState.pickCrashLog()
                    }
                }
                .keyboardShortcut("o", modifiers: [.command])
            }

            CommandGroup(after: .newItem) {
                Divider()
                Button(L10n.t("Manual Symbolicate…")) {
                    #if os(macOS)
                    openOrFocusManualWindow()
                    #else
                    openWindow(id: "manual_symbolication")
                    #endif
                }
                Menu(L10n.t("Open Recent")) {
                    if recentStore.items.isEmpty {
                        Button(L10n.t("No recent files")) {}
                            .disabled(true)
                    } else {
                        ForEach(recentStore.items.prefix(10)) { item in
                            Button(item.fileName) {
                                if let url = recentStore.resolveURL(for: item) {
                                    ensureMainWindowVisible()
                                    workspaceState.openCrashLog(url)
                                }
                            }
                        }
                    }

                    Divider()
                    Button(L10n.t("Clear Menu")) {
                        Task { @MainActor in
                            recentStore.removeAll()
                        }
                    }
                    .disabled(recentStore.items.isEmpty)
                }
            }
        }

        #if os(macOS)
        .commands {
            CommandGroup(after: .windowSize) {
                Button(L10n.t("Show Main Window")) {
                    ensureMainWindowVisible()
                }
                .keyboardShortcut("0", modifiers: [.command])
            }
        }
        #endif

        Settings {
            SettingsView()
                .preferredColorScheme(settings.appearanceMode.preferredColorScheme)
        }
        #if os(macOS)
        .defaultSize(width: 460, height: 420)
        .windowResizability(.contentSize)
        #endif
    }
}
