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
    @Published var showManualSymbolicateSheet: Bool = false
    @Published var aiAnalysisText: String = ""
    @Published var aiAnalysisError: String?
    @Published var isAnalyzingCrashWithAI: Bool = false

    private let symbolicationService = SymbolicationService()
    private var symbolicationTask: Task<Void, Never>?
    private var openCrashLogTask: Task<Void, Never>?
    private var aiAnalysisTask: Task<Void, Never>?
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
        aiAnalysisTask?.cancel()
        aiAnalysisText = ""
        aiAnalysisError = nil
        isAnalyzingCrashWithAI = false
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
                self.aiAnalysisTask?.cancel()
                self.aiAnalysisText = ""
                self.aiAnalysisError = nil
                self.isAnalyzingCrashWithAI = false
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

    @MainActor
    func requestAIAnalysis() {
        guard !RegionPolicy.isChinaMainland else {
            aiAnalysisError = L10n.t("AI features are not available in your region.")
            return
        }
        guard let crash = crashLog else {
            aiAnalysisError = L10n.t("Please open a crash file first")
            return
        }

        let settings = SettingsStore.shared
        let model = settings.llmModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseURL = settings.llmBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty, !baseURL.isEmpty else {
            aiAnalysisError = L10n.t("Please configure LLM provider in Settings first.")
            return
        }
        guard let endpoint = chatCompletionsEndpointURL(from: baseURL) else {
            aiAnalysisError = L10n.t("Invalid URL.")
            return
        }

        aiAnalysisTask?.cancel()
        isAnalyzingCrashWithAI = true
        aiAnalysisError = nil

        let input = symbolicatedText.isEmpty ? crash.rawText : symbolicatedText
        let prompt = buildAIPrompt(crash: crash, reportText: input)
        let headerName = settings.llmResolvedAPIKeyHeaderName()
        let key = (settings.llmAPIKey() ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        aiAnalysisTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                let firstTry = try await self.performChatCompletionRequest(
                    endpoint: endpoint,
                    model: model,
                    prompt: prompt,
                    apiKey: key,
                    headerName: headerName
                )

                var finalData = firstTry.data
                var finalHTTP = firstTry.http
                if finalHTTP.statusCode == 401, !key.isEmpty, headerName.caseInsensitiveCompare("Authorization") != .orderedSame {
                    let retry = try await self.performChatCompletionRequest(
                        endpoint: endpoint,
                        model: model,
                        prompt: prompt,
                        apiKey: key,
                        headerName: "Authorization"
                    )
                    finalData = retry.data
                    finalHTTP = retry.http
                }

                guard (200 ... 299).contains(finalHTTP.statusCode) else {
                    let body = String(data: finalData, encoding: .utf8) ?? ""
                    let msg = body.isEmpty ? L10n.tFormat("Request failed (%d).", finalHTTP.statusCode) : body
                    await MainActor.run {
                        self.isAnalyzingCrashWithAI = false
                        self.aiAnalysisError = msg
                    }
                    return
                }

                let decoded = try JSONDecoder().decode(OpenAIChatCompletionResponse.self, from: finalData)
                let finalText = decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                await MainActor.run {
                    self.isAnalyzingCrashWithAI = false
                    if finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self.aiAnalysisError = L10n.t("No analysis returned.")
                    } else if !self.matchesAIReportTemplate(finalText) {
                        self.aiAnalysisError = L10n.t("AI response did not match required template. Please retry.")
                    } else {
                        self.aiAnalysisText = finalText
                    }
                }
            } catch {
                await MainActor.run {
                    self.isAnalyzingCrashWithAI = false
                    self.aiAnalysisError = error.localizedDescription
                }
            }
        }
    }

    private func buildAIPrompt(crash: CrashLog, reportText: String) -> String {
        let maxLen = 16000
        let clipped = reportText.count > maxLen ? String(reportText.prefix(maxLen)) : reportText
        let t = aiReportTemplate()
        return """
        \(t.roleLine)
        \(t.taskLine)

        \(t.formatTitle)
        \(t.formatRuleLine)

        \(t.headings[0])
        ...

        \(t.headings[1])
        ...

        \(t.headings[2])
        ...

        \(t.headings[3])
        1.
        2.
        3.

        \(t.headings[4])
        ...

        \(t.headings[5])
        ...

        \(t.headings[6])
        ...

        \(t.constraintsTitle)
        - \(t.languageRule)
        - \(t.outputOnlyRule)
        - \(t.insufficientRule)
        - \(t.topReasonRule)

        \(t.fileLabel): \(crash.fileName)
        \(t.processLabel): \(crash.processName ?? "-")

        \(t.reportLabel):
        \(clipped)
        """
    }

    private func matchesAIReportTemplate(_ text: String) -> Bool {
        let requiredBlocks = aiReportTemplate().headings
        guard requiredBlocks.allSatisfy({ text.contains($0) }) else { return false }
        guard text.contains("1."), text.contains("2."), text.contains("3.") else { return false }
        return true
    }

    private func aiReportTemplate() -> (
        roleLine: String,
        taskLine: String,
        formatTitle: String,
        formatRuleLine: String,
        headings: [String],
        constraintsTitle: String,
        languageRule: String,
        outputOnlyRule: String,
        insufficientRule: String,
        topReasonRule: String,
        fileLabel: String,
        processLabel: String,
        reportLabel: String
    ) {
        let lang = Bundle.main.preferredLocalizations.first ?? "en"
        if lang.hasPrefix("zh-Hans") || lang == "zh-Hans" || lang == "zh" {
            return (
                roleLine: "你是资深 iOS 崩溃分析工程师。",
                taskLine: "请基于崩溃报告输出诊断结论。",
                formatTitle: "【输出格式要求（必须遵守）】",
                formatRuleLine: "请严格按照以下结构输出，不得增删标题，不得改写标题名：",
                headings: ["【崩溃类型】", "【崩溃位置】", "【关键信息】", "【最可能原因（按概率排序）】", "【影响范围】", "【修复建议】", "【一句话总结】"],
                constraintsTitle: "【额外约束】",
                languageRule: "只用简体中文。",
                outputOnlyRule: "仅输出以上模板内容，不要输出任何额外说明、前后缀、Markdown 代码块。",
                insufficientRule: "如果信息不足，在对应项写“信息不足”。",
                topReasonRule: "“最可能原因”必须保留 1/2/3 三条。",
                fileLabel: "文件名",
                processLabel: "进程",
                reportLabel: "报告内容"
            )
        }
        if lang.hasPrefix("zh-Hant") {
            return (
                roleLine: "你是資深 iOS 崩潰分析工程師。",
                taskLine: "請基於崩潰報告輸出診斷結論。",
                formatTitle: "【輸出格式要求（必須遵守）】",
                formatRuleLine: "請嚴格按照以下結構輸出，不得增刪標題，不得改寫標題名：",
                headings: ["【崩潰類型】", "【崩潰位置】", "【關鍵資訊】", "【最可能原因（按概率排序）】", "【影響範圍】", "【修復建議】", "【一句話總結】"],
                constraintsTitle: "【額外約束】",
                languageRule: "只用繁體中文。",
                outputOnlyRule: "僅輸出以上模板內容，不要輸出任何額外說明、前後綴、Markdown 代碼塊。",
                insufficientRule: "如果資訊不足，在對應項寫「資訊不足」。",
                topReasonRule: "「最可能原因」必須保留 1/2/3 三條。",
                fileLabel: "檔名",
                processLabel: "進程",
                reportLabel: "報告內容"
            )
        }
        if lang.hasPrefix("ja") {
            return (
                roleLine: "あなたはシニア iOS クラッシュ解析エンジニアです。",
                taskLine: "クラッシュレポートに基づいて診断結果を出力してください。",
                formatTitle: "[Output Format Requirements (Must Follow)]",
                formatRuleLine: "Use exactly this structure and keep all headings unchanged:",
                headings: ["[Crash Type]", "[Crash Location]", "[Key Information]", "[Most Likely Causes (Ranked)]", "[Impact Scope]", "[Fix Suggestions]", "[One-line Summary]"],
                constraintsTitle: "[Additional Constraints]",
                languageRule: "Respond in Japanese only.",
                outputOnlyRule: "Output only the template content above. No extra notes/prefix/suffix/markdown code blocks.",
                insufficientRule: "If information is insufficient, write \"Insufficient information\" in that section.",
                topReasonRule: "\"Most Likely Causes\" must keep items 1/2/3.",
                fileLabel: "File",
                processLabel: "Process",
                reportLabel: "Report Content"
            )
        }
        if lang.hasPrefix("ko") {
            return (
                roleLine: "당신은 시니어 iOS 크래시 분석 엔지니어입니다.",
                taskLine: "크래시 리포트를 기반으로 진단 결과를 출력하세요.",
                formatTitle: "[Output Format Requirements (Must Follow)]",
                formatRuleLine: "Use exactly this structure and keep all headings unchanged:",
                headings: ["[Crash Type]", "[Crash Location]", "[Key Information]", "[Most Likely Causes (Ranked)]", "[Impact Scope]", "[Fix Suggestions]", "[One-line Summary]"],
                constraintsTitle: "[Additional Constraints]",
                languageRule: "Respond in Korean only.",
                outputOnlyRule: "Output only the template content above. No extra notes/prefix/suffix/markdown code blocks.",
                insufficientRule: "If information is insufficient, write \"Insufficient information\" in that section.",
                topReasonRule: "\"Most Likely Causes\" must keep items 1/2/3.",
                fileLabel: "File",
                processLabel: "Process",
                reportLabel: "Report Content"
            )
        }
        if lang.hasPrefix("th") {
            return (
                roleLine: "You are a senior iOS crash analysis engineer.",
                taskLine: "Generate a diagnosis based on the crash report.",
                formatTitle: "[Output Format Requirements (Must Follow)]",
                formatRuleLine: "Use exactly this structure and keep all headings unchanged:",
                headings: ["[Crash Type]", "[Crash Location]", "[Key Information]", "[Most Likely Causes (Ranked)]", "[Impact Scope]", "[Fix Suggestions]", "[One-line Summary]"],
                constraintsTitle: "[Additional Constraints]",
                languageRule: "Respond in Thai only.",
                outputOnlyRule: "Output only the template content above. No extra notes/prefix/suffix/markdown code blocks.",
                insufficientRule: "If information is insufficient, write \"Insufficient information\" in that section.",
                topReasonRule: "\"Most Likely Causes\" must keep items 1/2/3.",
                fileLabel: "File",
                processLabel: "Process",
                reportLabel: "Report Content"
            )
        }
        if lang.hasPrefix("vi") {
            return (
                roleLine: "You are a senior iOS crash analysis engineer.",
                taskLine: "Generate a diagnosis based on the crash report.",
                formatTitle: "[Output Format Requirements (Must Follow)]",
                formatRuleLine: "Use exactly this structure and keep all headings unchanged:",
                headings: ["[Crash Type]", "[Crash Location]", "[Key Information]", "[Most Likely Causes (Ranked)]", "[Impact Scope]", "[Fix Suggestions]", "[One-line Summary]"],
                constraintsTitle: "[Additional Constraints]",
                languageRule: "Respond in Vietnamese only.",
                outputOnlyRule: "Output only the template content above. No extra notes/prefix/suffix/markdown code blocks.",
                insufficientRule: "If information is insufficient, write \"Insufficient information\" in that section.",
                topReasonRule: "\"Most Likely Causes\" must keep items 1/2/3.",
                fileLabel: "File",
                processLabel: "Process",
                reportLabel: "Report Content"
            )
        }
        if lang.hasPrefix("id") {
            return (
                roleLine: "You are a senior iOS crash analysis engineer.",
                taskLine: "Generate a diagnosis based on the crash report.",
                formatTitle: "[Output Format Requirements (Must Follow)]",
                formatRuleLine: "Use exactly this structure and keep all headings unchanged:",
                headings: ["[Crash Type]", "[Crash Location]", "[Key Information]", "[Most Likely Causes (Ranked)]", "[Impact Scope]", "[Fix Suggestions]", "[One-line Summary]"],
                constraintsTitle: "[Additional Constraints]",
                languageRule: "Respond in Indonesian only.",
                outputOnlyRule: "Output only the template content above. No extra notes/prefix/suffix/markdown code blocks.",
                insufficientRule: "If information is insufficient, write \"Insufficient information\" in that section.",
                topReasonRule: "\"Most Likely Causes\" must keep items 1/2/3.",
                fileLabel: "File",
                processLabel: "Process",
                reportLabel: "Report Content"
            )
        }
        return (
            roleLine: "You are a senior iOS crash analysis engineer.",
            taskLine: "Generate a diagnosis based on the crash report.",
            formatTitle: "[Output Format Requirements (Must Follow)]",
            formatRuleLine: "Use exactly this structure and keep all headings unchanged:",
            headings: ["[Crash Type]", "[Crash Location]", "[Key Information]", "[Most Likely Causes (Ranked)]", "[Impact Scope]", "[Fix Suggestions]", "[One-line Summary]"],
            constraintsTitle: "[Additional Constraints]",
            languageRule: "Respond in the app language.",
            outputOnlyRule: "Output only the template content above. No extra notes/prefix/suffix/markdown code blocks.",
            insufficientRule: "If information is insufficient, write \"Insufficient information\" in that section.",
            topReasonRule: "\"Most Likely Causes\" must keep items 1/2/3.",
            fileLabel: "File",
            processLabel: "Process",
            reportLabel: "Report Content"
        )
    }

    private func chatCompletionsEndpointURL(from baseURLString: String) -> URL? {
        guard var comps = URLComponents(string: baseURLString) else { return nil }
        let path = comps.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.isEmpty {
            comps.path = "/chat/completions"
        } else if path.hasSuffix("chat/completions") {
            comps.path = "/" + path
        } else {
            comps.path = "/" + path + "/chat/completions"
        }
        comps.query = nil
        comps.fragment = nil
        return comps.url
    }

    private func performChatCompletionRequest(
        endpoint: URL,
        model: String,
        prompt: String,
        apiKey: String,
        headerName: String
    ) async throws -> (data: Data, http: HTTPURLResponse) {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            if headerName.caseInsensitiveCompare("Authorization") == .orderedSame {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: headerName)
            } else {
                request.setValue(apiKey, forHTTPHeaderField: headerName)
            }
        }
        let payload = OpenAIChatCompletionRequest(
            model: model,
            messages: [
                .init(role: "system", content: "You are a senior iOS crash triage assistant."),
                .init(role: "user", content: prompt)
            ],
            temperature: 0.1
        )
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }
}

private struct OpenAIChatCompletionRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }
    let model: String
    let messages: [Message]
    let temperature: Double
}

private struct OpenAIChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String
        }
        let message: Message
    }
    let choices: [Choice]
}
