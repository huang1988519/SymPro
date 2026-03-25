import SwiftUI

struct CrashAnalyzerLeftSidebarView: View {
    let model: CrashReportModel?
    @Binding var selectedThreadIndex: Int
    @State private var showCrashReasonPopover: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let model {
                appHeader(model: model)
                Divider().opacity(0.9)
                threadsSection(model: model)
            } else {
                Text("sidebar.noData", comment: "Message when no crash data is loaded")
                    .foregroundStyle(Color.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
    }

    private func appHeader(model: CrashReportModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1)
                        )
                    Image(systemName: "doc.text")
                        .foregroundStyle(Color.primary.opacity(0.75))
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 3) {
                    Text(model.overview.process)
                        .font(.system(size: 14, weight: .semibold))
                    Text(model.overview.identifier)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                infoRow(key: L10n.t("Version:"), value: model.overview.version)
                infoRow(key: L10n.t("OS:"), value: model.overview.osVersion)
                HStack(spacing: 6) {
                    Text(L10n.t("Exception:"))
                        .foregroundStyle(Color.secondary)
                        .frame(width: 70, alignment: .leading)
                    Text(model.overview.exceptionType.isEmpty ? "-" : model.overview.exceptionType)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Button {
                        showCrashReasonPopover = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.secondary)
                    .help(L10n.t("About this crash type"))
                    .popover(isPresented: $showCrashReasonPopover, arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L10n.t("Possible cause for this crash type"))
                                .font(.system(size: 12, weight: .semibold))
                            Text(crashReasonText(for: model.overview.exceptionType))
                                .font(.system(size: 11))
                                .foregroundStyle(Color.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(12)
                        .frame(width: 320, alignment: .leading)
                    }
                }
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(Color.secondary)
        }
    }

    private func infoRow(key: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(key)
                .foregroundStyle(Color.secondary)
                .frame(width: 70, alignment: .leading)
            Text(value.isEmpty ? "-" : value)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private func crashReasonText(for exceptionType: String) -> String {
        let t = exceptionType.uppercased()
        if t.contains("EXC_BAD_ACCESS") {
            return L10n.t("Crash reason: EXC_BAD_ACCESS")
        }
        if t.contains("EXC_BREAKPOINT") || t.contains("SIGTRAP") {
            return L10n.t("Crash reason: EXC_BREAKPOINT")
        }
        if t.contains("SIGABRT") || t.contains("EXC_CRASH") {
            return L10n.t("Crash reason: SIGABRT")
        }
        if t.contains("SIGKILL") {
            return L10n.t("Crash reason: SIGKILL")
        }
        if t.contains("WATCHDOG") {
            return L10n.t("Crash reason: Watchdog")
        }
        return L10n.t("Crash reason: Unknown")
    }

    private func threadsSection(model: CrashReportModel) -> some View {
        let threads = model.threads.filter { !$0.frames.isEmpty }
        return VStack(alignment: .leading, spacing: 8) {
            Text("sidebar.threads.title", comment: "Section header for threads list")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.secondary)

            Group {
                if #available(macOS 13.0, *) {
                    List(selection: $selectedThreadIndex) {
                        ForEach(threads) { t in
                            threadRow(t)
                                .tag(t.index)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                } else {
                    List {
                        ForEach(threads) { t in
                            Button {
                                selectedThreadIndex = t.index
                            } label: {
                                threadRow(t)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(
                                selectedThreadIndex == t.index
                                    ? Color.accentColor.opacity(0.22)
                                    : Color.clear
                            )
                        }
                    }
                    .listStyle(.plain)
                }
            }
        }
    }

    private func threadRow(_ t: CrashReportModel.Thread) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(L10n.tFormat("Thread %d", t.index))
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                if t.triggered {
                    Text("sidebar.thread.crashed", comment: "Label for crashed thread")
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(Color.red.opacity(0.12))
                        )
                        .overlay(
                            Capsule().stroke(Color.red, lineWidth: 1)
                        )
                        .foregroundColor(.red)
                }
            }
            if let q = t.queue, !q.isEmpty {
                Text(q)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.vertical, 4)
    }
}

