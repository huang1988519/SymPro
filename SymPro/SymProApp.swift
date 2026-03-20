//
//  SymProApp.swift
//  SymPro
//
//  Created by 黄伟华 on 2026/3/17.
//

import SwiftUI
import DWARFSymbolication
import DWARF


extension Notification.Name {
    static let symProOpenRecentFile = Notification.Name("SymPro.openRecentFile")
}

@main
struct SymProApp: App {
    @StateObject private var workspaceState = SymbolicateWorkspaceState()
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var recentStore = RecentCrashLogStore.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(workspaceState)
                .preferredColorScheme(settings.appearanceMode.preferredColorScheme)
        }
        Settings {
            SettingsView()
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
    }
}
