//
//  ResultSectionView.swift
//  SymPro
//

import SwiftUI
import AppKit

struct ResultSectionView: View {
    @ObservedObject var state: SymbolicateWorkspaceState
    @ObservedObject private var settings = SettingsStore.shared

    var body: some View {
        VStack(spacing: 0) {
            resultTextView(
                ReportDisplayStyle.translatedReportOnly(state.symbolicatedText),
                processName: state.crashLog?.processName
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func resultTextView(_ text: String, processName: String?) -> some View {
        ZStack {
            if text.isEmpty {
                Text("Symbolication results will appear here")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    reportTextContent(text, processName: processName)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
            }
        }
        .overlay(alignment: .topTrailing) {
            if !text.isEmpty {
                HStack(spacing: 8) {
                    Button("Copy") {
                        copyToPasteboard(text)
                    }
                    Button("Export…") {
                        state.exportSymbolicatedResult()
                    }
                }
                .padding(8)
            }
        }
    }

    /// 报告正文：等宽字体；目标 app 堆栈行红色加粗，其余正常。
    @ViewBuilder
    private func reportTextContent(_ text: String, processName: String?) -> some View {
        Text(ReportDisplayStyle.attributedReport(text: text, processName: processName, fontSize: settings.resultFontSize))
    }

    private func copyToPasteboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}
