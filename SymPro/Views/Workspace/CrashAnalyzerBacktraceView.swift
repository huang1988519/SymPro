import SwiftUI
#if os(macOS)
import AppKit
#endif

struct CrashAnalyzerBacktraceView: View {
    let model: CrashReportModel?
    @Binding var selectedThreadIndex: Int

    var body: some View {
        if let model {
            let threads = model.threads.filter { !$0.frames.isEmpty }
            let thread = threads.first(where: { $0.index == selectedThreadIndex }) ?? threads.first
            if let t = thread {
                frameTable(thread: t, appName: model.overview.process)
            } else {
                Text("No thread data available")
                    .foregroundStyle(Color.white.opacity(0.6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            Text("Structured backtrace is currently supported only for .ips files.")
                .foregroundStyle(Color.white.opacity(0.6))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func frameTable(thread: CrashReportModel.Thread, appName: String?) -> some View {
        let app = (appName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return Table(thread.frames) {
            TableColumn("#") { f in
                Text("\(f.index)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Color.secondary)
                    .frame(minWidth: 25, alignment: .center)
            }
            .width(25)

            TableColumn("LIBRARY") { f in
                let isApp = !app.isEmpty && f.imageName == app
                HStack(spacing: 8) {
                    imageIcon(kind: imageKind(name: f.imageName, appName: app))
                    Text(f.imageName)
                        .font(.system(size: 12, weight: isApp ? .semibold : .regular ))
                        .foregroundStyle(isApp ? Color.primary : Color.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .width(min: 50, ideal: 60, max: 200)

            TableColumn("SYMBOL / INSTRUCTION") { f in
                let isApp = !app.isEmpty && f.imageName == app
                Text(symbolText(for: f))
                    .font(.system(size: 12,  weight: isApp ? .semibold : .regular, design: .monospaced))
                    .foregroundStyle(isApp ? Color.red : Color.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(symbolHelp(for: f))
                    .contextMenu {
                        Button(L10n.t("Copy")) {
                            copyToPasteboard(symbolText(for: f))
                        }
                    }
                    .padding(5)
            }
        }
        .frame(minWidth: 350, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
    }

    private func symbolText(for f: CrashReportModel.Frame) -> String {
        let addr = String(format: "0x%016llx", f.address)
        if let s = f.symbol, !s.isEmpty {
            if let file = f.sourceFile, let line = f.sourceLine {
                return "\(s)  (\(URL(fileURLWithPath: file).lastPathComponent):\(line))"
            }
            if let loc = f.symbolLocation { return "\(s) + \(loc)" }
            return s
        }
        if let base = f.imageBase, let off = f.imageOffset {
            return String(format: "0x%016llx + %d", base, off)
        }
        return addr
    }

    private func symbolHelp(for f: CrashReportModel.Frame) -> String {
        var parts: [String] = []
        parts.append("Frame \(f.index)")
        parts.append("Library: \(f.imageName)")
        parts.append("Address: " + String(format: "0x%016llx", f.address))
        if let base = f.imageBase, let off = f.imageOffset {
            parts.append(String(format: "Image: 0x%016llx + %d", base, off))
        }
        if let s = f.symbol, !s.isEmpty {
            parts.append("Symbol: \(s)")
        }
        if let file = f.sourceFile, let line = f.sourceLine {
            parts.append("Source: \(file):\(line)")
        }
        return parts.joined(separator: "\n")
    }

    private func copyToPasteboard(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    private enum ImageKind {
        case app
        case swiftUI
        case system
        case other
    }

    private func imageKind(name: String, appName: String) -> ImageKind {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !appName.isEmpty, n == appName { return .app }
        if n == "SwiftUI" { return .swiftUI }

        // Backtrace 的 frame 不一定带 path，这里用常见系统镜像名做兜底
        let systemNames: Set<String> = [
            "dyld",
            "UIKitCore",
            "Foundation",
            "CoreFoundation",
            "QuartzCore",
            "libdispatch.dylib",
            "libsystem_kernel.dylib"
        ]
        if systemNames.contains(n) { return .system }
        if n.hasPrefix("libsystem") { return .system }
        if n.hasPrefix("lib") || n.hasSuffix(".dylib") { return .system }

        return .other
    }

    private func imageIcon(kind: ImageKind) -> some View {
        let (symbol, color): (String, Color) = {
            switch kind {
            case .app: return ("person.fill", Color.blue)
            case .swiftUI: return ("square.stack.3d.up.fill", Color.purple)
            case .system: return ("gearshape.fill", Color.secondary)
            case .other: return ("chevron.left.forwardslash.chevron.right", Color.purple)
            }
        }()

        return ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(color.opacity(0.9))
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
    }
}

