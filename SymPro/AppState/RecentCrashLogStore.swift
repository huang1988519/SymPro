//
//  RecentCrashLogStore.swift
//  SymPro
//

import Foundation
import Combine

final class RecentCrashLogStore: NSObject, ObservableObject {
    static let shared = RecentCrashLogStore()

    struct RecentCrashLog: Identifiable, Codable, Hashable {
        let id: UUID
        var fileName: String
        var bookmark: Data
        var lastOpenedAt: Date

        init(id: UUID = UUID(), fileName: String, bookmark: Data, lastOpenedAt: Date = Date()) {
            self.id = id
            self.fileName = fileName
            self.bookmark = bookmark
            self.lastOpenedAt = lastOpenedAt
        }
    }

    @Published private(set) var items: [RecentCrashLog] = []

    private let storageURL: URL

    private struct Persisted: Codable {
        var items: [RecentCrashLog]
    }

    override init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("SymPro", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        storageURL = dir.appendingPathComponent("recent_crashlogs.json")
        super.init()
        load()
    }

    @MainActor
    func add(url: URL) {
        let fileName = url.lastPathComponent
        guard let bookmark = try? SecurityScopedBookmarks.makeBookmark(for: url) else { return }

        // 去重：同名文件（更贴合用户心智），更新为最新 bookmark 与时间
        if let idx = items.firstIndex(where: { $0.fileName == fileName }) {
            items[idx].bookmark = bookmark
            items[idx].lastOpenedAt = Date()
        } else {
            items.insert(RecentCrashLog(fileName: fileName, bookmark: bookmark), at: 0)
        }

        // 限制长度
        if items.count > 20 { items = Array(items.prefix(20)) }
        save()
    }

    func resolveURL(for item: RecentCrashLog) -> URL? {
        (try? SecurityScopedBookmarks.resolveBookmark(item.bookmark))
    }

    @MainActor
    func removeAll() {
        items = []
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let p = try? JSONDecoder().decode(Persisted.self, from: data)
        else { return }
        items = p.items.sorted(by: { $0.lastOpenedAt > $1.lastOpenedAt })
    }

    private func save() {
        let p = Persisted(items: items)
        guard let data = try? JSONEncoder().encode(p) else { return }
        try? data.write(to: storageURL, options: [.atomic])
    }
}

