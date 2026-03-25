//
//  CrashLogParser.swift
//  SymPro
//

import Foundation

enum CrashLogParser {
    /// 解析崩溃日志：若为 .ips JSON 则转为苹果 Translated Report 格式；否则按文本解析。
    static func parse(url: URL, data: Data) -> CrashLog? {
        guard let content = String(data: data, encoding: .utf8) else { return nil }
        let fileName = url.lastPathComponent
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)

        // .ips：首行为 metadata JSON，其余为 report JSON（bug_type 309 = crash）
        if trimmed.hasPrefix("{"), let crash = parseIPS(content: trimmed) {
            return CrashLog(
                fileURL: url,
                fileName: fileName,
                sourceText: trimmed,
                rawText: crash.translatedReport,
                model: crash.model,
                processName: crash.processName,
                uuidList: crash.uuidList,
                binaryImages: crash.binaryImages
            )
        }

        // 非 .ips 时，尝试解包三方平台导出的 JSON（如火山）中的原始崩溃文本。
        let plainCrashText = normalizeCrashText(extractEmbeddedCrashText(from: data) ?? content)
        let uuidList = extractUUIDs(from: plainCrashText)
        let binaryImages = extractBinaryImages(from: plainCrashText)
        let processName = extractProcessName(from: plainCrashText)
        let legacyModel: CrashReportModel? = {
            // Text crash reports (.crash / translated .ips / third-party exports):
            // build a structured model from the translated report text so UI can show backtrace.
            let ext = url.pathExtension.lowercased()
            guard ext == "ips" || ext == "crash" else { return nil }
            return CrashReportModel.fromTranslatedReportText(plainCrashText, processNameFallback: processName)
        }()
        return CrashLog(
            fileURL: url,
            fileName: fileName,
            sourceText: content,
            rawText: plainCrashText,
            model: legacyModel,
            processName: processName,
            uuidList: uuidList,
            binaryImages: binaryImages
        )
    }

    /// 解析 IPS 内容，返回 Translated Report 文本、进程名及 UUID/BinaryImages（用于 dSYM 匹配与符号化）。
    private static func parseIPS(content: String) -> (translatedReport: String, processName: String?, uuidList: [String], binaryImages: [BinaryImage], model: CrashReportModel?)? {
        guard let (metadata, report) = extractIPSPayload(content: content),
              isCrashBugType309(metadata) else { return nil }
        guard let translated = IPSReportFormatter.translatedReport(metadata: metadata, report: report) else { return nil }
        let processName = report["procName"] as? String
        let model = CrashReportModel.fromIPS(metadata: metadata, report: report)
        var uuidList: [String] = []
        var binaryImages: [BinaryImage] = []
        if let usedImages = report["usedImages"] as? [[String: Any]] {
            for img in usedImages {
                guard let base = (img["base"] as? NSNumber)?.uint64Value else { continue }
                let uuid = img["uuid"] as? String
                let name = img["name"] as? String ?? "???"
                let arch = img["arch"] as? String ?? "arm64"
                if let u = uuid, !u.isEmpty, u != "00000000-0000-0000-0000-000000000000" {
                    let normalized = u.replacingOccurrences(of: "-", with: "").uppercased()
                    if normalized.count == 32 {
                        let formatted = formatUUID(normalized)
                        if !uuidList.contains(formatted) { uuidList.append(formatted) }
                    }
                }
                binaryImages.append(BinaryImage(loadAddress: base, architecture: arch, name: name, uuid: uuid))
            }
        }
        return (translatedReport: translated, processName: processName, uuidList: uuidList, binaryImages: binaryImages, model: model)
    }

    private static func isCrashBugType309(_ metadata: [String: Any]) -> Bool {
        // bug_type 在不同 iOS/导出版本里可能是 String ("309") 或数字 (309)。
        if let s = metadata["bug_type"] as? String { return s == "309" }
        if let n = metadata["bug_type"] as? NSNumber { return n.intValue == 309 }
        if let i = metadata["bug_type"] as? Int { return i == 309 }
        return false
    }

    /// 支持两种输入：
    /// 1) 纯 .ips（首行 metadata JSON + 其余 report JSON）
    /// 2) 混合文本（Translated Report + Full Report，其中含两段顶层 JSON）
    private static func extractIPSPayload(content: String) -> (metadata: [String: Any], report: [String: Any])? {
        // Fast path: 标准 .ips（第一行 metadata，剩余为 report）
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        if let first = lines.first,
           let metaData = String(first).data(using: .utf8),
           let metadata = try? JSONSerialization.jsonObject(with: metaData) as? [String: Any] {
            let rest = lines.dropFirst().joined(separator: "\n")
            if let reportData = rest.data(using: .utf8),
               let report = try? JSONSerialization.jsonObject(with: reportData) as? [String: Any] {
                return (metadata, report)
            }
        }

        // Fallback: 从全文提取顶层 JSON 对象，寻找 metadata + report 连续配对
        let candidates = extractTopLevelJSONObjectStrings(from: content)
        guard candidates.count >= 2 else { return nil }
        for i in 0..<(candidates.count - 1) {
            guard let metaData = candidates[i].data(using: .utf8),
                  let reportData = candidates[i + 1].data(using: .utf8),
                  let metadata = try? JSONSerialization.jsonObject(with: metaData) as? [String: Any],
                  let report = try? JSONSerialization.jsonObject(with: reportData) as? [String: Any]
            else { continue }

            let bugType = metadata["bug_type"] as? String
            let reportLooksLikeCrash = report["threads"] != nil || report["usedImages"] != nil || report["procName"] != nil
            if bugType == "309", reportLooksLikeCrash {
                return (metadata, report)
            }
        }
        return nil
    }

    /// 提取文本中的“顶层 JSON 对象”字符串，支持 pretty JSON，忽略字符串中的大括号。
    private static func extractTopLevelJSONObjectStrings(from content: String) -> [String] {
        let chars = Array(content)
        var results: [String] = []
        var depth = 0
        var startIndex: Int?
        var inString = false
        var escaped = false

        for i in chars.indices {
            let c = chars[i]

            if inString {
                if escaped {
                    escaped = false
                } else if c == "\\" {
                    escaped = true
                } else if c == "\"" {
                    inString = false
                }
                continue
            }

            if c == "\"" {
                inString = true
                continue
            }

            if c == "{" {
                if depth == 0 { startIndex = i }
                depth += 1
                continue
            }

            if c == "}" {
                guard depth > 0 else { continue }
                depth -= 1
                if depth == 0, let s = startIndex {
                    results.append(String(chars[s...i]))
                    startIndex = nil
                }
            }
        }

        return results
    }

    /// 从文本格式崩溃日志中解析 "Process:             AppName [pid]" 得到进程名。
    private static func extractProcessName(from text: String) -> String? {
        for line in text.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("Process:") {
                let after = t.dropFirst("Process:".count).trimmingCharacters(in: .whitespaces)
                guard let bracket = after.firstIndex(of: "[") else { continue }
                let name = String(after[..<bracket]).trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { return name }
                continue
            }
            // 部分三方平台会把 Process 写成 "@Process:"
            if t.hasPrefix("@Process:") {
                let after = t.dropFirst("@Process:".count).trimmingCharacters(in: .whitespaces)
                guard let bracket = after.firstIndex(of: "[") else { continue }
                let name = String(after[..<bracket]).trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { return name }
            }
        }
        return nil
    }

    private static func extractUUIDs(from text: String) -> [String] {
        var uuids: [String] = []
        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            // Binary Images line: 0x123... 0x456... UUID  com.example.App
            let upper = line.uppercased()
            guard upper.contains("UUID") else { continue }
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            for (i, part) in parts.enumerated() {
                let s = String(part)
                if s.uppercased() == "UUID" && i + 1 < parts.count {
                    let uuidPart = String(parts[i + 1]).replacingOccurrences(of: "-", with: "").uppercased()
                    if uuidPart.count == 32, uuidPart.allSatisfy({ $0.isHexDigit }) {
                        let formatted = formatUUID(uuidPart)
                        if !uuids.contains(formatted) { uuids.append(formatted) }
                    }
                    break
                }
            }
        }

        // 兼容 Binary Images 行里的 <uuid>（如火山导出的 iOS crash 文本）
        let pattern = #"<([0-9A-Fa-f-]{32,36})>"#
        let nsText = text as NSString
        if let regex = try? NSRegularExpression(pattern: pattern) {
            for match in regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
                guard match.numberOfRanges >= 2 else { continue }
                let raw = nsText.substring(with: match.range(at: 1))
                let compact = raw.replacingOccurrences(of: "-", with: "").uppercased()
                guard compact.count == 32, compact.allSatisfy({ $0.isHexDigit }) else { continue }
                let formatted = formatUUID(compact)
                if !uuids.contains(formatted) { uuids.append(formatted) }
            }
        }
        return uuids
    }

    private static func formatUUID(_ hex: String) -> String {
        guard hex.count == 32 else { return hex }
        let a = hex.prefix(8)
        let b = hex.dropFirst(8).prefix(4)
        let c = hex.dropFirst(12).prefix(4)
        let d = hex.dropFirst(16).prefix(4)
        let e = hex.suffix(12)
        return "\(a)-\(b)-\(c)-\(d)-\(e)"
    }

    private static func extractBinaryImages(from text: String) -> [BinaryImage] {
        var images: [BinaryImage] = []
        let lines = text.components(separatedBy: .newlines)
        var inBinaryImages = false
        for line in lines {
            if line.contains("Binary Images:") { inBinaryImages = true; continue }
            if !inBinaryImages { continue }
            if line.isEmpty { break }
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            // 0x100000000 - 0x100123456  App (1.0) <UUID>  /path
            guard parts.count >= 4 else { break }
            guard let loadAddr = parseHex(String(parts[0])) else { break }

            var arch = "arm64"
            var uuid: String?
            var name = ""
            for (i, p) in parts.enumerated() {
                let s = String(p)
                if s.uppercased() == "UUID" && i + 1 < parts.count {
                    uuid = String(parts[i + 1])
                    break
                }
                if i >= 2 && !s.hasPrefix("0x") && s != "UUID" {
                    if name.isEmpty { name = s }
                    break
                }
            }
            if uuid == nil {
                // 常见形式：... Name arch <uuid> /path
                if let token = parts.first(where: { $0.first == "<" && $0.last == ">" }) {
                    let raw = String(token.dropFirst().dropLast())
                    let compact = raw.replacingOccurrences(of: "-", with: "").uppercased()
                    if compact.count == 32, compact.allSatisfy({ $0.isHexDigit }) {
                        uuid = formatUUID(compact)
                    }
                }
            }
            if parts.count >= 4 {
                let maybeArch = String(parts[3]).lowercased()
                if maybeArch.hasPrefix("arm") || maybeArch.hasPrefix("x86") {
                    arch = String(parts[3])
                }
            }
            if name.isEmpty, parts.count >= 3 { name = String(parts[2]) }
            images.append(BinaryImage(loadAddress: loadAddr, architecture: arch, name: name, uuid: uuid))
        }
        return images
    }

    /// 三方平台（如火山）经常把原始 iOS 崩溃文本塞进 JSON 的 `data` 字段。
    private static func extractEmbeddedCrashText(from data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let candidates = ["data", "crash_log", "crashLog", "stack", "stack_trace", "raw"]
        for key in candidates {
            if let s = obj[key] as? String, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return s
            }
        }
        return nil
    }

    /// 兜底兼容：有些导出会把换行保留为字面量 "\\n"，这里统一还原为真实换行。
    private static func normalizeCrashText(_ text: String) -> String {
        if text.contains("\n") { return text }
        if text.contains("\\n") {
            return text
                .replacingOccurrences(of: "\\r\\n", with: "\n")
                .replacingOccurrences(of: "\\n", with: "\n")
                .replacingOccurrences(of: "\\t", with: "\t")
        }
        return text
    }

    private static func parseHex(_ s: String) -> UInt64? {
        var s = s
        if s.hasPrefix("0x") { s = String(s.dropFirst(2)) }
        return UInt64(s, radix: 16)
    }
}
