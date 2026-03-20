//
//  DSYMAutoDiscoveryStore.swift
//  SymPro
//

import Foundation
import Combine

final class DSYMAutoDiscoveryStore: NSObject, ObservableObject {
    static let shared = DSYMAutoDiscoveryStore()

    struct SearchFolder: Identifiable, Codable, Hashable {
        let id: UUID
        var displayName: String
        var bookmark: Data
        var addedAt: Date

        init(id: UUID = UUID(), displayName: String, bookmark: Data, addedAt: Date = Date()) {
            self.id = id
            self.displayName = displayName
            self.bookmark = bookmark
            self.addedAt = addedAt
        }
    }

    struct DSYMIndexRecord: Codable, Hashable {
        var uuid: String
        var folderID: UUID
        /// 相对 SearchFolder 根目录的相对路径（例如: "SYM.app.dSYM" 或 "Some.xcarchive/dSYMs/XXX.dSYM"）
        var relativePath: String
        var displayName: String
        var lastSeenAt: Date
    }

    enum ScanState: Equatable {
        case idle
        case scanning(progressText: String)
        case failed(message: String)
        case finished(found: Int)
    }

    @Published private(set) var searchFolders: [SearchFolder] = []
    @Published private(set) var indexByUUID: [String: DSYMIndexRecord] = [:]
    @Published private(set) var scanState: ScanState = .idle

    private let storageURL: URL
    private let queue = DispatchQueue(label: "com.sympro.dsym.discovery", qos: .userInitiated)
    private let metadataQueryRunner = MetadataQueryRunner()

    private struct Persisted: Codable {
        var folders: [SearchFolder]
        var index: [String: DSYMIndexRecord]
    }

    override init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("SymPro", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        storageURL = dir.appendingPathComponent("dsym_discovery.json")
        super.init()
        load()
    }

    func addSearchFolder(url: URL) throws {
        let bookmark = try SecurityScopedBookmarks.makeBookmark(for: url)
        let displayName = url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
        if searchFolders.contains(where: { $0.displayName == displayName }) == false {
            searchFolders.append(SearchFolder(displayName: displayName, bookmark: bookmark))
            save()
        }
    }

    func removeSearchFolders(at offsets: IndexSet) {
        let validOffsets = offsets.filter { $0 < searchFolders.count }.sorted(by: >)
        for i in validOffsets {
            searchFolders.remove(at: i)
        }
        save()
    }

    /// 根据 UUID 查找 dSYM URL（需要在访问作用域内使用）。
    func resolveDSYMURL(forUUID uuid: String) -> (url: URL, folderID: UUID)? {
        guard let rec = indexByUUID[uuid],
              let folder = searchFolders.first(where: { $0.id == rec.folderID }) else { return nil }
        do {
            let root = try SecurityScopedBookmarks.resolveBookmark(folder.bookmark)
            let url = root.appendingPathComponent(rec.relativePath)
            return (url, folder.id)
        } catch {
            return nil
        }
    }

    /// 尝试为任意 URL 开启 security scope。
    /// - 优先：直接对 url 调用 startAccessingSecurityScopedResource（适用于用户手动选择的文件/包）
    /// - 兜底：若失败，则尝试匹配到某个已授权的 searchFolder root，并对 root 开启 scope
    /// - Returns: stop closure（调用方务必执行）
    func startAccessingIfNeeded(for url: URL) -> (() -> Void)? {
        if let stop = SecurityScopedBookmarks.startAccessing(url) {
            return stop
        }
        // 兜底：对所属 root 开启 scope（常见于“从 bookmark root 拼出来的子路径”）
        for folder in searchFolders {
            guard let root = try? SecurityScopedBookmarks.resolveBookmark(folder.bookmark) else { continue }
            if url.path.hasPrefix(root.path) {
                return SecurityScopedBookmarks.startAccessing(root)
            }
        }
        return nil
    }

    /// 开始扫描所有搜索目录（后台增量建立 UUID->dSYM 索引）。
    func rescan() {
        guard !searchFolders.isEmpty else {
            scanState = .finished(found: 0)
            return
        }
        scanState = .scanning(progressText: L10n.t("Preparing scan…"))

        let foldersSnapshot = searchFolders
        queue.async { [weak self] in
            guard let self else { return }
            var newIndex: [String: DSYMIndexRecord] = self.indexByUUID
            var found = 0
            var errorCount = 0
            var didUseMetadataQuery = false

            // 0) 先尝试用 Spotlight（NSMetadataQuery）快速定位 .dSYM 候选，再解析 UUID 建索引
            do {
                DispatchQueue.main.async {
                    self.scanState = .scanning(progressText: L10n.t("Spotlight scanning .dSYMs…"))
                }
                let roots = try self.resolveAccessibleRoots(for: foldersSnapshot)
                let dsymURLs = self.metadataQueryRunner.searchDSYMPackages(in: roots.map(\.url))
                if !dsymURLs.isEmpty {
                    didUseMetadataQuery = true
                    for dsym in dsymURLs {
                        // 归属到哪个 SearchFolder（按路径前缀匹配）
                        guard let owner = roots.first(where: { dsym.path.hasPrefix($0.url.path) }) else { continue }
                        if let uuid = DSYMUUIDResolver.resolveUUID(at: dsym)?.uuidString,
                           let rel = dsym.path.removingPrefix(owner.url.path + "/") ?? dsym.path.removingPrefix(owner.url.path) {
                            newIndex[uuid] = DSYMIndexRecord(
                                uuid: uuid,
                                folderID: owner.folder.id,
                                relativePath: rel,
                                displayName: dsym.lastPathComponent,
                                lastSeenAt: Date()
                            )
                            found += 1
                        }
                    }
                }
                // 结束访问
                roots.forEach { $0.stop() }
            } catch {
                // 若 Spotlight/书签解析失败，不影响后续兜底遍历
            }

            // 1) 兜底：如果 Spotlight 没有命中（或命中很少），继续走原有遍历扫描，保证覆盖
            if found == 0 && didUseMetadataQuery == false {
                // no-op: 直接进入原遍历
            }

            for (i, folder) in foldersSnapshot.enumerated() {
                DispatchQueue.main.async {
                    self.scanState = .scanning(progressText: "Scanning \(i + 1)/\(foldersSnapshot.count): \(folder.displayName)")
                }
                do {
                    let root = try SecurityScopedBookmarks.resolveBookmark(folder.bookmark)
                    guard let stop = SecurityScopedBookmarks.startAccessing(root) else { continue }
                    defer { stop() }

                    let fm = FileManager.default
                    // 1) 针对 Xcode Archives 目录：按层级扫描（更稳定、更快）
                    if root.lastPathComponent == "Archives" {
                        let dateDirs = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
                        for dateDir in dateDirs {
                            let isDir = (try? dateDir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                            guard isDir else { continue }
                            let archives = (try? fm.contentsOfDirectory(at: dateDir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
                            for a in archives where a.pathExtension == "xcarchive" {
                                let dsymsDir = a.appendingPathComponent("dSYMs", isDirectory: true)
                                let list = (try? fm.contentsOfDirectory(at: dsymsDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
                                for dsym in list where dsym.pathExtension == "dSYM" {
                                    if let uuid = DSYMUUIDResolver.resolveUUID(at: dsym)?.uuidString,
                                       let rel = dsym.path.removingPrefix(root.path + "/") ?? dsym.path.removingPrefix(root.path) {
                                        newIndex[uuid] = DSYMIndexRecord(
                                            uuid: uuid,
                                            folderID: folder.id,
                                            relativePath: rel,
                                            displayName: dsym.lastPathComponent,
                                            lastSeenAt: Date()
                                        )
                                        found += 1
                                    }
                                }
                            }
                        }
                    } else {
                        // 2) 通用扫描：遍历找到 .dSYM / .xcarchive
                        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .nameKey]
                        let en = fm.enumerator(
                            at: root,
                            includingPropertiesForKeys: keys,
                            options: [.skipsHiddenFiles],
                            errorHandler: { _, _ in
                                errorCount += 1
                                return true
                            }
                        )

                        while let u = en?.nextObject() as? URL {
                            if u.pathExtension == "dSYM" {
                                if let uuid = DSYMUUIDResolver.resolveUUID(at: u)?.uuidString,
                                   let rel = u.path.removingPrefix(root.path + "/") ?? u.path.removingPrefix(root.path) {
                                    newIndex[uuid] = DSYMIndexRecord(
                                        uuid: uuid,
                                        folderID: folder.id,
                                        relativePath: rel,
                                        displayName: u.lastPathComponent,
                                        lastSeenAt: Date()
                                    )
                                    found += 1
                                }
                                en?.skipDescendants()
                            } else if u.pathExtension == "xcarchive" {
                                let dsymsDir = u.appendingPathComponent("dSYMs", isDirectory: true)
                                let list = (try? fm.contentsOfDirectory(at: dsymsDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
                                for dsym in list where dsym.pathExtension == "dSYM" {
                                    if let uuid = DSYMUUIDResolver.resolveUUID(at: dsym)?.uuidString,
                                       let rel = dsym.path.removingPrefix(root.path + "/") ?? dsym.path.removingPrefix(root.path) {
                                        newIndex[uuid] = DSYMIndexRecord(
                                            uuid: uuid,
                                            folderID: folder.id,
                                            relativePath: rel,
                                            displayName: dsym.lastPathComponent,
                                            lastSeenAt: Date()
                                        )
                                        found += 1
                                    }
                                }
                                en?.skipDescendants()
                            }
                        }
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.scanState = .failed(message: error.localizedDescription)
                    }
                    return
                }
            }

            DispatchQueue.main.async {
                self.indexByUUID = newIndex
                if errorCount > 0 {
                    self.scanState = .finished(found: found)
                } else {
                    self.scanState = .finished(found: found)
                }
                self.save()
            }
        }
    }

    private typealias AccessibleRoot = (folder: SearchFolder, url: URL, stop: () -> Void)

    /// 解析书签并进入 security scope，返回可访问的根目录列表（调用方负责 stop）。
    private func resolveAccessibleRoots(for folders: [SearchFolder]) throws -> [AccessibleRoot] {
        var out: [AccessibleRoot] = []
        out.reserveCapacity(folders.count)
        for f in folders {
            let root = try SecurityScopedBookmarks.resolveBookmark(f.bookmark)
            guard let stop = SecurityScopedBookmarks.startAccessing(root) else { continue }
            out.append((folder: f, url: root, stop: stop))
        }
        return out
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        guard let persisted = try? JSONDecoder().decode(Persisted.self, from: data) else { return }
        searchFolders = persisted.folders
        indexByUUID = persisted.index
    }

    private func save() {
        let persisted = Persisted(folders: searchFolders, index: indexByUUID)
        guard let data = try? JSONEncoder().encode(persisted) else { return }
        try? data.write(to: storageURL, options: [.atomic])
    }
}

private extension String {
    func removingPrefix(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return String(dropFirst(prefix.count))
    }
}

/// 用 NSMetadataQuery（Spotlight）快速定位候选文件，再由上层解析 UUID 建索引。
private final class MetadataQueryRunner: NSObject {
    private let query = NSMetadataQuery()
    private var completion: (([URL]) -> Void)?

    override init() {
        super.init()
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(handleFinish(_:)), name: .NSMetadataQueryDidFinishGathering, object: query)
        nc.addObserver(self, selector: #selector(handleFinish(_:)), name: .NSMetadataQueryDidUpdate, object: query)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// 在 scopes 中搜索 *.dSYM（包），返回候选 URL。该方法会在内部阻塞等待 query 完成（带超时）。
    func searchDSYMPackages(in scopes: [URL]) -> [URL] {
        guard !scopes.isEmpty else { return [] }

        // 仅通过名称筛选 dSYM 包；UUID 仍需上层读取 Mach-O 精确匹配。
        let predicate = NSPredicate(format: "kMDItemFSName == '*.dSYM'")

        let sem = DispatchSemaphore(value: 0)
        var results: [URL] = []

        DispatchQueue.main.sync {
            self.query.stop()
            self.query.disableUpdates()
            self.query.searchScopes = scopes
            self.query.predicate = predicate
            self.completion = { urls in
                results = urls
                sem.signal()
            }
            self.query.start()
        }

        // 最多等 2 秒，避免 Spotlight 不可用时卡住扫描流程
        _ = sem.wait(timeout: .now() + 2.0)

        DispatchQueue.main.async {
            self.query.stop()
            self.query.enableUpdates()
            self.completion = nil
        }

        // 去重 + 只保留存在的路径
        var seen = Set<String>()
        return results.filter { url in
            let p = url.path
            guard !p.isEmpty, FileManager.default.fileExists(atPath: p) else { return false }
            if seen.contains(p) { return false }
            seen.insert(p)
            return true
        }
    }

    @objc private func handleFinish(_ notification: Notification) {
        guard let comp = completion else { return }
        let items = query.results as? [NSMetadataItem] ?? []
        let urls: [URL] = items.compactMap { item in
            guard let path = item.value(forAttribute: kMDItemPath as String) as? String else { return nil }
            return URL(fileURLWithPath: path)
        }
        comp(urls)
    }
}

