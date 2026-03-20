//
//  SymbolicateWorkspaceState.swift
//  SymPro
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers
import AppKit
import Combine

final class SymbolicateWorkspaceState: NSObject, ObservableObject {
    @Published var crashLog: CrashLog?
    @Published var symbolicatedModel: CrashReportModel?
    @Published var dsymItems: [DSYMItem] = []
    /// 每个 Mach-O（按 UUID）独立选择的 dSYM 路径
    @Published var selectedDSYMByImageUUID: [String: URL] = [:]
    /// 手动覆盖（优先级最高）。清除后会回退到自动匹配结果。
    @Published var manualDSYMOverrideByImageUUID: [String: URL] = [:]
    @Published var isSymbolicating = false
    @Published var symbolicationError: String?
    @Published var symbolicationErrorKind: SymbolicationError.Kind?
    @Published var symbolicatedText: String = ""
    @Published var isLoadingCrashLog: Bool = false

    private let symbolicationService = SymbolicationService()
    private var symbolicationTask: Task<Void, Never>?
    private var openCrashLogTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []
    private var lastAutoScanCrashID: UUID? = nil

    override init() {
        super.init()

        // 当自动发现索引更新（扫描完成）后，若当前崩溃仍有缺失 UUID，则自动重新计算选择。
        DSYMAutoDiscoveryStore.shared.$scanState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                guard case .finished = state else { return }
                Task { @MainActor in
                    self.autoMatchDSYMIfNeeded(triggerScan: false)
                }
            }
            .store(in: &cancellables)
    }

    @MainActor
    func resetWorkspace() {
        openCrashLogTask?.cancel()
        symbolicationTask?.cancel()
        crashLog = nil
        symbolicatedModel = nil
        symbolicatedText = ""
        symbolicationError = nil
        symbolicationErrorKind = nil
        isSymbolicating = false
        isLoadingCrashLog = false
        selectedDSYMByImageUUID = [:]
        manualDSYMOverrideByImageUUID = [:]
        // 保留 dsymItems 与 discovery 索引，避免每次重开窗口都需要重新导入/扫描
        refreshDSYMMatchState()
    }

    struct DSYMItem: Identifiable {
        let id: UUID
        let path: URL
        let displayName: String
        let uuid: UUID?
        var matchesCrashUUIDs: Bool

        init(from info: DSYMInfo, crashUUIDs: [String]) {
            id = info.id
            path = info.path
            displayName = info.displayName
            uuid = info.uuid
            let uuidStr = info.uuid?.uuidString ?? ""
            matchesCrashUUIDs = crashUUIDs.contains(uuidStr) || crashUUIDs.contains(uuidStr.replacingOccurrences(of: "-", with: "").uppercased())
        }
    }

    @MainActor
    func pickCrashLog() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText]
        if let crash = UTType(filenameExtension: "crash") { panel.allowedContentTypes.append(crash) }
        if let ips = UTType(filenameExtension: "ips") { panel.allowedContentTypes.append(ips) }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = L10n.t("Select Crash Logs")
        if panel.runModal() == .OK, let url = panel.url {
            openCrashLog(url)
        }
    }

    @MainActor
    func handleCrashLogDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { [weak self] url, _ in
            guard let url = url as? URL else { return }
            Task { @MainActor in
                self?.openCrashLog(url)
            }
        }
        return true
    }

    @MainActor
    func openCrashLog(_ url: URL) {
        openCrashLogTask?.cancel()
        symbolicationError = nil
        isLoadingCrashLog = true

        openCrashLogTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            let needsSecurityScope = url.startAccessingSecurityScopedResource()
            defer { if needsSecurityScope { url.stopAccessingSecurityScopedResource() } }

            guard !Task.isCancelled else { return }
            guard let data = try? Data(contentsOf: url) else {
                await MainActor.run { self.isLoadingCrashLog = false }
                return
            }
            guard !Task.isCancelled else { return }
            guard let crash = CrashLogParser.parse(url: url, data: data) else {
                await MainActor.run { self.isLoadingCrashLog = false }
                return
            }

            await MainActor.run {
                RecentCrashLogStore.shared.add(url: url)
                self.crashLog = crash
                self.symbolicatedModel = nil
                self.symbolicationError = nil
                self.symbolicationErrorKind = nil
                self.selectedDSYMByImageUUID = [:]
                self.manualDSYMOverrideByImageUUID = [:]
                self.refreshDSYMMatchState()
                self.recomputeResolvedDSYMSelection()
                self.lastAutoScanCrashID = crash.id
                self.autoMatchDSYMIfNeeded(triggerScan: true)
                // 导入后立即显示原始 Translated Report（保持 Apple 崩溃报告格式）
                self.symbolicatedText = ReportDisplayStyle.translatedReportOnly(crash.rawText)
                self.isLoadingCrashLog = false
            }
        }
    }

    /// 打开崩溃文件后自动匹配：
    /// - 先用已有 discovery 索引填充（recompute 已做）
    /// - 若仍有缺失且用户已配置了授权目录，则自动触发 rescan()
    @MainActor
    private func autoMatchDSYMIfNeeded(triggerScan: Bool) {
        guard let crash = crashLog else { return }
        // 先确保用当前索引/导入 dSYM/手动覆盖计算一次
        recomputeResolvedDSYMSelection()

        let missing = crash.uuidList.filter { selectedDSYMByImageUUID[$0] == nil }
        guard !missing.isEmpty else { return }

        // 只有在当前 crash 的首次导入时才触发自动扫描，避免频繁 rescan
        guard triggerScan, lastAutoScanCrashID == crash.id else { return }
        guard !DSYMAutoDiscoveryStore.shared.searchFolders.isEmpty else { return }

        // 若正在扫描中，则等待 scanState.finished 的订阅回调即可
        if case .scanning = DSYMAutoDiscoveryStore.shared.scanState { return }

        DSYMAutoDiscoveryStore.shared.rescan()
    }

    @MainActor
    func pickDSYM() {
        let panel = NSOpenPanel()
        // 不设置 allowedContentTypes，以便可选 .dSYM / .xcarchive 等包（在 macOS 上多为目录形态）
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.treatsFilePackagesAsDirectories = true
        panel.title = L10n.t("Select dSYMs or .xcarchive")
        if panel.runModal() == .OK {
            for url in panel.urls {
                addDSYM(url: url)
            }
        }
    }

    @MainActor
    func handleDSYMDrop(providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { [weak self] url, _ in
                guard let url = url as? URL else { return }
                Task { @MainActor in
                    self?.addDSYM(url: url)
                }
            }
            accepted = true
        }
        return accepted
    }

    private func addDSYM(url: URL) {
        let needsSecurityScope = url.startAccessingSecurityScopedResource()
        defer { if needsSecurityScope { url.stopAccessingSecurityScopedResource() } }

        let path = url
        if url.pathExtension == "xcarchive" {
            let dsymsDir = url.appendingPathComponent("dSYMs", isDirectory: true)
            let dsyms = (try? FileManager.default.contentsOfDirectory(at: dsymsDir, includingPropertiesForKeys: nil)) ?? []
            for d in dsyms where d.pathExtension == "dSYM" {
                addDSYM(url: d)
            }
            return
        }
        if url.pathExtension != "dSYM" { return }
        let displayName = url.lastPathComponent
        let uuid = DSYMUUIDResolver.resolveUUID(at: path)
        let info = DSYMInfo(path: path, displayName: displayName, uuid: uuid)
        let crashUUIDs = crashLog?.uuidList ?? []
        let item = DSYMItem(from: info, crashUUIDs: crashUUIDs)
        if !dsymItems.contains(where: { $0.path == path }) {
            dsymItems.append(item)
        }
        recomputeResolvedDSYMSelection()
    }

    @MainActor
    func removeDSYMItems(at offsets: IndexSet) {
        let validOffsets = offsets.filter { $0 < dsymItems.count }
        dsymItems.remove(atOffsets: IndexSet(validOffsets))
    }

    private func refreshDSYMMatchState() {
        let crashUUIDs = crashLog?.uuidList ?? []
        dsymItems = dsymItems.map { item in
            let info = DSYMInfo(id: item.id, path: item.path, displayName: item.displayName, uuid: item.uuid)
            return DSYMItem(from: info, crashUUIDs: crashUUIDs)
        }
    }

    /// 批量导入 dSYM 后，若与崩溃日志的 Mach-O UUID 匹配，则自动填充到每个镜像的选择中（不覆盖手动选择）。
    private func autoAssignSelectedDSYMIfPossible(_ map: inout [String: URL]) {
        guard let crash = crashLog else { return }
        let wanted = Set(crash.uuidList)
        for item in dsymItems {
            guard item.matchesCrashUUIDs, let u = item.uuid?.uuidString else { continue }
            // uuidList 中可能为格式化 UUID（8-4-4-4-12），这里统一用 uuidString（同样格式）
            guard wanted.contains(u) else { continue }
            if map[u] == nil { map[u] = item.path }
        }
    }

    /// 若设置里配置了搜索目录，并已建立 UUID 索引，则自动填充尚未选择的镜像 dSYM。
    private func autoAssignFromDiscoveryIndexIfPossible(_ map: inout [String: URL]) {
        guard let crash = crashLog else { return }
        for uuid in crash.uuidList where map[uuid] == nil {
            if let resolved = DSYMAutoDiscoveryStore.shared.resolveDSYMURL(forUUID: uuid) {
                map[uuid] = resolved.url
            }
        }
    }

    /// 重新计算“有效选择”（manual 覆盖 > 导入 dSYM 匹配 > 自动发现索引）。
    @MainActor
    func recomputeResolvedDSYMSelection() {
        guard crashLog != nil else {
            selectedDSYMByImageUUID = [:]
            return
        }
        var map: [String: URL] = [:]
        // 1) 手动覆盖
        for (k, v) in manualDSYMOverrideByImageUUID { map[k] = v }
        // 2) 用户导入的 dSYM（匹配 UUID）
        autoAssignSelectedDSYMIfPossible(&map)
        // 3) 自动发现索引
        autoAssignFromDiscoveryIndexIfPossible(&map)
        selectedDSYMByImageUUID = map
    }

    @MainActor
    func pickDSYM(forImageUUID uuid: String) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.treatsFilePackagesAsDirectories = true
        panel.title = L10n.tFormat("Select dSYM for %@", uuid)
        if panel.runModal() == .OK, let url = panel.url {
            addDSYM(url: url)
            manualDSYMOverrideByImageUUID[uuid] = url
            recomputeResolvedDSYMSelection()
        }
    }

    @MainActor
    func clearSelectedDSYM(forImageUUID uuid: String) {
        manualDSYMOverrideByImageUUID.removeValue(forKey: uuid)
        recomputeResolvedDSYMSelection()
    }

    @MainActor
    func assignSelectedDSYM(forImageUUID uuid: String, url: URL) {
        // 视为手动覆盖（来自行内“分配…”也属于用户明确操作）
        manualDSYMOverrideByImageUUID[uuid] = url
        recomputeResolvedDSYMSelection()
    }

    /// 将“自动发现到的候选”填充为自动匹配结果（不会变成手动覆盖）。
    @MainActor
    func assignAutoDiscoveredDSYM(forImageUUID uuid: String, url: URL) {
        guard manualDSYMOverrideByImageUUID[uuid] == nil else { return }
        var map = selectedDSYMByImageUUID
        map[uuid] = url
        selectedDSYMByImageUUID = map
    }

    @MainActor
    func startSymbolication() {
        guard let crash = crashLog, !selectedDSYMByImageUUID.isEmpty else { return }
        symbolicationTask?.cancel()
        symbolicationError = nil
        symbolicationErrorKind = nil
        isSymbolicating = true
        let paths = Array(Set(selectedDSYMByImageUUID.values))
        symbolicationTask = Task {
            // 符号化期间为已选择的 dSYM 开启安全作用域：
            // - 若 URL 本身是 security-scoped（用户手动选择）则直接 startAccessing(url)
            // - 若 URL 是由 bookmark root 拼出的子路径（自动发现）则对 root startAccessing
            let stops: [() -> Void] = paths.compactMap { DSYMAutoDiscoveryStore.shared.startAccessingIfNeeded(for: $0) }
            defer { stops.forEach { $0() } }

            let result = await symbolicationService.symbolicate(crashLog: crash, dsymPaths: paths)
            await MainActor.run {
                isSymbolicating = false
                switch result {
                case .success(let output):
                    symbolicationError = nil
                    symbolicatedText = output.text
                    symbolicatedModel = output.model
                    if !output.text.isEmpty {
                        ProjectHistoryStore.shared.add(
                            crashPath: crash.fileURL.path,
                            dsymPaths: paths.map { $0.path }
                        )
                    }
                case .failure(let err):
                    symbolicationError = err.localizedDescription
                    if let se = err as? SymbolicationError {
                        symbolicationErrorKind = se.kind
                    } else {
                        symbolicationErrorKind = nil
                    }
                }
            }
        }
    }

    @MainActor
    func exportSymbolicatedResult() {
        guard !symbolicatedText.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "symbolicated.crash"
        if panel.runModal() == .OK, let url = panel.url {
            let content = ReportDisplayStyle.translatedReportOnly(symbolicatedText)
            try? content.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
