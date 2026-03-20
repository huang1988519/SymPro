//
//  IPSPrettyTemplateFormatter.swift
//  SymPro
//

import Foundation

enum IPSPrettyTemplateFormatter {
    static func prettyText(crash: CrashLog, selectedDSYMByImageUUID: [String: URL]) -> String? {
        guard let model = crash.model else { return nil }

        let appName = model.overview.process
        let bundleID = model.overview.identifier
        let version = model.overview.version
        let device = deviceText(model: model)

        let crashTime = model.overview.dateTime
        let launchTime = model.overview.launchTime
        let deltaText = launchDeltaText(crash: crashTime, launch: launchTime)

        let exceptionType = model.overview.exceptionType
        let exceptionCodes = model.overview.exceptionCodes
        let termination = terminationText(signalName: model.overview.exceptionSignal, exceptionType: exceptionType)

        let crashedThread = model.overview.triggeredThread
        let isMain = crashedThread == 0

        let typeJudgement = judgementText(model: model)
        let analysis = smartAnalysis(model: model)

        let appUUID = appImageUUID(model: model)
        let binaryText = appBinaryText(model: model)
        let dsymMatched = appUUID.map { selectedDSYMByImageUUID[$0] != nil } ?? false

        let stackText = crashedThreadStackText(model: model, appName: appName)
        let threadsFolded = otherThreadsFoldedText(model: model, crashedThread: crashedThread)
        let imagesFolded = imagesFoldedText(model: model)

        var out: [String] = []
        out += [
            "──────────────────────────────────────",
            "🔥 Crash Report",
            "──────────────────────────────────────",
            "",
            "【App】",
            "\(appName) (\(bundleID))",
            "Version: \(version)",
            "",
            "【Device】",
            device.isEmpty ? "Unknown" : device,
            "",
            "【Time】",
            "Crash: \(crashTime)",
            "Launch: \(launchTime)\(deltaText)",
            "",
            "──────────────────────────────────────",
            "💥 崩溃摘要",
            "──────────────────────────────────────",
            "",
            "Exception Type:    \(exceptionType)",
            "Exception Codes:   \(exceptionCodes)",
            "Termination:       \(termination)",
            "",
            "Crashed Thread:    \(crashedThread)\(isMain ? "  (Main Thread)" : "")",
            "",
            "👉 类型判断：",
            "\(typeJudgement)",
            "",
            "──────────────────────────────────────",
            "🧠 智能分析（Root Cause）",
            "──────────────────────────────────────",
            "",
            analysis,
            "",
            "──────────────────────────────────────",
            "🔥 崩溃调用栈（已符号化）",
            "──────────────────────────────────────",
            "",
            stackText,
            "",
            "──────────────────────────────────────",
            "📦 关键定位信息",
            "──────────────────────────────────────",
            "",
            "Crash Address:",
            crashAddress(from: exceptionCodes) ?? "Unknown",
            "",
            "UUID:",
            appUUID ?? "Unknown",
            "",
            "Binary:",
            binaryText ?? "Unknown",
            "",
            "dSYM:",
            dsymMatched ? "✅ 已匹配" : "❌ 未匹配",
            "",
            "──────────────────────────────────────",
            "🧵 线程信息（已折叠）",
            "──────────────────────────────────────",
            "",
            threadsFolded,
            "",
            "──────────────────────────────────────",
            "🧩 Binary Images（已折叠）",
            "──────────────────────────────────────",
            "",
            imagesFolded,
            "",
            "──────────────────────────────────────",
        ]

        return out.joined(separator: "\n")
    }

    // MARK: - Heuristics

    private static func judgementText(model: CrashReportModel) -> String {
        let t = model.overview.exceptionType.uppercased()
        if t.contains("EXC_BREAKPOINT") || t.contains("SIGTRAP") {
            return "主动触发崩溃（fatalError / assert / Swift runtime）"
        }
        if t.contains("EXC_BAD_ACCESS") || t.contains("SIGSEGV") {
            return "内存访问异常（野指针 / 访问已释放对象 / 越界）"
        }
        return "需要结合堆栈进一步判断"
    }

    private static func smartAnalysis(model: CrashReportModel) -> String {
        let (conclusion, reason, issues, suggestions, confidence) = analyze(model: model)
        var lines: [String] = []
        lines += ["【结论】", conclusion, "", "【原因】", reason, ""]
        lines += ["【高概率问题】"]
        lines += issues.map { "- \($0)" }
        lines += ["", "【建议】"]
        lines += suggestions.map { "✔ \($0)" }
        lines += ["", "【置信度】", "\(confidence)%"]
        return lines.joined(separator: "\n")
    }

    private static func analyze(model: CrashReportModel) -> (String, String, [String], [String], Int) {
        let crashed = model.threads.first(where: { $0.triggered }) ?? model.threads.first(where: { $0.index == model.overview.triggeredThread })
        let symbols = (crashed?.frames ?? []).compactMap { $0.symbol }.joined(separator: "\n").lowercased()

        if symbols.contains("nsibuserdefinedruntimeattributesconnector") || symbols.contains("establishconnection") || symbols.contains("nib") || symbols.contains("storyboard") {
            return (
                "Storyboard / XIB 配置错误（KVC / Runtime Attribute）",
                "系统在 viewDidLoad / nib 加载阶段建立 Interface Builder 连接时失败",
                [
                    "User Defined Runtime Attributes key 不存在",
                    "IBOutlet 未连接",
                    "属性类型不匹配"
                ],
                [
                    "检查 storyboard / xib 的 Runtime Attributes",
                    "确认 IBOutlet 已连接",
                    "删除异常属性重新配置"
                ],
                95
            )
        }

        if symbols.contains("setvalue") && symbols.contains("forundefinedkey") {
            return (
                "KVC 设置了不存在的 key（forUndefinedKey）",
                "运行时通过 KVC 反射赋值时找不到对应属性",
                [
                    "Runtime Attributes key 写错",
                    "IBOutlet/IBAction 连接指向了已删除的属性"
                ],
                [
                    "检查 Runtime Attributes / IBOutlet 连接",
                    "清理无效连接后重新编译运行"
                ],
                90
            )
        }

        let t = model.overview.exceptionType.uppercased()
        if t.contains("EXC_BREAKPOINT") || t.contains("SIGTRAP") {
            return (
                "主动触发崩溃（断言/Swift runtime）",
                "常见于 fatalError/assert/preconditionFailure 或 Swift runtime trap",
                [
                    "业务断言失败",
                    "不可达分支触发 fatalError",
                    "Swift runtime 检测到不一致状态"
                ],
                [
                    "优先查看 Thread 0 顶部 1-3 帧的业务函数",
                    "结合日志/输入数据复现断言条件"
                ],
                75
            )
        }

        return (
            "需要进一步分析",
            "当前特征不足以给出高置信结论，建议结合顶部堆栈与关键地址进一步定位",
            [
                "符号信息不足或崩溃点不在 UI 初始化路径",
                "线程/镜像信息需要与 dSYM 匹配后再分析"
            ],
            [
                "先完成 dSYM 匹配并点击开始符号化",
                "将 Thread 0 顶部堆栈贴出进一步判断"
            ],
            50
        )
    }

    // MARK: - Sections

    private static func crashedThreadStackText(model: CrashReportModel, appName: String) -> String {
        let thread = model.threads.first(where: { $0.index == model.overview.triggeredThread })
            ?? model.threads.first(where: { $0.triggered })
        guard let t = thread else { return "Thread \(model.overview.triggeredThread)" }

        var out: [String] = []
        out.append("Thread \(t.index) (Crashed" + (t.index == 0 ? " - Main Thread" : "") + ")")
        out.append("")

        let frames = Array(t.frames.prefix(20))
        let appFrames = frames.filter { $0.imageName == appName }
        let sysFrames = frames.filter { $0.imageName != appName }

        if !appFrames.isEmpty {
            out.append("▶ App (重点)")
            out += appFrames.prefix(8).map { stackLine($0) }
            out.append("")
        }
        if !sysFrames.isEmpty {
            out.append("▶ System")
            out += sysFrames.prefix(12).map { stackLine($0) }
        }

        return out.joined(separator: "\n")
    }

    private static func stackLine(_ f: CrashReportModel.Frame) -> String {
        let idx = "\(f.index)".padding(toLength: 2, withPad: " ", startingAt: 0)
        let image = f.imageName.padding(toLength: 6, withPad: " ", startingAt: 0)
        let sym: String = {
            if let s = f.symbol, !s.isEmpty {
                if let loc = f.symbolLocation { return "\(s) + \(loc)" }
                return s
            }
            return String(format: "0x%016llx", f.address)
        }()
        let symPadded = sym.padding(toLength: 38, withPad: " ", startingAt: 0)
        if let file = f.sourceFile, let line = f.sourceLine {
            let last = (file as NSString).lastPathComponent
            return "\(idx)  \(image)  \(symPadded) (\(last):\(line))"
        }
        return "\(idx)  \(image)  \(sym)"
    }

    private static func otherThreadsFoldedText(model: CrashReportModel, crashedThread: Int) -> String {
        let others = model.threads.map(\.index).filter { $0 != crashedThread }.sorted()
        if others.isEmpty { return "(无其它线程)" }
        let lines = others.prefix(8).map { "Thread \($0)" }
        return (lines + ["(点击展开)"]).joined(separator: "\n")
    }

    private static func imagesFoldedText(model: CrashReportModel) -> String {
        let imgs = model.images.prefix(8)
        var lines: [String] = []
        for img in imgs {
            let name = img.name.padding(toLength: 18, withPad: " ", startingAt: 0)
            if let base = img.base, let size = img.size {
                let end = size > 0 ? base + size : base
                lines.append("\(name)  \(hex(base)) - \(hex(end))")
            } else {
                lines.append("\(name)")
            }
        }
        if model.images.count > imgs.count { lines.append("...") }
        return lines.joined(separator: "\n")
    }

    // MARK: - Extractors

    private static func crashAddress(from exceptionCodes: String) -> String? {
        // 常见格式："0x0000000000000001, 0x0000000100319d5c"
        let parts = exceptionCodes
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return parts.last
    }

    private static func appImageUUID(model: CrashReportModel) -> String? {
        let app = model.images.first(where: { $0.name == model.overview.process })
        return app?.uuid
    }

    private static func appBinaryText(model: CrashReportModel) -> String? {
        let p = model.overview.path
        guard !p.isEmpty else { return nil }
        let comps = p.split(separator: "/").map(String.init)
        if let appIdx = comps.lastIndex(where: { $0.hasSuffix(".app") }) {
            if appIdx + 1 < comps.count {
                return "\(comps[appIdx])/\(comps[appIdx + 1])"
            }
            return comps[appIdx]
        }
        return comps.suffix(2).joined(separator: "/")
    }

    private static func terminationText(signalName: String?, exceptionType: String) -> String {
        let t = (signalName ?? exceptionType).uppercased()
        let n: Int? = {
            if t.contains("SIGTRAP") { return 5 }
            if t.contains("SIGSEGV") { return 11 }
            if t.contains("SIGABRT") { return 6 }
            if t.contains("SIGBUS") { return 10 }
            return nil
        }()
        return n.map { "SIGNAL \($0)" } ?? "Unknown"
    }

    private static func deviceText(model: CrashReportModel) -> String {
        let os = model.overview.osVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        let hw = model.overview.hardwareModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if os.isEmpty && hw.isEmpty { return "Unknown" }
        if !os.isEmpty && !hw.isEmpty {
            // 目标格式：macOS 26.3.1 (Mac16,11)
            if os.contains("(") { return "\(os) \(hw)" }
            return "\(os) (\(hw))"
        }
        return !os.isEmpty ? os : hw
    }

    // MARK: - Time

    private static func launchDeltaText(crash: String, launch: String) -> String {
        guard let c = parseIPSDate(crash), let l = parseIPSDate(launch) else { return "" }
        let s = Int(c.timeIntervalSince(l))
        guard s >= 0 else { return "" }
        return "  (启动后 \(s)s 崩溃)"
    }

    private static func parseIPSDate(_ s: String) -> Date? {
        // IPS 常见时间格式："2026-03-17 15:21:04.000 +0800" 或无毫秒
        let f1 = DateFormatter()
        f1.locale = Locale(identifier: "en_US_POSIX")
        f1.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS Z"
        if let d = f1.date(from: s) { return d }
        let f2 = DateFormatter()
        f2.locale = Locale(identifier: "en_US_POSIX")
        f2.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        if let d = f2.date(from: s) { return d }
        let f3 = DateFormatter()
        f3.locale = Locale(identifier: "en_US_POSIX")
        f3.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f3.date(from: s)
    }

    private static func hex(_ n: UInt64) -> String {
        String(format: "0x%016llx", n)
    }
}

