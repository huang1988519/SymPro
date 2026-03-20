//
//  RawLogView.swift
//  SymPro
//

import SwiftUI
import AppKit

struct RawLogView: View {
    @ObservedObject var state: SymbolicateWorkspaceState
    @ObservedObject private var settings = SettingsStore.shared
    @State private var wrapLines = true
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Raw Log")
                    .font(.headline)
                Spacer()
                TextField("Search", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                Toggle("Wrap", isOn: $wrapLines)
                    .toggleStyle(.switch)
                Button("Copy") { copyToPasteboard(text) }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)

            Divider()

            Group {
                if wrapLines {
                    ScrollView(.vertical) {
                        Text(highlightedText)
                            .font(.system(size: settings.resultFontSize, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding()
                    }
                } else {
                    ScrollView(.horizontal) {
                        ScrollView(.vertical) {
                            Text(highlightedText)
                                .font(.system(size: settings.resultFontSize, design: .monospaced))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: true, vertical: false)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                                .padding()
                        }
                    }
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
    }

    private var text: String {
        if let crash = state.crashLog {
            return crash.sourceText
        }
        return ""
    }

    private var highlightedText: AttributedString {
        guard !query.isEmpty else { return AttributedString(text) }
        var out = AttributedString(text)
        let lowerText = text.lowercased()
        let q = query.lowercased()
        var searchRange = lowerText.startIndex..<lowerText.endIndex
        while let r = lowerText.range(of: q, options: [], range: searchRange) {
            if let ar = Range(r, in: out) {
                out[ar].backgroundColor = Color.yellow.opacity(0.45)
            }
            searchRange = r.upperBound..<lowerText.endIndex
        }
        return out
    }

    private func copyToPasteboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}

#Preview {
    RawLogView(state: SymbolicateWorkspaceState())
        .frame(width: 900, height: 600)
}

