//
//  ReportDisplayStyle.swift
//  SymPro
//
//  按 Apple ips/崩溃报告样式格式化显示：等宽、分段标题加粗、对齐。
//

import Foundation
import SwiftUI

enum ReportDisplayStyle {
    /// 生成适合崩溃/ips 报告显示的 AttributedString（线程标题、Binary Images 等加粗）
    static func attributedString(from text: String, fontSize: CGFloat) -> AttributedString {
        var result = AttributedString()
        let lines = text.components(separatedBy: .newlines)
        let font = Font.system(size: fontSize, design: .monospaced)
        let boldFont = Font.system(size: fontSize, design: .monospaced).weight(.semibold)

        for (index, line) in lines.enumerated() {
            if index > 0 {
                result.append(AttributedString("\n"))
            }
            var lineAttr = AttributedString(line)
            lineAttr.font = font

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Thread N Crashed:: 或 Thread N::
            if trimmed.range(of: #"^Thread \d+ (Crashed)?::"#, options: .regularExpression) != nil {
                lineAttr.font = boldFont
            }
            // Binary Images:
            else if trimmed == "Binary Images:" || trimmed.hasPrefix("Binary Images:") {
                lineAttr.font = boldFont
            }
            // ----- 分隔线
            else if trimmed.hasPrefix("---") && trimmed.allSatisfy({ $0 == "-" }) {
                lineAttr.font = boldFont
            }
            // Process:, Path:, Exception Type: 等键行（键名加粗可选，此处整行一致以保持等宽对齐）
            else if trimmed.contains(":") && !trimmed.hasPrefix(" ") {
                let keyEnd = trimmed.firstIndex(of: ":") ?? trimmed.endIndex
                let keyPart = String(trimmed[..<keyEnd])
                if ["Process", "Path", "Identifier", "Version", "Exception Type", "Exception Codes",
                    "Termination Reason", "Triggered by Thread", "Date/Time", "Translated Report",
                    "Full Report"].contains(where: { keyPart.hasPrefix($0) }) {
                    // 仅对明显标题行做加粗（可选，保持简洁则不加粗整行）
                }
            }

            result.append(lineAttr)
        }
        return result
    }

    /// 报告正文使用等宽字体时的最小宽度，减少长行换行、保持列对齐（与 Apple 报告一致）
    static let reportMinWidth: CGFloat = 1400

    /// 带高亮的报告正文：属于目标 app（崩溃进程）的堆栈行红色加粗，其余等宽字体。
    /// - Parameters:
    ///   - text: 已截断为 Translated Report 的全文。
    ///   - processName: 崩溃进程名（主 app 镜像名），为 nil 则不高亮。
    ///   - fontSize: 等宽字体字号。
    /// - Returns: 用于 Text() 显示的 AttributedString。
    static func attributedReport(text: String, processName: String?, fontSize: CGFloat) -> AttributedString {
        guard !text.isEmpty else { return AttributedString("") }
        let lines = text.components(separatedBy: .newlines)
        let font = Font.system(size: fontSize, design: .monospaced)
        let appFrameFont = Font.system(size: fontSize, design: .monospaced).weight(.bold)
        var result = AttributedString()
        let appName = (processName ?? "").trimmingCharacters(in: .whitespaces)
        let isAppStackFrame: (String) -> Bool = { line in
            guard !appName.isEmpty else { return false }
            // 堆栈帧行格式: "0   SYM   \t0x..." 或 "1   AppKit   ..."
            guard let first = line.first, first.isNumber else { return false }
            let rest = line.dropFirst()
            guard let endOfNum = rest.firstIndex(where: { !$0.isNumber }) else { return false }
            let afterNum = rest[endOfNum...].trimmingCharacters(in: .whitespaces)
            guard afterNum.count >= appName.count else { return false }
            let possibleName = String(afterNum.prefix(appName.count))
            guard possibleName == appName else { return false }
            let next = afterNum.dropFirst(appName.count)
            guard next.first == " " || next.first == "\t" else { return false }
            return line.contains("0x")
        }
        for (index, line) in lines.enumerated() {
            if index > 0 {
                result.append(AttributedString("\n"))
            }
            var lineAttr = AttributedString(line)
            lineAttr.font = font
            if isAppStackFrame(line) {
                lineAttr.foregroundColor = .red
                lineAttr.font = appFrameFont
            }
            result.append(lineAttr)
        }
        return result
    }

    /// 只保留「Translated Report」部分，去掉 "----------- Full Report -----------" 及之后的 JSON 等全文。
    /// 与苹果解析后展示一致，不显示 Full Report 之后的内容。
    static func translatedReportOnly(_ fullText: String) -> String {
        let markers = [
            "\n-----------\nFull Report\n-----------",
            "\r\n-----------\r\nFull Report\r\n-----------",
            "-----------\nFull Report\n-----------",
            "-----------\r\nFull Report\r\n-----------",
        ]
        for marker in markers {
            if let range = fullText.range(of: marker) {
                return String(fullText[..<range.lowerBound])
            }
        }
        return fullText
    }
}
