//
//  OverviewView.swift
//  SymPro
//

import SwiftUI

struct OverviewView: View {
    @ObservedObject var state: SymbolicateWorkspaceState
    @ObservedObject private var settings = SettingsStore.shared

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            VStack(alignment: .leading, spacing: 14) {
                if let crash = state.crashLog {
                    translatedReportDetail(crash: crash)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    Text("Please import .ips / .crash files using the left Open File button.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

//                Divider().padding(.vertical, 6)

                // VStack(spacing: 0) {
                //     ActionBarView(state: state)
                //     Divider()
                //     ResultSectionView(state: state)
                // }
                // .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .alert(
            "Symbolication Failed",
            isPresented: Binding(
                get: { state.symbolicationError != nil },
                set: { presented in
                    if !presented { state.symbolicationError = nil }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(state.symbolicationError ?? "")
        }
    }

    private var header: some View {
        HStack {
            Text("Overview")
                .font(.headline)
            Spacer()

            if let crash = state.crashLog {
                if state.isSymbolicating {
                    ProgressView().scaleEffect(0.7)
                } else {
                    Button {
                        state.startSymbolication()
                    } label: {
                            Label("Symbolicate", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(state.selectedDSYMByImageUUID.isEmpty)
                        .help(state.selectedDSYMByImageUUID.isEmpty ? "No matching dSYM found; cannot symbolicate" : "Resolve stack symbols using matched dSYMs")
                }

                Text(crash.fileName)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else if state.isLoadingCrashLog {
                ProgressView().scaleEffect(0.5)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private func translatedReportDetail(crash: CrashLog) -> some View {
        let baseText = state.symbolicatedText.isEmpty ? crash.rawText : state.symbolicatedText
        let text = ReportDisplayStyle.translatedReportOnly(baseText)
        return ScrollView([.horizontal, .vertical], showsIndicators: true) {
            Text(ReportDisplayStyle.attributedReport(text: text, processName: crash.processName, fontSize: settings.resultFontSize))
                .textSelection(.enabled)
                .frame(minWidth: ReportDisplayStyle.reportMinWidth, alignment: .topLeading)
                .padding()
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

}

#Preview {
    OverviewView(state: SymbolicateWorkspaceState())
        .frame(width: 1000, height: 700)
}

