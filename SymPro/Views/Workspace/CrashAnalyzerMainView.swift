import SwiftUI
import UserNotifications

struct CrashAnalyzerMainView: View {
    @EnvironmentObject private var state: SymbolicateWorkspaceState

    @State private var tab: AnalyzerTab = .backtrace
    @State private var showSymbolicationErrorAlert: Bool = false
    @State private var tabSelectedThreadIndex: Int = 0
    @State private var hasRequestedAINotificationPermission: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            HSplitView {
                leftSidebar
                    .frame(minWidth: 220, idealWidth: 260, maxWidth: 420)

                centerContent
                    .frame(minWidth: 560, idealWidth: 720, maxWidth: .infinity)

                rightSidebar
                    .frame(minWidth: 280, idealWidth: 320, maxWidth: 520)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .foregroundStyle(Color.primary)
        .onChange(of: state.symbolicationError) { newValue in
            showSymbolicationErrorAlert = (newValue?.isEmpty == false)
        }
        .alert("Symbolication Failed", isPresented: $showSymbolicationErrorAlert) {
            Button("OK") {}
        } message: {
            Text(state.symbolicationError ?? "")
        }
        .onAppear {
            tabSelectedThreadIndex = preferredThreadIndex(model: state.symbolicatedModel ?? state.crashLog?.model)
        }
        .onChange(of: state.crashLog?.id) { _ in
            tabSelectedThreadIndex = preferredThreadIndex(model: state.symbolicatedModel ?? state.crashLog?.model)
        }
        .onChange(of: state.aiAnalysisText) { newValue in
            let content = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { return }
            guard tab != .aiInsight else { return }
            notifyAIAnalysisReady()
        }
        .onReceive(NotificationCenter.default.publisher(for: .symProOpenAIInsight)) { _ in
            tab = .aiInsight
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            // Image(systemName: "bolt.circle.fill")
            //     .foregroundStyle(Color.primary.opacity(0.85))
            // Text("Crash Analyzer Pro")
            //     .font(.system(size: 13, weight: .semibold))
            if let crash = state.crashLog {
                Text(crash.fileName)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text("v2.0")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondary)
            }

            Button(L10n.t("Manual Symbolicate…")) {
                state.showManualSymbolicateSheet = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            
            Spacer()

            uuidMatchPill
            symbolicationStatusPill
            
            
            Button {
                state.startSymbolication()
            } label: {
                if state.isSymbolicating {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text(L10n.t("Symbolication in progress"))
                    }
                } else {
                    if state.symbolicationErrorKind == .noSymbolsFound {
                        Text(L10n.t("No symbols found"))
                    } else {
                        Text(L10n.t("Symbolicate"))
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(!canSymbolicate)
            .help(symbolizeHelpText)

            Button(L10n.t("Raw text")) {
                showRawTextReport()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(state.crashLog == nil)

            Button(L10n.t("Export Report")) {
                state.exportSymbolicatedResult()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var uuidMatchPill: some View {
        let ok = uuidMatchSummary.ok
        let total = uuidMatchSummary.total
        let text: String = {
            if total == 0 { return L10n.t("UUID Matching: -") }
            if ok == total { return L10n.t("UUID Matching: Match") }
            return L10n.tFormat("UUID Matching: %d/%d", ok, total)
        }()
        let bg = ok == total && total > 0 ? Color.green.opacity(0.18) : Color.white.opacity(0.08)
        let fg = ok == total && total > 0 ? Color.green : Color.secondary

        return Text(text)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(bg)
            .foregroundStyle(fg)
            .clipShape(Capsule())
    }

    private var uuidMatchSummary: (ok: Int, total: Int) {
        guard let crash = state.crashLog else { return (0, 0) }
        let uuids = crash.uuidList
        if uuids.isEmpty { return (0, 0) }
        let ok = uuids.filter { state.selectedDSYMByImageUUID[$0] != nil }.count
        return (ok, uuids.count)
    }

    private var symbolicationStatusPill: some View {
        let text: String
        let bg: Color
        let fg: Color

        if state.isSymbolicating {
            text = L10n.t("Symbolication: Running")
            bg = Color.blue.opacity(0.18)
            fg = Color.blue
        } else if state.symbolicationError?.isEmpty == false {
            text = L10n.t("Symbolication: Failed")
            bg = Color.red.opacity(0.18)
            fg = Color.red
        } else if state.symbolicatedModel != nil, !(state.symbolicatedText.isEmpty) {
            text = L10n.t("Symbolication: Done")
            bg = Color.green.opacity(0.18)
            fg = Color.green
        } else {
            text = L10n.t("Symbolication: -")
            bg = Color.white.opacity(0.08)
            fg = Color.secondary
        }

        return Text(text)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(bg)
            .foregroundStyle(fg)
            .clipShape(Capsule())
    }

    private var canSymbolicate: Bool {
        guard state.crashLog != nil else { return false }
        guard !state.isSymbolicating else { return false }
        let total = uuidMatchSummary.total
        let ok = uuidMatchSummary.ok
        return total > 0 && ok > 0
    }

    private func showRawTextReport() {
        guard let crash = state.crashLog else { return }
        state.symbolicatedModel = nil
        state.symbolicationError = nil
        state.symbolicationErrorKind = nil
        state.symbolicatedText = ReportDisplayStyle.translatedReportOnly(crash.rawText)
    }

    private var symbolizeHelpText: String {
        guard state.crashLog != nil else { return L10n.t("Please open a crash file first") }
        if state.isSymbolicating { return L10n.t("Symbolication in progress") }
        if state.symbolicationErrorKind == .noSymbolsFound { return L10n.t("No symbols found") }
        let total = uuidMatchSummary.total
        let ok = uuidMatchSummary.ok
        if total == 0 { return L10n.t("The current crash file contains no matching UUID information") }
        if ok == 0 { return L10n.t("No usable dSYM matched (import on the right or configure auto-discovery directories)") }
        return L10n.t("Resolve stack symbols using the matched dSYMs")
    }

    private var leftSidebar: some View {
        CrashAnalyzerLeftSidebarView(
            model: state.symbolicatedModel ?? state.crashLog?.model,
            selectedThreadIndex: $tabSelectedThreadIndex
        )
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var centerContent: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            Group {
                switch tab {
                case .backtrace:
                    CrashAnalyzerBacktraceView(
                        model: state.symbolicatedModel ?? state.crashLog?.model,
                        selectedThreadIndex: $tabSelectedThreadIndex
                    )
                case .registers:
                    PlaceholderPanel(title: "Registers", subtitle: "ThreadState registers display (to be integrated)")
                case .binaryImages:
                    ImagesView(state: state)
                case .aiInsight:
                    aiInsightPanel
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
        }
    }

    private var tabBar: some View {
        HStack(spacing: 18) {
            underlineTabItem(title: L10n.t("Backtrace"), tab: .backtrace)
            underlineTabItem(title: L10n.t("AI Insight"), tab: .aiInsight)
//            underlineTabItem(title: "Registers", tab: .registers)
//            underlineTabItem(title: "Binary Images", tab: .binaryImages)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 13)
        .padding(.top, 15)
        .background(Color(nsColor: .controlBackgroundColor))
        .frame(alignment: .center)
    }

    @ViewBuilder
    private func underlineTabItem(title: String, tab item: AnalyzerTab) -> some View {
        UnderlineTabItem(
            title: title,
            isSelected: tab == item,
            onTap: {
                withAnimation(.easeInOut(duration: 0.1)) {
                    tab = item
                }
            }
        )
    }

    private var rightSidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            CrashAnalyzerDSYMPanel()
//            CrashAnalyzerInsightPanel()
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func preferredThreadIndex(model: CrashReportModel?) -> Int {
        guard let model else { return 0 }
        if let crashed = model.threads.first(where: { $0.triggered })?.index { return crashed }
        return model.threads.first(where: { !$0.frames.isEmpty })?.index ?? 0
    }

    private var aiInsightPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.t("AI Insight"))
                    .font(.headline)
                Spacer()
                Button(state.isAnalyzingCrashWithAI ? L10n.t("Analyzing…") : L10n.t("AI Analyze")) {
                    state.requestAIAnalysis()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(state.crashLog == nil || state.isAnalyzingCrashWithAI)
            }

            if let err = state.aiAnalysisError, !err.isEmpty {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if state.isAnalyzingCrashWithAI {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(L10n.t("Analyzing…"))
                            .font(.subheadline.weight(.medium))
                    }
                    .padding(.bottom, 2)

                    Text(L10n.t("• 正在读取崩溃上下文并提炼问题点"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(L10n.t("• 正在生成精简结论与修复建议"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(L10n.t("• 完成后将自动展示结果"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                // .background(
                //     RoundedRectangle(cornerRadius: 10, style: .continuous)
                //         .fill(Color(nsColor: .textBackgroundColor))
                // )
                // .overlay(
                //     RoundedRectangle(cornerRadius: 10, style: .continuous)
                //         .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                // )
            } else if state.aiAnalysisText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.t("AI analysis not generated yet."))
                        .foregroundStyle(.secondary)
                    Text(L10n.t("点击右上角 “AI Analyze” 开始分析。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(formattedAIInsightText)
                            .font(.system(size: 13))
                            .foregroundStyle(.primary)
                            .lineSpacing(4)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                    )
                    .frame(maxWidth: 960, alignment: .topLeading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
    }

    private var formattedAIInsightText: String {
        var s = state.aiAnalysisText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return s }

        // Keep "single-paragraph style" but add readable wraps around key transitions.
        s = s.replacingOccurrences(of: "；", with: "；\n")
        s = s.replacingOccurrences(of: ";", with: ";\n")
        s = s.replacingOccurrences(of: "建议排查", with: "\n建议排查")
        s = s.replacingOccurrences(of: "排查方向", with: "\n排查方向")

        while s.contains("\n\n\n") {
            s = s.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        return s
    }

    private func notifyAIAnalysisReady() {
        let center = UNUserNotificationCenter.current()
        if !hasRequestedAINotificationPermission {
            hasRequestedAINotificationPermission = true
            center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                guard granted else { return }
                postAIReadyNotification(center: center)
            }
            return
        }
        postAIReadyNotification(center: center)
    }

    private func postAIReadyNotification(center: UNUserNotificationCenter) {
        let content = UNMutableNotificationContent()
        content.title = "AI 分析已完成"
        content.body = "崩溃报告解读结果已生成，可切换到 AI 解读页查看。"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "sympro.ai.analysis.ready",
            content: content,
            trigger: nil
        )
        center.removePendingNotificationRequests(withIdentifiers: ["sympro.ai.analysis.ready"])
        center.add(request)
    }
}

private enum AnalyzerTab: Hashable {
    case backtrace
    case registers
    case binaryImages
    case aiInsight
}

private struct PlaceholderPanel: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.6))
            Spacer()
        }
        .padding(16)
    }
}

private struct UnderlineTabItem: View {
    private struct TextWidthKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }

    let title: String
    let isSelected: Bool
    let onTap: () -> Void

    @State private var textWidth: CGFloat = 0

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .background(
                        GeometryReader { proxy in
                            Color.clear
                                .preference(key: TextWidthKey.self, value: proxy.size.width)
                        }
                    )

                Capsule()
                    .fill(isSelected ? Color.accentColor : Color.clear)
                    .frame(width: max(6, textWidth), height: 2, alignment: .leading)
            }
            .padding(.vertical, 0)
            .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.plain)
        .onPreferenceChange(TextWidthKey.self) { w in
            if abs(w - textWidth) > 0.5 {
                textWidth = w
            }
        }
    }
}

