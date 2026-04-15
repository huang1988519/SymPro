//
//  RootView.swift
//  SymPro
//

import SwiftUI
#if os(macOS)
import AppKit
private let mainWindowIdentifier = NSUserInterfaceItemIdentifier("MainWorkspaceWindow")
#endif

struct RootView: View {
    @EnvironmentObject private var workspaceState: SymbolicateWorkspaceState

    var body: some View {
        CrashAnalyzerRootView()
        #if os(macOS)
        .background(
            WindowWillCloseObserver(
                onWindowAvailable: { window in
                    window.identifier = mainWindowIdentifier
                    window.title = "SymPro"
                    let duplicateMainWindows = NSApp.windows.filter {
                        ($0.identifier == mainWindowIdentifier || $0.title == "SymPro") && $0 !== window
                    }
                    for duplicate in duplicateMainWindows {
                        duplicate.close()
                    }
                },
                shouldClose: {
                    guard workspaceState.crashLog != nil else { return true }
                    workspaceState.resetWorkspace()
                    return false
                }
            )
        )
        #endif
        .onDisappear {
            Task { @MainActor in
                workspaceState.resetWorkspace()
            }
        }
    }
}

#Preview {
    RootView()
}
