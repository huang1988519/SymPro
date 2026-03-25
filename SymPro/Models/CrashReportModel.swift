//
//  CrashReportModel.swift
//  SymPro
//

import Foundation

struct CrashReportModel {
    private static func normalizeUUIDString(_ s: String?) -> String? {
        guard let s, !s.isEmpty else { return nil }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if let u = UUID(uuidString: trimmed) { return u.uuidString }

        // 兼容 iOS 导出/三方导出：有些 uuid 可能是 32 位纯 hex（无短横线）。
        let compact = trimmed.replacingOccurrences(of: "-", with: "").uppercased()
        guard compact.count == 32, compact.allSatisfy({ $0.isHexDigit }) else { return nil }

        let formatted =
            "\(compact.prefix(8))-" +
            "\(compact.dropFirst(8).prefix(4))-" +
            "\(compact.dropFirst(12).prefix(4))-" +
            "\(compact.dropFirst(16).prefix(4))-" +
            "\(compact.suffix(12))"
        return UUID(uuidString: formatted)?.uuidString ?? formatted
    }
    struct Overview: Equatable {
        var process: String
        var pid: Int
        var identifier: String
        var version: String
        var path: String
        var dateTime: String
        var launchTime: String
        var osVersion: String
        var hardwareModel: String
        var exceptionType: String
        var exceptionSignal: String?
        var exceptionCodes: String
        var triggeredThread: Int
        var triggeredQueue: String?
        var incidentID: String
    }

    struct Frame: Equatable, Identifiable {
        let id = UUID()
        var index: Int
        var imageName: String
        var address: UInt64
        var symbol: String?
        var symbolLocation: Int?
        var sourceFile: String?
        var sourceLine: Int?
        var imageBase: UInt64?
        var imageOffset: Int?
    }

    struct Thread: Equatable, Identifiable {
        let id = UUID()
        var index: Int
        var name: String?
        var queue: String?
        var triggered: Bool
        var frames: [Frame]
    }

    struct Image: Equatable, Identifiable {
        let id = UUID()
        var index: Int
        var name: String
        var bundleId: String?
        var arch: String?
        var uuid: String?
        var base: UInt64?
        var size: UInt64?
        var path: String?
    }

    var overview: Overview
    var threads: [Thread]
    var images: [Image]
    var rawReportJSON: [String: AnyCodable]? = nil

    /// 仅用于 .ips：由 JSON 直接构建结构化模型。
    static func fromIPS(metadata: [String: Any], report: [String: Any]) -> CrashReportModel? {
        guard isCrashBugType309(metadata) else { return nil }

        let procName = report["procName"] as? String ?? (metadata["name"] as? String ?? "???")
        let pid = report["pid"] as? Int ?? 0
        let bundleInfo = report["bundleInfo"] as? [String: Any]
        let identifier = bundleInfo?["CFBundleIdentifier"] as? String ?? (metadata["bundleID"] as? String ?? "")
        let shortVer = bundleInfo?["CFBundleShortVersionString"] as? String ?? (metadata["app_version"] as? String ?? "")
        let buildVer = bundleInfo?["CFBundleVersion"] as? String ?? (metadata["build_version"] as? String ?? "")
        let version = shortVer.isEmpty ? buildVer : "\(shortVer) (\(buildVer))"
        let path = report["procPath"] as? String ?? ""
        let dateTime = report["captureTime"] as? String ?? ""
        let launchTime = report["procLaunch"] as? String ?? ""
        let osVersionObj = report["osVersion"] as? [String: Any]
        let train = osVersionObj?["train"] as? String ?? (metadata["os_version"] as? String ?? "")
        let build = osVersionObj?["build"] as? String ?? ""
        let osVersion = build.isEmpty ? train : "\(train) (\(build))"
        let hardwareModel = report["modelCode"] as? String ?? ""
        let exception = report["exception"] as? [String: Any]
        let excType = exception?["type"] as? String ?? ""
        let excSignal = exception?["signal"] as? String ?? ""
        let exceptionType = excSignal.isEmpty ? excType : "\(excType) (\(excSignal))"
        let exceptionCodes = exception?["codes"] as? String ?? ""
        let triggeredThread = report["faultingThread"] as? Int ?? 0
        let legacyInfo = report["legacyInfo"] as? [String: Any]
        let triggeredQueue = (legacyInfo?["threadTriggered"] as? [String: Any])?["queue"] as? String
        let incidentID = report["incident"] as? String ?? (metadata["incident_id"] as? String ?? "")

        var images: [Image] = []
        if let usedImages = report["usedImages"] as? [[String: Any]] {
            for (idx, img) in usedImages.enumerated() {
                images.append(Image(
                    index: idx,
                    name: img["name"] as? String ?? "???",
                    bundleId: img["CFBundleIdentifier"] as? String,
                    arch: img["arch"] as? String,
                    uuid: normalizeUUIDString(img["uuid"] as? String),
                    base: (img["base"] as? NSNumber)?.uint64Value,
                    size: (img["size"] as? NSNumber)?.uint64Value,
                    path: img["path"] as? String
                ))
            }
        }

        let imageNameByIndex: [Int: String] = Dictionary(uniqueKeysWithValues: images.map { ($0.index, $0.name) })

        var threads: [Thread] = []
        if let tArr = report["threads"] as? [[String: Any]] {
            for (idx, t) in tArr.enumerated() {
                let triggered = (t["triggered"] as? Bool) == true
                let queue = t["queue"] as? String
                let name = t["name"] as? String
                var frames: [Frame] = []
                let fArr = t["frames"] as? [[String: Any]] ?? []
                for (fidx, f) in fArr.enumerated() {
                    let imageIndex = f["imageIndex"] as? Int ?? 0
                    let imageOffset = (f["imageOffset"] as? NSNumber)?.intValue
                    let imageBase = imageIndex < images.count ? images[imageIndex].base : nil
                    let address = (imageBase ?? 0) + UInt64(imageOffset ?? 0)
                    let src = f["source"] as? [String: Any]
                    let file = src?["file"] as? String ?? src?["filename"] as? String
                    let line = (src?["line"] as? NSNumber)?.intValue ?? (src?["line"] as? Int)
                    frames.append(Frame(
                        index: fidx,
                        imageName: imageNameByIndex[imageIndex] ?? "???",
                        address: address,
                        symbol: f["symbol"] as? String,
                        symbolLocation: (f["symbolLocation"] as? NSNumber)?.intValue,
                        sourceFile: file,
                        sourceLine: line,
                        imageBase: imageBase,
                        imageOffset: imageOffset
                    ))
                }
                threads.append(Thread(index: idx, name: name, queue: queue, triggered: triggered, frames: frames))
            }
        }

        return CrashReportModel(
            overview: Overview(
                process: procName,
                pid: pid,
                identifier: identifier,
                version: version,
                path: path,
                dateTime: dateTime,
                launchTime: launchTime,
                osVersion: osVersion,
                hardwareModel: hardwareModel,
                exceptionType: exceptionType,
                exceptionSignal: excSignal.isEmpty ? nil : excSignal,
                exceptionCodes: exceptionCodes,
                triggeredThread: triggeredThread,
                triggeredQueue: triggeredQueue,
                incidentID: incidentID
            ),
            threads: threads,
            images: images,
            rawReportJSON: AnyCodable.wrap(report)
        )
    }

    /// 兼容 iOS/第三方导出“Translated Report 文本版”的 .ips：
    /// - 只有 metadata JSON + 人类可读 report 文本
    /// - 没有 structured JSON 字段（threads/usedImages）
    static func fromTranslatedReportText(_ text: String, processNameFallback: String? = nil) -> CrashReportModel? {
        let lines = text.components(separatedBy: .newlines)

        func valueAfterPrefix(_ prefix: String) -> String? {
            for line in lines {
                guard line.hasPrefix(prefix) else { continue }
                let rest = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
                if !rest.isEmpty { return rest }
            }
            return nil
        }

        func parseHex(_ s: String) -> UInt64? {
            var v = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if v.hasPrefix("0x") || v.hasPrefix("0X") { v = String(v.dropFirst(2)) }
            return UInt64(v, radix: 16)
        }

        func formatUUIDFromCompactHex(_ hex: String) -> String? {
            let compact = hex.replacingOccurrences(of: "-", with: "").uppercased()
            guard compact.count == 32, compact.allSatisfy({ $0.isHexDigit }) else { return nil }
            let a = compact.prefix(8)
            let b = compact.dropFirst(8).prefix(4)
            let c = compact.dropFirst(12).prefix(4)
            let d = compact.dropFirst(16).prefix(4)
            let e = compact.suffix(12)
            return "\(a)-\(b)-\(c)-\(d)-\(e)"
        }

        // --- Overview ---
        let procLinePrefix = "Process:"
        var procName = processNameFallback?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var pid: Int = 0
        for line in lines where line.hasPrefix(procLinePrefix) {
            let rest = line.dropFirst(procLinePrefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let open = rest.firstIndex(of: "["),
                  let close = rest.lastIndex(of: "]"),
                  close > open else {
                procName = rest
                continue
            }
            let namePart = rest[..<open].trimmingCharacters(in: .whitespacesAndNewlines)
            let pidPart = rest[rest.index(after: open)..<close].trimmingCharacters(in: .whitespacesAndNewlines)
            procName = String(namePart)
            pid = Int(pidPart) ?? 0
            break
        }

        let identifier = valueAfterPrefix("Identifier:") ?? ""
        let version = valueAfterPrefix("Version:") ?? ""
        let path = valueAfterPrefix("Path:") ?? ""
        let dateTime = valueAfterPrefix("Date/Time:") ?? ""
        let launchTime = valueAfterPrefix("Launch Time:") ?? ""
        let osVersion = valueAfterPrefix("OS Version:") ?? ""
        let hardwareModel = valueAfterPrefix("Hardware Model:") ?? ""
        let exceptionCodes = valueAfterPrefix("Exception Codes:") ?? ""
        let incidentID = valueAfterPrefix("Incident Identifier:") ?? ""

        let exceptionTypeLine = valueAfterPrefix("Exception Type:") ?? ""
        var exceptionType = exceptionTypeLine
        var exceptionSignal: String? = nil
        if let open = exceptionTypeLine.lastIndex(of: "("),
           let close = exceptionTypeLine.lastIndex(of: ")"),
           close > open {
            let before = exceptionTypeLine[..<open].trimmingCharacters(in: .whitespacesAndNewlines)
            let inside = exceptionTypeLine[exceptionTypeLine.index(after: open)..<close].trimmingCharacters(in: .whitespacesAndNewlines)
            if !inside.isEmpty {
                exceptionType = String(before)
                exceptionSignal = inside
            }
        }

        var triggeredThread = 0
        var triggeredQueue: String? = nil
        for line in lines where line.hasPrefix("Triggered by Thread:") {
            let rest = line.dropFirst("Triggered by Thread:".count).trimmingCharacters(in: .whitespacesAndNewlines)
            if let numRange = rest.range(of: #"^\d+"#, options: .regularExpression) {
                triggeredThread = Int(rest[numRange]) ?? 0
            } else {
                // 兜底：取前几个 token
                let firstToken = rest.split(separator: " ").first.map(String.init) ?? "0"
                triggeredThread = Int(firstToken) ?? 0
            }

            if let qRange = rest.range(of: "Dispatch Queue:") {
                let qRest = rest[qRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                if !qRest.isEmpty {
                    triggeredQueue = qRest
                }
            } else if let qRange = rest.range(of: "Dispatch queue:") {
                let qRest = rest[qRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                if !qRest.isEmpty { triggeredQueue = qRest }
            }
            break
        }

        // --- Threads / Frames ---
        var threadsByIndex: [Int: CrashReportModel.Thread] = [:]
        var currentThreadIndex: Int? = nil

        func parseThreadIndex(from line: String) -> Int? {
            guard line.hasPrefix("Thread ") else { return nil }
            let rest = line.dropFirst("Thread ".count)
            var digits = ""
            for ch in rest {
                guard ch.isNumber else { break }
                digits.append(ch)
            }
            return Int(digits)
        }

        for line in lines {
            if line.hasPrefix("Thread ") {
                guard let idx = parseThreadIndex(from: line) else { continue }
                currentThreadIndex = idx

                let isCrashed = line.contains("Crashed:")

                // name / queue
                var name: String? = nil
                var queue: String? = nil
                if line.contains("name:") {
                    if let range = line.range(of: "name:") {
                        var after = line[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                        if after.hasPrefix("Dispatch queue:") {
                            after = after.replacingOccurrences(of: "Dispatch queue:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                            queue = after
                        } else {
                            name = after
                        }
                    }
                }
                if line.contains("Dispatch queue:") {
                    // 兼容：有些行直接写了 Dispatch queue
                    if let range = line.range(of: "Dispatch queue:") {
                        let after = line[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                        if !after.isEmpty { queue = after }
                    }
                }

                if threadsByIndex[idx] == nil {
                    threadsByIndex[idx] = Thread(index: idx, name: name, queue: queue, triggered: isCrashed, frames: [])
                } else {
                    var t = threadsByIndex[idx]!
                    if name != nil { t.name = name }
                    if queue != nil { t.queue = queue }
                    if isCrashed { t.triggered = true }
                    threadsByIndex[idx] = t
                }
                continue
            }

            guard let idx = currentThreadIndex, threadsByIndex[idx] != nil else { continue }
            if line.contains("Binary Images:") { break }

            // Frame line (translated crash text):
            // 0   UIKitCore   0x....  -[UIAlertController _invokeHandlersForAction:] + 88
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            let parts = trimmed.split(whereSeparator: { $0.isWhitespace || $0 == "\t" })
            guard parts.count >= 4 else { continue }
            guard let fIndex = Int(parts[0]) else { continue }
            let imageName = String(parts[1])
            guard let pc = parseHex(String(parts[2])) else { continue }

            // Symbol can contain spaces; parse "+ offset" from tail.
            var parsedOffset: Int? = nil
            var parsedSymbol: String? = nil
            if let plusIndex = parts.lastIndex(where: { $0 == "+" || $0.hasSuffix("+") }),
               plusIndex + 1 < parts.count {
                let token = String(parts[plusIndex + 1])
                if token.hasPrefix("0x") || token.hasPrefix("0X") {
                    parsedOffset = parseHex(token).flatMap { Int($0) }
                } else {
                    parsedOffset = Int(token)
                }
                if plusIndex > 3 {
                    let symbolParts = parts[3..<plusIndex]
                    let symbol = symbolParts.map(String.init).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !symbol.isEmpty { parsedSymbol = symbol }
                }
            } else if parts.count > 3 {
                // Fallback: no "+ offset" tail, keep trailing text as symbol.
                let symbol = parts[3...].map(String.init).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                if !symbol.isEmpty { parsedSymbol = symbol }
            }

            var t = threadsByIndex[idx]!
            let frame = Frame(
                index: fIndex,
                imageName: imageName,
                address: pc,
                symbol: parsedSymbol,
                symbolLocation: parsedOffset,
                sourceFile: nil,
                sourceLine: nil,
                imageBase: nil,
                imageOffset: parsedOffset
            )
            t.frames.append(frame)
            threadsByIndex[idx] = t
        }

        let threads = threadsByIndex.keys.sorted().compactMap { threadsByIndex[$0] }

        // --- Binary Images (for images view + uuid mapping fallback) ---
        var images: [Image] = []
        var inBinaryImages = false
        for line in lines {
            if line.contains("Binary Images:") { inBinaryImages = true; continue }
            if !inBinaryImages { continue }
            if line.isEmpty { break }

            let parts = line.split(whereSeparator: { $0.isWhitespace || $0 == "\t" })
            guard parts.count >= 5 else { continue }
            guard let loadAddr = parseHex(String(parts[0])) else { break }

            // uuid token: <...>
            let uuidToken = parts.first { token in
                guard let first = token.first, let last = token.last else { return false }
                return first == "<" && last == ">"
            }
            let uuid: String? = uuidToken.map { token in
                let raw = token.dropFirst().dropLast()
                return formatUUIDFromCompactHex(String(raw))
            } ?? nil

            // arch token (arm/x86)
            let archToken = parts.first { token in
                let s = token.lowercased()
                return s.hasPrefix("arm") || s.hasPrefix("x86")
            }
            let arch = archToken.map { String($0) }

            // name token: try the token just before arch
            var name = ""
            if let archToken, let archIndex = parts.firstIndex(of: archToken), archIndex > 0 {
                let cand = parts[archIndex - 1]
                let candStr = String(cand)
                if !candStr.hasPrefix("0x") && candStr != "-" { name = candStr }
            }
            if name.isEmpty, parts.count >= 4 {
                // fallback：取第一个非 0x token
                if let cand = parts.dropFirst(2).first(where: { !String($0).hasPrefix("0x") && String($0) != "-" }) {
                    name = String(cand)
                }
            }

            // path token: token after uuid
            var imgPath: String? = nil
            if let uuidToken, let uuidIndex = parts.firstIndex(of: uuidToken), uuidIndex + 1 < parts.count {
                imgPath = String(parts[uuidIndex + 1])
            }

            images.append(Image(index: images.count, name: name.isEmpty ? "???" : name, bundleId: nil, arch: arch, uuid: uuid, base: loadAddr, size: nil, path: imgPath))
        }

        guard !threads.isEmpty else { return nil }

        return CrashReportModel(
            overview: Overview(
                process: procName.isEmpty ? (processNameFallback ?? "???") : procName,
                pid: pid,
                identifier: identifier,
                version: version,
                path: path,
                dateTime: dateTime,
                launchTime: launchTime,
                osVersion: osVersion,
                hardwareModel: hardwareModel,
                exceptionType: exceptionType,
                exceptionSignal: exceptionSignal,
                exceptionCodes: exceptionCodes,
                triggeredThread: triggeredThread,
                triggeredQueue: triggeredQueue,
                incidentID: incidentID
            ),
            threads: threads,
            images: images,
            rawReportJSON: nil
        )
    }

    private static func isCrashBugType309(_ metadata: [String: Any]) -> Bool {
        // bug_type 在不同 iOS/导出版本里可能是 String ("309") 或数字 (309)。
        if let s = metadata["bug_type"] as? String { return s == "309" }
        if let n = metadata["bug_type"] as? NSNumber { return n.intValue == 309 }
        if let i = metadata["bug_type"] as? Int { return i == 309 }
        return false
    }
}

/// 轻量 AnyCodable，用于把 JSON 作为调试信息保存（不用于 UI 大量渲染）。
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) { self.value = value }

    static func wrap(_ dict: [String: Any]) -> [String: AnyCodable] {
        var out: [String: AnyCodable] = [:]
        for (k, v) in dict { out[k] = AnyCodable(v) }
        return out
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode(Bool.self) { value = v; return }
        if let v = try? c.decode(Int.self) { value = v; return }
        if let v = try? c.decode(Double.self) { value = v; return }
        if let v = try? c.decode(String.self) { value = v; return }
        if let v = try? c.decode([String: AnyCodable].self) { value = v.mapValues { $0.value }; return }
        if let v = try? c.decode([AnyCodable].self) { value = v.map { $0.value }; return }
        value = NSNull()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch value {
        case let v as Bool: try c.encode(v)
        case let v as Int: try c.encode(v)
        case let v as Double: try c.encode(v)
        case let v as String: try c.encode(v)
        case let v as [String: Any]:
            try c.encode(v.mapValues { AnyCodable($0) })
        case let v as [Any]:
            try c.encode(v.map { AnyCodable($0) })
        default:
            try c.encodeNil()
        }
    }
}

