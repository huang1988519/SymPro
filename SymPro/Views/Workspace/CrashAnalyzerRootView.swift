import SwiftUI

/// New UI root based on the provided mockups.
struct CrashAnalyzerRootView: View {
    @EnvironmentObject private var state: SymbolicateWorkspaceState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if state.crashLog == nil {
                CrashAnalyzerEmptyStateView(
                    isLoading: state.isLoadingCrashLog,
                    onOpen: { state.pickCrashLog() },
                    onManualSymbolicate: { openWindow(id: "manual_symbolication") },
                    onDropProviders: { providers in state.handleCrashLogDrop(providers: providers) }
                )
            } else {
                CrashAnalyzerMainView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

