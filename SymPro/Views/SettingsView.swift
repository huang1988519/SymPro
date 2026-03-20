//
//  SettingsView.swift
//  SymPro
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

struct SettingsView: View {
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var discovery = DSYMAutoDiscoveryStore.shared
    @State private var discoveryError: String?

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 18) {
//                pageHeader
                appearanceSectionCard
                dsymDiscoverySectionCard
                aboutSectionCard
                Spacer(minLength: 0)
            }
            .padding(25)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var pageHeader: some View {
        HStack {
            Text("Settings")
                .font(.title2.weight(.semibold))
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var appearanceSectionCard: some View {
        GroupBox {
            settingsCardRow(
                title: "Appearance",
                subtitle: "Light / Dark / System"
            ) {
                Picker("", selection: Binding(
                    get: { settings.appearanceMode },
                    set: { settings.appearanceMode = $0 }
                )) {
                    ForEach(SettingsStore.AppearanceMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            Divider()
            settingsCardRow(
                title: "Result Font Size",
                subtitle: "Affects Overview / Raw Log / Result display."
            ) {
                Text("\(Int(settings.resultFontSize)) pt")
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Slider(value: Binding(
                    get: { settings.resultFontSize },
                    set: { settings.resultFontSize = $0 }
                ), in: 10...24, step: 1)
                Text("Sample: Aa symbolicated result text")
                    .font(.system(size: settings.resultFontSize, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.35))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        } label: {
            Text("Appearance")
                .font(.headline)
        }
    }

    private var dsymDiscoverySectionCard: some View {
        GroupBox {
            settingsCardRow(
                title: "Search Directories",
                subtitle: "Authorized directories will be scanned and indexed by UUID."
            ) {
                HStack(spacing: 10) {
                    Button("Add…") { addSearchFolder() }
                    Button(L10n.t("Rescan")) { discovery.rescan() }
                }
            }

            if let err = discoveryError {
                Divider()
                Text(err)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            }

            Divider()

            if discovery.searchFolders.isEmpty {
                Text("Add the directories where you keep dSYM/.xcarchive (e.g., Xcode Archives). The app will automatically match by UUID and assign dSYMs.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(discovery.searchFolders) { folder in
                        dsymFolderRowInCard(folder)
                    }
                    HStack {
                        Spacer()
                        Button("Remove All") {
                            discovery.removeSearchFolders(at: IndexSet(integersIn: 0..<discovery.searchFolders.count))
                        }
                        .buttonStyle(.link)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }

            Divider()

            discoveryStatusRow
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        } label: {
            Text("dSYM Discovery")
                .font(.headline)
        }
    }

    private var aboutSectionCard: some View {
        GroupBox {
            settingsCardRow(title: "Version", subtitle: nil) {
                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-")
                    .foregroundStyle(.secondary)
            }
            Divider()
            settingsCardRow(title: "Build", subtitle: nil) {
                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-")
                    .foregroundStyle(.secondary)
            }
        } label: {
            Text("About")
                .font(.headline)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .padding(.horizontal, 2)
    }

    private func settingsCardRow<Trailing: View>(title: String, subtitle: String?, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(alignment: subtitle == nil ? .center : .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .foregroundStyle(.primary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 10)
            trailing()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func dsymFolderRowInCard(_ folder: DSYMAutoDiscoveryStore.SearchFolder) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(folder.displayName)
                    .lineLimit(1)

                let resolved = resolvedFolderPathText(folder)
                Text(resolved.text)
                    .font(.caption2)
                    .foregroundStyle(resolved.isError ? Color.red : Color.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 10)
            Menu {
                Button("Show in Finder") { revealFolderInFinder(folder) }
                Button("Remove Authorization") { removeFolder(folder) }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .imageScale(.medium)
            }
            .menuStyle(.borderlessButton)
        }
    }

    private var discoveryStatusRow: some View {
        Group {
            switch discovery.scanState {
            case .idle:
                Text(L10n.t("Not scanned"))
                    .foregroundStyle(.secondary)
            case .scanning(let text):
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.5)
                    Text(text)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            case .failed(let message):
                Text(L10n.tFormat("Scan failed: %@", message))
                    .foregroundStyle(.red)
            case .finished(let found):
                Text(L10n.tFormat("Indexed %d UUIDs (updated %d this scan)", discovery.indexByUUID.count, found))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .padding(.vertical, 2)
    }

    private func resolvedFolderPathText(_ folder: DSYMAutoDiscoveryStore.SearchFolder) -> (text: String, isError: Bool) {
        do {
            let url = try SecurityScopedBookmarks.resolveBookmark(folder.bookmark)
            return (url.path, false)
        } catch {
            return ("Bookmark invalid: \(error.localizedDescription)", true)
        }
    }

    private func removeFolder(_ folder: DSYMAutoDiscoveryStore.SearchFolder) {
        guard let idx = discovery.searchFolders.firstIndex(of: folder) else { return }
        discovery.removeSearchFolders(at: IndexSet(integer: idx))
    }

    private func revealFolderInFinder(_ folder: DSYMAutoDiscoveryStore.SearchFolder) {
        #if os(macOS)
        do {
            let url = try SecurityScopedBookmarks.resolveBookmark(folder.bookmark)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            discoveryError = error.localizedDescription
        }
        #endif
    }

    // 卡片化设置页（回退到“背景色调整”之前版本）。

    private func addSearchFolder() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.title = L10n.t("Choose directories for dSYM Auto Discovery")
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try discovery.addSearchFolder(url: url)
                discoveryError = nil
                discovery.rescan()
            } catch {
                discoveryError = error.localizedDescription
            }
        }
        #endif
    }
}

#Preview {
    SettingsView()
        .frame(width: 400, height: 300)
}
