import SwiftUI
#if os(macOS)
import AppKit
#endif

/// New UI root based on the provided mockups.
struct CrashAnalyzerRootView: View {
    @EnvironmentObject private var state: SymbolicateWorkspaceState
    @Environment(\.openWindow) private var openWindow

    #if os(macOS)
    private var manualWindowIdentifier: NSUserInterfaceItemIdentifier {
        NSUserInterfaceItemIdentifier("ManualSymbolicationWindow")
    }

    private func openOrFocusManualWindow() {
        if let existing = NSApp.windows.first(where: { $0.identifier == manualWindowIdentifier }) {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            openWindow(id: "manual_symbolication")
        }
    }
    #endif

    var body: some View {
        Group {
            if state.crashLog == nil {
                CrashAnalyzerEmptyStateView(
                    isLoading: state.isLoadingCrashLog,
                    onOpen: { state.pickCrashLog() },
                    onManualSymbolicate: {
#if os(macOS)
                        openOrFocusManualWindow()
#else
                        openWindow(id: "manual_symbolication")
#endif
                    },
                    onDropProviders: { providers in state.handleCrashLogDrop(providers: providers) }
                )
            } else {
                CrashAnalyzerMainView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

