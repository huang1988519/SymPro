import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

struct CrashAnalyzerDSYMPanel: View {
    @EnvironmentObject private var state: SymbolicateWorkspaceState
    @ObservedObject private var discovery = DSYMAutoDiscoveryStore.shared
    @State private var dsymInfo: DSYMInfoPresentation?
    @State private var showAllMachO: Bool = false
    @State private var discoveryError: String?
    @State private var menuRefreshToken: Int = 0
    @State private var didAutoCleanupStaleBookmarks: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.t("Auto dSYM Discovery Directories"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.secondary)

            GroupBox("") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Menu {
                            let suggestionsToShow = builtInSuggestions.filter { !isSuggestionAuthorized($0.url) }
#if DEBUG
                            debugLogSuggestionsToShow(suggestionsToShowCount: suggestionsToShow.count)
#endif
                            ForEach(suggestionsToShow, id: \.id) { suggestion in
                                Button("Recommended: \(suggestion.title)") {
                                    authorizeFolder(suggestion.url)
                                }
                            }
                            if !suggestionsToShow.isEmpty { Divider() }
                            Button("Custom directory…") {
                                addSearchFolderCustom()
                            }
                        } label: {
                            Label("Add", systemImage: "plus.circle.fill")
                        }
                        .menuStyle(.borderlessButton)
                        .help(L10n.t("Add dSYM Discovery directories: choose a recommended directory or a custom directory (manual authorization required)."))
                        .id(menuRefreshToken)
                        
                        Spacer(minLength: 0)
                        Button(L10n.t("Rescan")) { discovery.rescan() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(discovery.searchFolders.isEmpty)
                    }

                    if let err = discoveryError, !err.isEmpty {
                        Text(err)
                            .foregroundStyle(.red)
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Divider()

                    if discovery.searchFolders.isEmpty {
                        Text("Add/authorize at least one directory containing dSYMs (e.g., Xcode Archives), then click “Rescan”.")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(discovery.searchFolders) { folder in
                                dsymFolderRowInCard(folder)
                            }
                        }
                    }

                    Divider()
                    discoveryStatusRow
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }

            if let crash = state.crashLog {
                let entries = uuidEntries(crash: crash, showAll: showAllMachO)
                let detailsByUUID = imageDetailsByUUID(crash: crash)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Toggle(L10n.t("Show system images"), isOn: $showAllMachO)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        Spacer(minLength: 0)
                        Text(L10n.tFormat("Showing %d / %d", entries.count, crash.uuidList.count))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(entries) { entry in
                                let uuid = entry.uuid
                                let details = detailsByUUID[uuid]
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.name)
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                        if let arch = details?.arch, !arch.isEmpty {
                                            Text(arch)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                        Text(uuid)
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundStyle(Color.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                        if let bundleId = details?.bundleId, !bundleId.isEmpty {
                                            Text(bundleId)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                        }
                                        if let size = details?.size, size > 0 {
                                            Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        if let path = details?.path, !path.isEmpty {
                                            Text(path)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                        }
                                    }
                                    Spacer(minLength: 8)
                                    if let selected = state.selectedDSYMByImageUUID[uuid] {
                                        let isManual = state.manualDSYMOverrideByImageUUID[uuid] != nil
                                        HStack(spacing: 6) {
                                            Text(isManual ? L10n.t("Manual") : L10n.t("Auto"))
                                                .font(.caption2.weight(.semibold))
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 3)
                                                .background((isManual ? Color.accentColor : Color.green).opacity(0.18))
                                                .foregroundStyle(isManual ? Color.accentColor : Color.primary)
                                                .clipShape(Capsule())

                                            Button {
                                                dsymInfo = DSYMInfoPresentation(
                                                    uuid: uuid,
                                                    imageName: entry.name,
                                                    url: selected,
                                                    isManual: isManual
                                                )
                                            } label: {
                                                Image(systemName: "info.circle")
                                                    .font(.system(size: 11, weight: .semibold))
                                            }
                                            .buttonStyle(.plain)
                                            .foregroundStyle(Color.secondary)
                                            .help(L10n.t("View dSYM details"))
                                        }
                                    } else if !entry.isSystem {
                                        let discovered = discovery.resolveDSYMURL(forUUID: uuid)?.url
                                        let label = discovered != nil ? L10n.t("Auto-match available") : L10n.t("Missing")
                                        Text(label)
                                            .font(.caption2.weight(.semibold))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(Color.secondary.opacity(0.12))
                                            .foregroundStyle(.secondary)
                                            .clipShape(Capsule())
                                    }
                                }
                                Divider()
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
//                    .frame(maxHeight: 200)

                    HStack(spacing: 8) {
                        Button(L10n.t("Select dSYM for missing UUIDs…")) {
                            if let missing = crash.uuidList.first(where: { state.selectedDSYMByImageUUID[$0] == nil }) {
                                state.pickDSYM(forImageUUID: missing)
                            } else {
                                state.pickDSYM()
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(crash.uuidList.isEmpty)

                        Button(L10n.t("Re-match")) {
                            state.recomputeResolvedDSYMSelection()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(crash.uuidList.isEmpty)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
        .task {
            guard !didAutoCleanupStaleBookmarks else { return }
            didAutoCleanupStaleBookmarks = true
            cleanupStaleBookmarksIfNeeded()
        }
        .sheet(item: $dsymInfo) { info in
            DSYMInfoSheet(info: info)
        }
    }

    private func imageNameByUUID(crash: CrashLog) -> [String: String] {
        // 优先使用结构化 usedImages（.ips），否则退回 parser 的 binaryImages
        if let model = state.symbolicatedModel ?? crash.model {
            let pairs: [(String, String)] = model.images.compactMap { img in
                guard let uuid = img.uuid, !uuid.isEmpty else { return nil }
                let name = img.name.isEmpty ? "Unknown Image" : img.name
                return (uuid, name)
            }
            return Dictionary(pairs, uniquingKeysWith: { first, _ in first })
        }

        let pairs: [(String, String)] = crash.binaryImages.compactMap { img in
            guard let uuid = img.uuid, !uuid.isEmpty else { return nil }
            let name = img.name.isEmpty ? "Unknown Image" : img.name
            return (uuid, name)
        }
        return Dictionary(pairs, uniquingKeysWith: { first, _ in first })
    }

    private func imageDetailsByUUID(crash: CrashLog) -> [String: (arch: String?, bundleId: String?, size: UInt64?, path: String?)] {
        // Prefer structured .ips image data (best match with ImagesView).
        if let model = state.symbolicatedModel ?? crash.model {
            let pairs = model.images.compactMap { img -> (String, (String?, String?, UInt64?, String?))? in
                guard let u = img.uuid, !u.isEmpty else { return nil }
                return (u, (img.arch, img.bundleId, img.size, img.path))
            }
            return Dictionary(pairs, uniquingKeysWith: { first, _ in first })
        }

        // Fallback for legacy parsed .crash: only arch is available.
        let pairs = crash.binaryImages.compactMap { img -> (String, (String?, String?, UInt64?, String?))? in
            guard let u = img.uuid, !u.isEmpty else { return nil }
            return (u, (img.architecture, nil, nil, nil))
        }
        return Dictionary(pairs, uniquingKeysWith: { first, _ in first })
    }

    private func uuidEntries(crash: CrashLog, showAll: Bool) -> [UUIDDisplayEntry] {
        let names = imageNameByUUID(crash: crash)
        let pathByUUID: [String: String] = {
            if let model = state.symbolicatedModel ?? crash.model {
                let pairs = model.images.compactMap { img -> (String, String)? in
                    guard let u = img.uuid, !u.isEmpty else { return nil }
                    return (u, img.path ?? "")
                }
                return Dictionary(pairs, uniquingKeysWith: { first, _ in first })
            }
            return [:]
        }()

        return crash.uuidList.compactMap { uuid in
            let name = names[uuid] ?? "Unknown Image"
            let path = pathByUUID[uuid]
            let isSystem = isSystemImage(name: name, path: path)
            if !showAll && isSystem { return nil }
            return UUIDDisplayEntry(uuid: uuid, name: name, isSystem: isSystem)
        }
    }

    private func isSystemImage(name: String, path: String?) -> Bool {
        if let path {
            if path.hasPrefix("/System/") ||
                path.hasPrefix("/usr/lib/") ||
                path.hasPrefix("/usr/libexec/") ||
                path.hasPrefix("/Volumes/VOLUME/") {
                return true
            }
        }
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if n.hasPrefix("libsystem") || n.hasPrefix("libobjc") || n.hasPrefix("libdispatch") || n.hasPrefix("libc++") || n == "dyld" {
            return true
        }
        if n.hasPrefix("UIKit") ||
            n.hasPrefix("Foundation") ||
            n.hasPrefix("Core") ||
            n.hasPrefix("Quartz") ||
            n.hasPrefix("CFNetwork") ||
            n.hasPrefix("GraphicsServices") {
            return true
        }
        return false
    }
}

private extension CrashAnalyzerDSYMPanel {
    struct BuiltInSuggestion: Identifiable {
        let id: String
        let title: String
        let url: URL
        let hint: String
    }

    var builtInSuggestions: [BuiltInSuggestion] {
        #if os(macOS)
        let home = FileManager.default.homeDirectoryForCurrentUser
        let archives = home.appendingPathComponent("Library/Developer/Xcode/Archives", isDirectory: true)
        let derivedData = home.appendingPathComponent("Library/Developer/Xcode/DerivedData", isDirectory: true)
        // 某些场景（自定义打包/构建缓存）可能会把 dSYM 产物放到 Products 目录下
        let products = home.appendingPathComponent("Library/Developer/Xcode/Products", isDirectory: true)

        return [
            BuiltInSuggestion(id: "xcode-archives", title: "Xcode Archives", url: archives, hint: "Usually contains .xcarchive/dSYMs"),
            BuiltInSuggestion(id: "xcode-deriveddata", title: "DerivedData", url: derivedData, hint: "May contain dSYMs from custom builds"),
            BuiltInSuggestion(id: "xcode-products", title: "Products", url: products, hint: "In a few cases, may contain dSYMs")
        ]
        #else
        return []
        #endif
    }

    @ViewBuilder
    private func suggestionRow(_ suggestion: BuiltInSuggestion) -> some View {
        let exists = FileManager.default.fileExists(atPath: suggestion.url.path)
        let isAuthorized = isSuggestionAuthorized(suggestion.url)

        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.title)
                    .lineLimit(1)
                Text(suggestion.hint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)

            Button(isAuthorized ? "Authorized" : "Authorize") {
                authorizeFolder(suggestion.url)
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .disabled(isAuthorized)
            .help(isAuthorized
                ? "This directory is already in the authorization list"
                : (exists ? "Open the authorization picker (manual confirmation required)" : "Target directory does not exist; authorization will start from the most recently existing parent directory."))
        }
        .contentShape(Rectangle())
    }

    private func isSuggestionAuthorized(_ url: URL) -> Bool {
        let normalizedTarget = (try? url.resolvingSymlinksInPath().standardizedFileURL) ?? url.standardizedFileURL
        let targetPath = normalizedTarget.path.lowercased()
        let hostMappedTargetPath = hostMappedPathIfSandboxContainer(targetPath: targetPath)

        for folder in discovery.searchFolders {
            guard let resolved = try? SecurityScopedBookmarks.resolveBookmark(folder.bookmark) else { continue }
            let resolvedURL = (try? resolved.resolvingSymlinksInPath().standardizedFileURL) ?? resolved.standardizedFileURL
            let resolvedPath = resolvedURL.path.lowercased()
#if DEBUG
            print("[CrashAnalyzerDSYMPanel] isSuggestionAuthorized? suggestion=\(url.path) targetPath=\(targetPath) hostMappedTargetPath=\(hostMappedTargetPath ?? "nil") resolvedPath=\(resolvedPath)")
#endif
            // 1) 直接相等
            if resolvedPath == targetPath { return true }
            if let hostMappedTargetPath, resolvedPath == hostMappedTargetPath { return true }

            // 2) 推荐目录被授权的子目录（例如具体 .xcarchive / dSYMs）
            if resolvedPath.hasPrefix(targetPath + "/") { return true }
            if let hostMappedTargetPath,
               resolvedPath.hasPrefix(hostMappedTargetPath + "/") { return true }
        }
        return false
    }

    /// 将沙盒容器路径映射到宿主真实路径，避免把 `~/Library/Containers/<bundle>/Data/...` 和 `~/Library/...` 做严格比较。
    private func hostMappedPathIfSandboxContainer(targetPath: String) -> String? {
        guard let bundleId = Bundle.main.bundleIdentifier else { return nil }
        // Typical sandbox layout:
        // /Users/<user>/Library/Containers/<bundleId>/Data/Library/...
        // maps to host:
        // /Users/<user>/Library/...
        //
        // Important: we must include the trailing "/library" in the marker,
        // otherwise replacing ".../data" -> "/library" will produce ".../library/library/...".
        let marker = "/library/containers/\(bundleId.lowercased())/data/library"
        let lower = targetPath.lowercased()
        guard lower.contains(marker) else { return nil }
        return lower.replacingOccurrences(of: marker, with: "/library")
    }

    private func authorizeFolder(_ url: URL) {
        #if os(macOS)
        discoveryError = nil
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.title = L10n.t("Authorization Directory")
        panel.message = L10n.t("Choose directories for dSYM Discovery (manual confirmation required)")
        panel.prompt = L10n.t("Authorize")

        // NSOpenPanel 的起始目录设置有时会受软链接/不存在路径影响，做一次归一化并回退到最近存在的父目录。
        let startURL = startDirectoryURLForAuthorization(from: url)
        panel.directoryURL = startURL

        if panel.runModal() == .OK, let chosen = panel.url {
            do {
                try discovery.addSearchFolder(url: chosen)
                discovery.rescan()
                menuRefreshToken += 1
#if DEBUG
                debugAfterAuthorization(chosen: chosen)
#endif
            } catch {
                discoveryError = error.localizedDescription
            }
        }
        #endif
    }

    private func startDirectoryURLForAuthorization(from url: URL) -> URL {
        // 不依赖 fileExists：若当前 App 在沙盒环境下，该判断可能失真并导致错误回退到 ~/Library。
        // NSOpenPanel 本身会在无法定位时做合适的回退。
        let normalized = (try? url.resolvingSymlinksInPath()) ?? url
        return normalized
    }

    private func addSearchFolderCustom() {
        #if os(macOS)
        discoveryError = nil
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.title = L10n.t("Choose directories for dSYM Auto Discovery")
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try discovery.addSearchFolder(url: url)
                discovery.rescan()
                menuRefreshToken += 1
#if DEBUG
                debugAfterAuthorization(chosen: url)
#endif
            } catch {
                discoveryError = error.localizedDescription
            }
        }
        #endif
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
                revealFolderInFinder(folder)
                Button("Remove Authorization") { removeFolder(folder) }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .imageScale(.medium)
            }
            .menuStyle(.borderlessButton)
        }
    }

    private func resolvedFolderPathText(_ folder: DSYMAutoDiscoveryStore.SearchFolder) -> (text: String, isError: Bool) {
        do {
            let url = try SecurityScopedBookmarks.resolveBookmark(folder.bookmark)
            return (url.path, false)
        } catch {
            return ("Bookmark invalid (remove/re-authorize)", true)
        }
    }

    private func removeFolder(_ folder: DSYMAutoDiscoveryStore.SearchFolder) {
        guard let idx = discovery.searchFolders.firstIndex(of: folder) else { return }
        discovery.removeSearchFolders(at: IndexSet(integer: idx))
        // 取消授权后立刻重新扫描，刷新 UUID->dSYM 索引。
        discovery.rescan()
        menuRefreshToken += 1
#if DEBUG
        debugAfterRemoval()
#endif
    }

#if DEBUG
    private func debugLogSuggestionsToShow(suggestionsToShowCount: Int) -> some View {
        print("[CrashAnalyzerDSYMPanel] menu open suggestionsToShow=\(suggestionsToShowCount) currentAuthFolders=\(discovery.searchFolders.count)")
        for s in builtInSuggestions {
            let auth = isSuggestionAuthorized(s.url)
            print("  - suggestion '\(s.title)': url=\(s.url.path) authorized=\(auth)")
        }
        return EmptyView()
    }

    private func debugAfterAuthorization(chosen: URL) {
        print("[CrashAnalyzerDSYMPanel] authorized added path=\(chosen.path)")
        dumpResolvedSearchFolders()
    }

    private func debugAfterRemoval() {
        print("[CrashAnalyzerDSYMPanel] removed one auth folder")
        dumpResolvedSearchFolders()
    }

    private func dumpResolvedSearchFolders() {
        for (i, folder) in discovery.searchFolders.enumerated() {
            do {
                let resolved = try SecurityScopedBookmarks.resolveBookmark(folder.bookmark)
                let norm = (try? resolved.resolvingSymlinksInPath()) ?? resolved
                print("  auth[\(i)] displayName=\(folder.displayName) resolved=\(resolved.path) normalized=\(norm.path)")
            } catch {
                print("  auth[\(i)] displayName=\(folder.displayName) resolved=ERROR(\(error.localizedDescription))")
            }
        }
    }
#endif

    private func cleanupStaleBookmarksIfNeeded() {
        #if os(macOS)
        let staleIndices = discovery.searchFolders.enumerated().compactMap { idx, folder in
            // resolveBookmark 失败说明书签已失效
            (try? SecurityScopedBookmarks.resolveBookmark(folder.bookmark)) == nil ? idx : nil
        }
        guard !staleIndices.isEmpty else { return }
        discovery.removeSearchFolders(at: IndexSet(staleIndices))
        discovery.rescan()
        #endif
    }

    private func revealFolderInFinder(_ folder: DSYMAutoDiscoveryStore.SearchFolder) -> some View {
        #if os(macOS)
        return Button("Show in Finder") {
            do {
                let url = try SecurityScopedBookmarks.resolveBookmark(folder.bookmark)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                discoveryError = error.localizedDescription
            }
        }
        #else
        return EmptyView()
        #endif
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
                    Spacer(minLength: 0)
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
}

private struct UUIDDisplayEntry: Identifiable {
    var id: String { uuid }
    let uuid: String
    let name: String
    let isSystem: Bool
}

private struct DSYMInfoPresentation: Identifiable {
    var id: String { uuid }
    let uuid: String
    let imageName: String
    let url: URL
    let isManual: Bool
}

private struct DSYMInfoSheet: View {
    let info: DSYMInfoPresentation

    @EnvironmentObject private var state: SymbolicateWorkspaceState
    @Environment(\.dismiss) private var dismiss
    @State private var details: DSYMInspector.DSYMDetails?
    @State private var samples: [DSYMInspector.SampleSymbolication] = []
    @State private var manualHex: String = ""
    @State private var manualOffset: String = ""
    @State private var manualUseTextVMAddr: Bool = true
    @State private var manualResultText: String = ""
    @State private var manualErrorText: String = ""
    @State private var isManualResolving: Bool = false

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(info.imageName)
                            .font(.headline)
                        Text(info.isManual ? "Source: Manual selection" : "Source: Auto-matched")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 10)
                }

                GroupBox("Basic Information") {
                    VStack(alignment: .leading, spacing: 10) {
                        // 概览
                        if let details {
                            Text(details.capabilities.summary)
                                .font(.subheadline.weight(.semibold))
                            HStack(spacing: 8) {
                                capabilityPill(title: "Debug info", ok: details.capabilities.hasDebugInfo)
                                capabilityPill(title: "File:Line", ok: details.capabilities.hasDebugLine)
                                capabilityPill(title: "Apple accel", ok: details.capabilities.hasAppleAccelerators)
                                capabilityPill(title: "Aranges", ok: details.capabilities.hasAranges)
                            }
                        }

                        Divider().opacity(0.2)

                        // UUID
                        Text("UUID")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(info.uuid)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if let d = details, let binUUID = d.file.uuid, !binUUID.isEmpty {
                            let ok = (binUUID == info.uuid)
                            Text(L10n.tFormat(
                                "dSYM Mach-O UUID: %@ %@",
                                binUUID,
                                ok ? L10n.t("(Matched)") : L10n.t("(Unmatched)")
                            ))
                                .font(.caption2)
                                .foregroundStyle(ok ? Color.green : Color.red)
                                .textSelection(.enabled)
                        }

                        Divider().opacity(0.2)

                        if let details {
                            if !details.arch.architectures.isEmpty {
                                Text(
                                    L10n.tFormat(
                                        "Mach-O Architectures: %@",
                                        details.arch.architectures.joined(separator: ", ")
                                    )
                                )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else if details.arch.isFat {
                                Text("Mach-O Architectures: (fat binary)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Mach-O Architectures: -")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if details.dwarfSections.dwarfSegmentFound {
//                                let names = details.dwarfSections.sectionNames
//                                let list = names.isEmpty ? "__DWARF" : names.prefix(8).joined(separator: ", ")
//                                Text("Mach-O __DWARF Sections: \(list)")
//                                    .font(.caption2)
//                                    .foregroundStyle(.secondary)
//                                    .textSelection(.enabled)
                            } else {
                                Text("Mach-O __DWARF: Not found (may not be a valid DWARF binary)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            if details.session.canOpen {
                                let arch = details.session.architecture ?? "-"
                                let slice = (details.session.universalBinaryIndex != nil && details.session.universalBinaryCount != nil)
                                    ? "\(details.session.universalBinaryIndex!)/\(details.session.universalBinaryCount!)"
                                    : "-"
                                Text(L10n.tFormat(
                                    "Swift-dwarf session: Openable (arch=%@, slice=%@)",
                                    arch,
                                    slice
                                ))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(L10n.tFormat(
                                    "Swift-dwarf session: Failed to open: %@",
                                    details.session.errorText ?? "unknown"
                                ))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Text("Loading…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Divider().opacity(0.2)

                        // Details + path
                        Text("Details / Path")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        if let details {
                            if let size = details.file.fileSize {
                                Text(L10n.tFormat(
                                    "DWARF file size: %@",
                                    ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
                                ))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(L10n.t("DWARF file size: -"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let d = details.file.modificationDate {
                                Text(L10n.tFormat("Last modified: %@", format(date: d)))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(L10n.t("Last modified: -"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text(info.url.path)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
                }

                GroupBox("Manual Symbolication") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            TextField("Address (hex, e.g. 0x1044c43b0)", text: $manualHex)
                                .textFieldStyle(.roundedBorder)
                            Button(isManualResolving ? "Symbolicating…" : "Symbolicate") {
                                runManualSymbolication()
                            }
                            .disabled(isManualResolving || manualHex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }

                        HStack(spacing: 10) {
                            Toggle("Use __TEXT vmaddr + imageOffset", isOn: $manualUseTextVMAddr)
                                .toggleStyle(.switch)
                            TextField("imageOffset (optional, decimal)", text: $manualOffset)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 220)
                            Spacer(minLength: 0)
                        }

                        if !manualErrorText.isEmpty {
                            Text(manualErrorText)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .textSelection(.enabled)
                        }

                        if !manualResultText.isEmpty {
                            Text(manualResultText)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
                }

                HStack(spacing: 10) {
                    #if os(macOS)
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([info.url])
                    }
                    #endif
                    Spacer()
                }
            }
            .padding(16)
        }
        .frame(minWidth: 520, minHeight: 320)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
        .task {
            // 读取 dSYM 详情时也需要安全作用域（自动发现的路径可能来自书签根目录）
            let stop = DSYMAutoDiscoveryStore.shared.startAccessingIfNeeded(for: info.url)
            defer { stop?() }
            details = DSYMInspector.inspect(dsymURL: info.url)

            // 从当前 crash 中抽取该 UUID 的若干 pc/off 做样例符号化
            let addrs = samplePCsAndOffsets(forUUID: info.uuid)
            samples = DSYMInspector.sampleSymbolicate(dsymURL: info.url, pcs: addrs.pcs, imageOffsets: addrs.offsets)
        }
    }

    private func capabilityPill(title: String, ok: Bool) -> some View {
        Text(ok ? title : "\(title)")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background((ok ? Color.green : Color.secondary).opacity(0.14))
            .foregroundStyle(ok ? Color.green : Color.secondary)
            .clipShape(Capsule())
    }

    private func samplePCsAndOffsets(forUUID uuid: String) -> (pcs: [UInt64], offsets: [Int?]) {
        guard let crash = state.crashLog else { return ([], []) }
        guard let model = state.symbolicatedModel ?? crash.model else { return ([], []) }
        guard let img = model.images.first(where: { ($0.uuid ?? "") == uuid }) else { return ([], []) }
        let imageName = img.name

        let frames = model.threads
            .first(where: { $0.triggered })?.frames ?? model.threads.first?.frames ?? []

        let picked = frames.filter { $0.imageName == imageName }.prefix(3)
        return (picked.map { $0.address }, picked.map { $0.imageOffset })
    }

    private func format(date: Date) -> String {
        let f = DateFormatter()
        f.locale = .current
        f.dateStyle = .medium
        f.timeStyle = .medium
        return f.string(from: date)
    }

    private func runManualSymbolication() {
        manualErrorText = ""
        manualResultText = ""
        isManualResolving = true

        let stop = DSYMAutoDiscoveryStore.shared.startAccessingIfNeeded(for: info.url)

        Task.detached(priority: .userInitiated) {
            defer { stop?() }

            let hex = manualHex.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let pc = parseHexUInt64(hex) else {
                await MainActor.run {
                    isManualResolving = false
                    manualErrorText = L10n.tFormat("Invalid address format: %@", hex)
                }
                return
            }

            let offsetInt: Int? = {
                let s = manualOffset.trimmingCharacters(in: .whitespacesAndNewlines)
                if s.isEmpty { return nil }
                return Int(s)
            }()

            let addrUsed: UInt64 = {
                if manualUseTextVMAddr, let off = offsetInt, let vm = DSYMInspector.readTextVMAddrForUI(dsymURL: info.url) {
                    return vm &+ UInt64(off)
                }
                return pc
            }()

            let res = DSYMInspector.symbolicate(dsymURL: info.url, address: addrUsed)
            await MainActor.run {
                isManualResolving = false
                switch res {
                case .success(let r):
                    let fn = (r.function?.isEmpty == false) ? r.function! : L10n.t("(No function name)")
                    let fl: String = {
                        if let f = r.file, !f.isEmpty, let l = r.line { return "\(f):\(l)" }
                        return L10n.t("(No file line number)")
                    }()
                    manualResultText = String(format: "pc=0x%016llx  used=0x%016llx\n%@\n%@", pc, addrUsed, fn, fl)
                case .failure(let err):
                    manualErrorText = err.localizedDescription
                }
            }
        }
    }

    private func parseHexUInt64(_ s: String) -> UInt64? {
        let t = s.lowercased().hasPrefix("0x") ? String(s.dropFirst(2)) : s
        return UInt64(t, radix: 16)
    }
}

struct CrashAnalyzerInsightPanel: View {
    @EnvironmentObject private var state: SymbolicateWorkspaceState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Insight Analysis")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.secondary)

            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.yellow.opacity(0.9))
                        Text("Anomaly Reason Diagnosis")
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                    }

                    if let crash = state.crashLog, let model = state.symbolicatedModel ?? crash.model {
                        Text(L10n.tFormat("Detected %@.", crash.fileName))
                            .font(.system(size: 11))
                            .foregroundStyle(Color.secondary)

                        Text(L10n.tFormat("Crash type: %@", model.overview.exceptionType))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color.secondary)

                        if let first = model.threads.first(where: { $0.triggered })?.frames.first,
                           let fn = first.symbol, !fn.isEmpty {
                            Text(L10n.tFormat("Top Frame：%@", fn))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Color.secondary)
                                .lineLimit(2)
                        }
                    } else {
                        Text("Show the diagnostic summary after opening a crash file.")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.secondary)
                    }
                }
                .padding(12)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
    }
}

