//
//  RootView.swift
//  SymPro
//

import SwiftUI

struct RootView: View {
    @EnvironmentObject private var workspaceState: SymbolicateWorkspaceState

    var body: some View {
        CrashAnalyzerRootView()
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
