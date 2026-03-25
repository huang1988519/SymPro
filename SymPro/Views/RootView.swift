//
//  RootView.swift
//  SymPro
//

import SwiftUI

struct RootView: View {
    @EnvironmentObject private var workspaceState: SymbolicateWorkspaceState

    var body: some View {
        CrashAnalyzerRootView()
        .onReceive(NotificationCenter.default.publisher(for: .symProOpenRecentFile)) { notification in
            guard let url = notification.userInfo?["url"] as? URL else { return }
            workspaceState.openCrashLog(url)
        }
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
