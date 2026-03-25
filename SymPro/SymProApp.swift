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
    @StateObject private var workspaceState = SymbolicateWorkspaceState()
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var recentStore = RecentCrashLogStore.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(workspaceState)
                .preferredColorScheme(settings.appearanceMode.preferredColorScheme)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") {
                    Task { @MainActor in
                        workspaceState.pickCrashLog()
                    }
                }
                .keyboardShortcut("o", modifiers: [.command])
            }

            CommandGroup(after: .newItem) {
                Divider()
                Menu("Open Recent") {
                    if recentStore.items.isEmpty {
                        Button("No recent files") {}
                            .disabled(true)
                    } else {
                        ForEach(recentStore.items.prefix(10)) { item in
                            Button(item.fileName) {
                                if let url = recentStore.resolveURL(for: item) {
                                    NotificationCenter.default.post(
                                        name: .symProOpenRecentFile,
                                        object: nil,
                                        userInfo: ["url": url]
                                    )
                                }
                            }
                        }
                    }

                    Divider()
                    Button("Clear Menu") {
                        Task { @MainActor in
                            recentStore.removeAll()
                        }
                    }
                    .disabled(recentStore.items.isEmpty)
                }
            }
        }

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
