import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Shared UI for managing dSYM auto-discovery directories.
struct DSYMDiscoveryDirectoriesCard: View {
    @ObservedObject private var discovery = DSYMAutoDiscoveryStore.shared

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
                            ForEach(suggestionsToShow, id: \.id) { suggestion in
                                Button("Recommended: \(suggestion.title)") {
                                    authorizeFolder(suggestion.url)
                                }
                            }
                            if !suggestionsToShow.isEmpty { Divider() }
                            Button(L10n.t("Custom directory…")) {
                                addSearchFolderCustom()
                            }
                        } label: {
                            Label(L10n.t("Add"), systemImage: "plus.circle.fill")
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
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
        .task {
            guard !didAutoCleanupStaleBookmarks else { return }
            didAutoCleanupStaleBookmarks = true
            cleanupStaleBookmarksIfNeeded()
        }
    }
}

private extension DSYMDiscoveryDirectoriesCard {
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

    func dsymFolderRowInCard(_ folder: DSYMAutoDiscoveryStore.SearchFolder) -> some View {
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

    func resolvedFolderPathText(_ folder: DSYMAutoDiscoveryStore.SearchFolder) -> (text: String, isError: Bool) {
        do {
            let url = try SecurityScopedBookmarks.resolveBookmark(folder.bookmark)
            return (url.path, false)
        } catch {
            return ("Bookmark invalid (remove/re-authorize)", true)
        }
    }

    func removeFolder(_ folder: DSYMAutoDiscoveryStore.SearchFolder) {
        guard let idx = discovery.searchFolders.firstIndex(of: folder) else { return }
        discovery.removeSearchFolders(at: IndexSet(integer: idx))
        discovery.rescan()
        menuRefreshToken &+= 1
    }

    func revealFolderInFinder(_ folder: DSYMAutoDiscoveryStore.SearchFolder) -> some View {
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

    var discoveryStatusRow: some View {
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

    func cleanupStaleBookmarksIfNeeded() {
        #if os(macOS)
        let staleIndices = discovery.searchFolders.enumerated().compactMap { idx, folder in
            (try? SecurityScopedBookmarks.resolveBookmark(folder.bookmark)) == nil ? idx : nil
        }
        guard !staleIndices.isEmpty else { return }
        discovery.removeSearchFolders(at: IndexSet(staleIndices))
        discovery.rescan()
        #endif
    }

    func isSuggestionAuthorized(_ url: URL) -> Bool {
        let normalizedTarget = (try? url.resolvingSymlinksInPath().standardizedFileURL) ?? url.standardizedFileURL
        let targetPath = normalizedTarget.path.lowercased()
        let hostMappedTargetPath = hostMappedPathIfSandboxContainer(targetPath: targetPath)

        for folder in discovery.searchFolders {
            guard let resolved = try? SecurityScopedBookmarks.resolveBookmark(folder.bookmark) else { continue }
            let resolvedURL = (try? resolved.resolvingSymlinksInPath().standardizedFileURL) ?? resolved.standardizedFileURL
            let resolvedPath = resolvedURL.path.lowercased()
            if resolvedPath == targetPath { return true }
            if let hostMappedTargetPath, resolvedPath == hostMappedTargetPath { return true }
            if resolvedPath.hasPrefix(targetPath + "/") { return true }
            if let hostMappedTargetPath, resolvedPath.hasPrefix(hostMappedTargetPath + "/") { return true }
        }
        return false
    }

    func hostMappedPathIfSandboxContainer(targetPath: String) -> String? {
        guard let bundleId = Bundle.main.bundleIdentifier else { return nil }
        let marker = "/library/containers/\(bundleId.lowercased())/data/library"
        let lower = targetPath.lowercased()
        guard lower.contains(marker) else { return nil }
        return lower.replacingOccurrences(of: marker, with: "/library")
    }

    func authorizeFolder(_ url: URL) {
        #if os(macOS)
        discoveryError = nil
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.title = L10n.t("Authorization Directory")
        panel.message = L10n.t("Choose directories for dSYM Discovery (manual confirmation required)")
        panel.prompt = L10n.t("Authorize")
        panel.directoryURL = startDirectoryURLForAuthorization(from: url)

        if panel.runModal() == .OK, let chosen = panel.url {
            do {
                try discovery.addSearchFolder(url: chosen)
                discovery.rescan()
                menuRefreshToken &+= 1
            } catch {
                discoveryError = error.localizedDescription
            }
        }
        #endif
    }

    func startDirectoryURLForAuthorization(from url: URL) -> URL {
        let normalized = (try? url.resolvingSymlinksInPath()) ?? url
        return normalized
    }

    func addSearchFolderCustom() {
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
                menuRefreshToken &+= 1
            } catch {
                discoveryError = error.localizedDescription
            }
        }
        #endif
    }
}

