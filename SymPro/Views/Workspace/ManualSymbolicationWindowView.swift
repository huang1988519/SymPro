import SwiftUI

struct ManualSymbolicationWindowView: View {
    @State private var showDirectories: Bool = false

    #if os(macOS)
    private var manualWindowIdentifier: NSUserInterfaceItemIdentifier {
        NSUserInterfaceItemIdentifier("ManualSymbolicationWindow")
    }
    #endif

    var body: some View {
        NavigationSplitView {
            dsymDiscoveryContent
                .navigationSplitViewColumnWidth(min: 200, ideal: 260, max: 340)
                .navigationTitle(L10n.t("Manual Symbolication"))
//                .toolbar {
//                    ToolbarItem(placement: .automatic) {
//                        Button {
//                            showDirectories.toggle()
//                        } label: {
//                            Label("dSYM Directories", systemImage: "sidebar.right")
//                                .labelStyle(.titleAndIcon)
//                        }
//                    }
//                }
        } detail: {
            manualSymbolicateContent
        }
        #if os(macOS)
        .background(
            WindowWillCloseObserver(
                onWindowAvailable: { window in
                    window.title = L10n.t("Manual Symbolication")
                    window.identifier = manualWindowIdentifier
                }
            )
        )
        #endif
    }

    private var manualSymbolicateContent: some View {
        ScrollView(.vertical) {
            ManualSymbolicateSheet()
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var dsymDiscoveryContent: some View {
        ScrollView(.vertical) {
            DSYMDiscoveryDirectoriesCard()
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

