//
//  SecurityScopedBookmarks.swift
//  SymPro
//

import Foundation

enum SecurityScopedBookmarks {
    static func makeBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    static func resolveBookmark(_ data: Data) throws -> URL {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        // stale 时由上层决定是否重建；这里仍返回可用 url
        return url
    }

    /// 开启安全作用域访问，返回一个关闭 closure（调用方务必执行）。
    static func startAccessing(_ url: URL) -> (() -> Void)? {
        let ok = url.startAccessingSecurityScopedResource()
        guard ok else { return nil }
        return { url.stopAccessingSecurityScopedResource() }
    }
}

