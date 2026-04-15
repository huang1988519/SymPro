import SwiftUI
import UniformTypeIdentifiers

struct CrashAnalyzerEmptyStateView: View {
    var isLoading: Bool
    var onOpen: () -> Void
    var onManualSymbolicate: () -> Void
    var onDropProviders: ([NSItemProvider]) -> Bool

    @State private var isDropTargeted: Bool = false

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            VStack {
                HStack {
                    Spacer()
                    Button {
                        onManualSymbolicate()
                    } label: {
                        Image(systemName: "wrench.and.screwdriver")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 28, height: 20)
                            .padding(10)
                    }
                    .buttonStyle(.plain)
                    .help(L10n.t("Manual Symbolicate…"))
                    .disabled(isLoading)
                }
                Spacer()
            }

            VStack(spacing: 18) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1)
                        .frame(width: 60, height: 60)
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.9))
                }

                VStack(spacing: 8) {
                    Text(L10n.t("Import Crash Report"))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.primary)
                    Text(L10n.t("Drag and drop .ips or .crash files to start forensic analysis."))
                        .font(.system(size: 12))
                        .foregroundStyle(Color.secondary)
                }

                Button {
                    onOpen()
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                (isDropTargeted ? Color.accentColor.opacity(0.45) : Color.secondary.opacity(0.35)),
                                style: StrokeStyle(lineWidth: 1, dash: [6, 6])
                            )
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color(nsColor: .controlBackgroundColor).opacity(isDropTargeted ? 0.9 : 0.7))
                            )
                        VStack(spacing: 10) {
                            Image(systemName: "folder")
                                .font(.system(size: 22, weight: .medium))
                                .foregroundStyle(Color.primary.opacity(0.75))
                            Text(L10n.t("Click to upload or drag files here"))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.secondary)
                        }
                        .padding(.vertical, 24)
                    }
                    .frame(width: 520, height: 140)
                }
                .buttonStyle(.plain)
                .onDrop(of: [.fileURL, .plainText], isTargeted: $isDropTargeted) { providers in
                    if isLoading { return false }
                    return onDropProviders(providers)
                }
                .disabled(isLoading)

                if isLoading {
                    HStack(spacing: 10) {
                        ProgressView()
                            .scaleEffect(0.9)
                        Text(L10n.t("Parsing kernel dump file…"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.secondary)
                    }
                    .padding(.top, 8)
                    .frame(width: 520)
                }
            }
        }
    }
}

