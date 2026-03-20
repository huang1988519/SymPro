//
//  CrashLog.swift
//  SymPro
//

import Foundation

struct CrashLog: Identifiable {
    let id: UUID
    let fileURL: URL
    let fileName: String
    /// 原始文件内容（.ips 为 JSON 原文；.crash 为文本原文），用于 Raw Log 展示与调试。
    let sourceText: String
    let rawText: String
    /// 结构化报告模型（目前主要用于 .ips），用于 Overview/Threads/Images 页面。
    let model: CrashReportModel?
    /// 崩溃进程名（主 app 镜像名），用于高亮「目标 app」堆栈行。
    let processName: String?
    /// UUIDs extracted from Binary Images (for matching dSYMs).
    let uuidList: [String]
    /// Parsed binary image entries: load address, architecture, name, uuid.
    let binaryImages: [BinaryImage]

    init(id: UUID = UUID(), fileURL: URL, fileName: String, sourceText: String, rawText: String, model: CrashReportModel? = nil, processName: String? = nil, uuidList: [String], binaryImages: [BinaryImage]) {
        self.id = id
        self.fileURL = fileURL
        self.fileName = fileName
        self.sourceText = sourceText
        self.rawText = rawText
        self.model = model
        self.processName = processName
        self.uuidList = uuidList
        self.binaryImages = binaryImages
    }
}

struct BinaryImage: Identifiable {
    let id: UUID
    let loadAddress: UInt64
    let architecture: String
    let name: String
    let uuid: String?

    init(id: UUID = UUID(), loadAddress: UInt64, architecture: String, name: String, uuid: String?) {
        self.id = id
        self.loadAddress = loadAddress
        self.architecture = architecture
        self.name = name
        self.uuid = uuid
    }
}
