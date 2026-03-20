//
//  CrashReportModel.swift
//  SymPro
//

import Foundation

struct CrashReportModel {
    private static func normalizeUUIDString(_ s: String?) -> String? {
        guard let s, !s.isEmpty else { return nil }
        return UUID(uuidString: s)?.uuidString
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
        guard (metadata["bug_type"] as? String) == "309" else { return nil }

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

