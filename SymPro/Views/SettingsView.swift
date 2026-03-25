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
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var discovery = DSYMAutoDiscoveryStore.shared
    @State private var discoveryError: String?
    @State private var showLLMProviderSheet: Bool = false
    @State private var themeRefreshNonce: Int = 0

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 16) {
                appearanceSectionCard
                llmOpenAPISectionCard
                aboutSectionCard
            }
            .padding(20)
            .frame(maxWidth: 520, alignment: .topLeading)
        }
        .frame(minWidth: 380, idealWidth: 460, maxWidth: 600)
        .frame(minHeight: 320, idealHeight: 420, maxHeight: 900)
        .id(themeRefreshID)
        .onChange(of: settings.appearanceMode) { _ in
            triggerThemeRefresh()
        }
        .onChange(of: colorScheme) { _ in
            triggerThemeRefresh()
        }
    }

    private var themeRefreshID: String {
        "\(settings.appearanceMode.rawValue)-\(colorScheme == .dark ? "dark" : "light")-\(themeRefreshNonce)"
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
//            Divider()
//            settingsCardRow(
//                title: "Result Font Size",
//                subtitle: "Affects Overview / Raw Log / Result display."
//            ) {
//                Text("\(Int(settings.resultFontSize)) pt")
//                    .font(.body.monospacedDigit())
//                    .foregroundStyle(.secondary)
//            }
//            Divider()
//            VStack(alignment: .leading, spacing: 10) {
//                Slider(value: Binding(
//                    get: { settings.resultFontSize },
//                    set: { settings.resultFontSize = $0 }
//                ), in: 10...24, step: 1)
//                Text("Sample: Aa symbolicated result text")
//                    .font(.system(size: settings.resultFontSize, design: .monospaced))
//                    .foregroundStyle(.secondary)
//                    .padding(.vertical, 6)
//                    .padding(.horizontal, 10)
//                    .frame(maxWidth: .infinity, alignment: .leading)
//                    .background(Color(nsColor: .textBackgroundColor).opacity(0.35))
//                    .clipShape(RoundedRectangle(cornerRadius: 8))
//            }
//            .padding(.horizontal, 12)
//            .padding(.vertical, 10)
        } label: {
            Text("Appearance")
                .font(.headline)
        }
    }

    private var llmOpenAPISectionCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    showLLMProviderSheet = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "globe")
                            .font(.title2)
                            .foregroundStyle(.blue)
                            .frame(width: 40, height: 40)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(llmProviderRowTitle)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                            Text(llmProviderRowSubtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                Text(L10n.t("Analysis uses the current crash file as input."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        } label: {
            Text(L10n.t("Providers"))
                .font(.headline)
        }
        .sheet(isPresented: $showLLMProviderSheet) {
            LLMProviderSettingsSheet(settings: settings)
        }
    }

    private var llmProviderRowTitle: String {
        let n = settings.llmProviderDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !n.isEmpty { return n }
        return L10n.t("Model Provider")
    }

    private var llmProviderRowSubtitle: String {
        let m = settings.llmModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let u = settings.llmBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if u.isEmpty, m.isEmpty {
            return L10n.t("Not configured")
        }
        if let url = URL(string: u), let host = url.host {
            if m.isEmpty { return host }
            return "\(m) · \(host)"
        }
        if !m.isEmpty, !u.isEmpty {
            return "\(m) · \(u)"
        }
        return m.isEmpty ? u : m
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
            Divider()
            settingsCardRow(title: "Feedback", subtitle: "support@anti.xin") {
                HStack(spacing: 8) {
                    Button("Email Support") {
                        sendFeedbackEmail()
                    }
                    .buttonStyle(.bordered)
                }
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

    private func sendFeedbackEmail() {
        #if os(macOS)
        guard let url = feedbackMailURL() else { return }
        if NSWorkspace.shared.open(url) { return }

        // Fallback: explicitly ask Mail.app to handle the mailto URL.
        let mailAppURL = URL(fileURLWithPath: "/System/Applications/Mail.app")
        if FileManager.default.fileExists(atPath: mailAppURL.path) {
            let cfg = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open(
                [url],
                withApplicationAt: mailAppURL,
                configuration: cfg
            ) { _, _ in
                // Ignore callback result; user still has copy fallback button.
            }
        }
        #endif
    }

    private func feedbackMailURL() -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "support@anti.xin"
        
        components.queryItems = [
            URLQueryItem(name: "subject", value: "SymPro Feedback")
    ]
    
    return components.url
}

    private func triggerThemeRefresh() {
        themeRefreshNonce &+= 1
        // Some AppKit-backed controls update appearance one runloop later.
        DispatchQueue.main.async {
            themeRefreshNonce &+= 1
        }
    }

}

#Preview {
    SettingsView()
        .frame(width: 400, height: 300)
}
