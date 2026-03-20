import SwiftUI

/// New UI root based on the provided mockups.
struct CrashAnalyzerRootView: View {
    @EnvironmentObject private var state: SymbolicateWorkspaceState

    var body: some View {
        Group {
            if state.crashLog == nil {
                CrashAnalyzerEmptyStateView(
                    isLoading: state.isLoadingCrashLog,
                    onOpen: { state.pickCrashLog() },
                    onDropProviders: { providers in state.handleCrashLogDrop(providers: providers) }
                )
            } else {
                CrashAnalyzerMainView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

