//
//  SymbolicateWorkspaceView.swift
//  SymPro
//

import SwiftUI

struct SymbolicateWorkspaceView: View {
    @ObservedObject var workspaceState: SymbolicateWorkspaceState
    @ObservedObject private var discovery = DSYMAutoDiscoveryStore.shared
    @State private var subSelection: SymbolicateSubItem = .overview

    var body: some View {
        HStack(spacing: 0) {
            subSidebar
            Divider()
            detailContent
        }
        .frame(minWidth: 860, minHeight: 520)
        .toolbar { primaryToolbar }
    }

    private var subSidebar: some View {
        Group {
            if #available(macOS 13.0, *) {
                List(selection: $subSelection) {
                    Section {
                        Button {
                            workspaceState.pickCrashLog()
                        } label: {
                            Label("Open File", systemImage: "plus.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tint)
                        .tag(SymbolicateSubItem.overview)
                    }
                    Section {
                        sidebarItem(.overview, title: "Overview", systemImage: "rectangle.grid.2x2")
                        sidebarItem(.threads, title: "Threads", systemImage: "list.bullet.rectangle")
                        sidebarItem(.images, title: "Images", systemImage: "square.stack.3d.up")
                    } header: {
                        Text("ANALYSIS")
                    }
                    Section {
                        sidebarItem(.rawLog, title: "Raw Log", systemImage: "doc.plaintext")
                    } header: {
                        Text("SOURCE")
                    }
                }
                .listStyle(.sidebar)
            } else {
                // macOS 12：List(selection:) 不可用，改为手动高亮与点击切换
                List {
                    Section {
                        Button {
                            workspaceState.pickCrashLog()
                            subSelection = .overview
                        } label: {
                            Label("Open File", systemImage: "plus.circle.fill")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tint)
                    }
                    Section {
                        sidebarButton(.overview, title: "Overview", systemImage: "rectangle.grid.2x2")
                        sidebarButton(.threads, title: "Threads", systemImage: "list.bullet.rectangle")
                        sidebarButton(.images, title: "Images", systemImage: "square.stack.3d.up")
                    } header: {
                        Text("ANALYSIS")
                    }
                    Section {
                        sidebarButton(.rawLog, title: "Raw Log", systemImage: "doc.plaintext")
                    } header: {
                        Text("SOURCE")
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .frame(minWidth: 200, idealWidth: 220, maxWidth: 260)
    }

    @available(macOS 13.0, *)
    private func sidebarItem(_ item: SymbolicateSubItem, title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .tag(item)
    }

    private func sidebarButton(_ item: SymbolicateSubItem, title: String, systemImage: String) -> some View {
        Button {
            subSelection = item
        } label: {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .listRowBackground(subSelection == item ? Color.accentColor.opacity(0.18) : Color.clear)
    }

    @ViewBuilder
    private var detailContent: some View {
        switch subSelection {
        case .overview:
            OverviewView(state: workspaceState)
        case .threads:
            ThreadsView(state: workspaceState)
        case .images:
            ImagesView(state: workspaceState)
        case .rawLog:
            RawLogView(state: workspaceState)
        }
    }

    @ToolbarContentBuilder
    private var primaryToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button {
                workspaceState.pickCrashLog()
                subSelection = .overview
            } label: {
                Label("Open", systemImage: "folder")
            }
            .help(L10n.t("Open .ips / .crash files"))

            Button {
                discovery.rescan()
            } label: {
                Label("Scan dSYMs", systemImage: "arrow.clockwise")
            }
            .help(L10n.t("Rescan the authorized dSYM search directories in Settings"))

            Button {
                workspaceState.recomputeResolvedDSYMSelection()
            } label: {
                Label("Re-match", systemImage: "wand.and.stars")
            }
            .disabled(workspaceState.crashLog == nil)
            .help(L10n.t("Re-match UUIDs for this crash using the current index/imported dSYMs (no index rebuild)"))
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                workspaceState.startSymbolication()
            } label: {
                Label("Start Symbolication", systemImage: "play.fill")
            }
            .disabled(workspaceState.isSymbolicating || workspaceState.crashLog == nil || workspaceState.selectedDSYMByImageUUID.isEmpty)
            .help(workspaceState.crashLog != nil && workspaceState.selectedDSYMByImageUUID.isEmpty
                   ? L10n.t("Please select matching dSYMs for the target Mach-O first, then click to resolve addresses into symbols")
                   : L10n.t("Use the selected dSYMs to resolve stack addresses into function names and line numbers"))
        }

        ToolbarItem(placement: .automatic) {
            HStack(spacing: 10) {
                if workspaceState.isSymbolicating {
                    ProgressView().scaleEffect(0.5)
                }
                if case .scanning = discovery.scanState {
                    ProgressView().scaleEffect(0.5)
                }
            }
        }
    }
}

enum SymbolicateSubItem: Hashable {
    case overview
    case threads
    case images
    case rawLog
}

#Preview {
    SymbolicateWorkspaceView(workspaceState: SymbolicateWorkspaceState())
        .frame(width: 700, height: 500)
}
