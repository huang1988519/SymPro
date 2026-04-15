import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

struct CrashAnalyzerDSYMPanel: View {
    @EnvironmentObject private var state: SymbolicateWorkspaceState
    @ObservedObject private var discovery = DSYMAutoDiscoveryStore.shared
    @State private var dsymInfo: DSYMInfoPresentation?
    @State private var uuidMismatchAlertMessage: String?
    @State private var showAllMachO: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DSYMDiscoveryDirectoriesCard()

            if let crash = state.crashLog {
                let entries = uuidEntries(crash: crash, showAll: showAllMachO)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Toggle(L10n.t("Show system images"), isOn: $showAllMachO)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        Spacer(minLength: 0)
                        Text(L10n.tFormat("Showing %d / %d", entries.count, crash.uuidList.count))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(entries) { entry in
                                let uuid = entry.uuid
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.name)
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                        Text(uuid)
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundStyle(Color.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                    Spacer(minLength: 8)
                                    if let selected = state.selectedDSYMByImageUUID[uuid] {
                                        let isManual = state.manualDSYMOverrideByImageUUID[uuid] != nil
                                        HStack(spacing: 6) {
                                            Text(isManual ? L10n.t("Manual") : L10n.t("Auto"))
                                                .font(.caption2.weight(.semibold))
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 3)
                                                .background((isManual ? Color.accentColor : Color.green).opacity(0.18))
                                                .foregroundStyle(isManual ? Color.accentColor : Color.primary)
                                                .clipShape(Capsule())

                                            if !entry.isSystem {
                                                Button(L10n.t("Select dSYM…")) {
                                                    pickAndValidateDSYM(forImageUUID: uuid, imageName: entry.name)
                                                }
                                                .buttonStyle(.plain)
                                                .font(.caption)
                                            }

                                            Button {
                                                dsymInfo = DSYMInfoPresentation(
                                                    uuid: uuid,
                                                    imageName: entry.name,
                                                    url: selected,
                                                    isManual: isManual
                                                )
                                            } label: {
                                                Image(systemName: "info.circle")
                                                    .font(.system(size: 11, weight: .semibold))
                                            }
                                            .buttonStyle(.plain)
                                            .foregroundStyle(Color.secondary)
                                            .help(L10n.t("View dSYM details"))
                                        }
                                    } else if !entry.isSystem {
                                        let discovered = discovery.resolveDSYMURL(forUUID: uuid)?.url
                                        HStack(spacing: 6) {
                                            let label = discovered != nil ? L10n.t("Auto-match available") : L10n.t("Missing")
                                            Text(label)
                                                .font(.caption2.weight(.semibold))
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 3)
                                                .background(Color.secondary.opacity(0.12))
                                                .foregroundStyle(.secondary)
                                                .clipShape(Capsule())

                                            Button(L10n.t("Select dSYM…")) {
                                                pickAndValidateDSYM(forImageUUID: uuid, imageName: entry.name)
                                            }
                                            .buttonStyle(.plain)
                                            .font(.caption)
                                        }
                                    }
                                }
                                Divider()
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
//                    .frame(maxHeight: 200)

                    HStack(spacing: 8) {
                        Button(L10n.t("Re-match")) {
                            state.recomputeResolvedDSYMSelection()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(crash.uuidList.isEmpty)
                    }
                }
                .padding(.top, 2)
            }
        }
        .sheet(item: $dsymInfo) { info in
            DSYMInfoSheet(info: info)
        }
        .alert(L10n.t("UUID mismatch"), isPresented: Binding(
            get: { uuidMismatchAlertMessage != nil },
            set: { newValue in
                if !newValue { uuidMismatchAlertMessage = nil }
            }
        )) {
            Button(L10n.t("Done")) {
                uuidMismatchAlertMessage = nil
            }
        } message: {
            Text(uuidMismatchAlertMessage ?? "")
        }
    }

    private func imageNameByUUID(crash: CrashLog) -> [String: String] {
        // 优先使用结构化 usedImages（.ips），否则退回 parser 的 binaryImages
        if let model = state.symbolicatedModel ?? crash.model {
            let pairs: [(String, String)] = model.images.compactMap { img in
                guard let uuid = img.uuid, !uuid.isEmpty else { return nil }
                let name = img.name.isEmpty ? "Unknown Image" : img.name
                return (uuid, name)
            }
            return Dictionary(pairs, uniquingKeysWith: { first, _ in first })
        }

        let pairs: [(String, String)] = crash.binaryImages.compactMap { img in
            guard let uuid = img.uuid, !uuid.isEmpty else { return nil }
            let name = img.name.isEmpty ? "Unknown Image" : img.name
            return (uuid, name)
        }
        return Dictionary(pairs, uniquingKeysWith: { first, _ in first })
    }

    private func uuidEntries(crash: CrashLog, showAll: Bool) -> [UUIDDisplayEntry] {
        let names = imageNameByUUID(crash: crash)
        let pathByUUID: [String: String] = {
            if let model = state.symbolicatedModel ?? crash.model {
                let pairs = model.images.compactMap { img -> (String, String)? in
                    guard let u = img.uuid, !u.isEmpty else { return nil }
                    return (u, img.path ?? "")
                }
                return Dictionary(pairs, uniquingKeysWith: { first, _ in first })
            }
            return [:]
        }()

        return crash.uuidList.compactMap { uuid in
            let name = names[uuid] ?? "Unknown Image"
            let path = pathByUUID[uuid]
            let isSystem = isSystemImage(name: name, path: path)
            if !showAll && isSystem { return nil }
            return UUIDDisplayEntry(uuid: uuid, name: name, isSystem: isSystem)
        }
    }

    private func isSystemImage(name: String, path: String?) -> Bool {
        if let path {
            if path.hasPrefix("/System/") ||
                path.hasPrefix("/usr/lib/") ||
                path.hasPrefix("/usr/libexec/") ||
                path.hasPrefix("/Volumes/VOLUME/") {
                return true
            }
        }
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if n.hasPrefix("libsystem") || n.hasPrefix("libobjc") || n.hasPrefix("libdispatch") || n.hasPrefix("libc++") || n == "dyld" {
            return true
        }
        if n.hasPrefix("UIKit") ||
            n.hasPrefix("Foundation") ||
            n.hasPrefix("Core") ||
            n.hasPrefix("Quartz") ||
            n.hasPrefix("CFNetwork") ||
            n.hasPrefix("GraphicsServices") {
            return true
        }
        return false
    }

    private func pickAndValidateDSYM(forImageUUID uuid: String, imageName: String) {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.treatsFilePackagesAsDirectories = true
        panel.title = L10n.tFormat("Select dSYM for %@", imageName)
        if panel.runModal() == .OK, let url = panel.url {
            let selectedUUID = DSYMUUIDResolver.resolveUUID(at: url)?.uuidString
            guard let selectedUUID else {
                uuidMismatchAlertMessage = L10n.t("Cannot read UUID from selected dSYM.")
                return
            }
            guard selectedUUID == uuid else {
                uuidMismatchAlertMessage = L10n.tFormat(
                    "Selected dSYM UUID (%@) does not match binary UUID (%@).",
                    selectedUUID,
                    uuid
                )
                return
            }
            state.assignSelectedDSYM(forImageUUID: uuid, url: url)
        }
        #endif
    }
}

// NOTE: dSYM auto-discovery directory management UI has been extracted to `DSYMDiscoveryDirectoriesCard`.
private extension CrashAnalyzerDSYMPanel {}

private struct UUIDDisplayEntry: Identifiable {
    var id: String { uuid }
    let uuid: String
    let name: String
    let isSystem: Bool
}

private struct DSYMInfoPresentation: Identifiable {
    var id: String { uuid }
    let uuid: String
    let imageName: String
    let url: URL
    let isManual: Bool
}

private struct DSYMInfoSheet: View {
    let info: DSYMInfoPresentation

    @EnvironmentObject private var state: SymbolicateWorkspaceState
    @Environment(\.dismiss) private var dismiss
    @State private var details: DSYMInspector.DSYMDetails?
    @State private var samples: [DSYMInspector.SampleSymbolication] = []
    @State private var manualHex: String = ""
    @State private var manualOffset: String = ""
    @State private var manualUseTextVMAddr: Bool = true
    @State private var manualResultText: String = ""
    @State private var manualErrorText: String = ""
    @State private var isManualResolving: Bool = false

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 16) {
                headerSection
                statusSection
                basicInfoSection
                manualSymbolicationSection
                bottomBar
            }
            .padding(16)
        }
        .frame(minWidth: 520, minHeight: 320)
        .task {
            // 读取 dSYM 详情时也需要安全作用域（自动发现的路径可能来自书签根目录）
            let stop = DSYMAutoDiscoveryStore.shared.startAccessingIfNeeded(for: info.url)
            defer { stop?() }
            details = DSYMInspector.inspect(dsymURL: info.url)

            // 从当前 crash 中抽取该 UUID 的若干 pc/off 做样例符号化
            let addrs = samplePCsAndOffsets(forUUID: info.uuid)
            samples = DSYMInspector.sampleSymbolicate(dsymURL: info.url, pcs: addrs.pcs, imageOffsets: addrs.offsets)
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(info.imageName)
                .font(.headline)
            Text(info.isManual ? L10n.t("Source: Manual selection") : L10n.t("Source: Auto-matched"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var statusSection: some View {
        Group {
            if let d = details, let binUUID = d.file.uuid, !binUUID.isEmpty {
                let matched = (binUUID == info.uuid)
                HStack(spacing: 8) {
                    Image(systemName: matched ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(matched ? Color.green : Color.orange)
                    Text(matched ? L10n.t("UUID Matched") : L10n.t("UUID Not Matched"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(matched ? Color.green : Color.orange)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background((matched ? Color.green : Color.orange).opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                Text(L10n.t("Loading…"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var basicInfoSection: some View {
        GroupBox(L10n.t("Basic Information")) {
            VStack(alignment: .leading, spacing: 12) {
                if let d = details {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12) {
                        gridCell(title: L10n.t("Architecture"), value: architectureText(from: d))
                        gridCell(title: L10n.t("File Size"), value: fileSizeText(from: d))
                        gridCell(title: L10n.t("Modified"), value: modifiedText(from: d))
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(L10n.t("UUID"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(info.uuid, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.plain)
                    }
                    Text(info.uuid)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.t("Path"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Button(shortenedPath(info.url.path)) {
                        openPathInFinder()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .font(.system(.caption, design: .monospaced))
                    .help(info.url.path)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
        }
    }

    private var manualSymbolicationSection: some View {
        GroupBox(L10n.t("Manual Symbolication")) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    TextField(L10n.t("Address (hex, e.g. 0x1044c43b0)"), text: $manualHex)
                        .textFieldStyle(.roundedBorder)
                    TextField(L10n.t("imageOffset (optional, decimal)"), text: $manualOffset)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                    Button(isManualResolving ? L10n.t("Symbolicating…") : L10n.t("Symbolicate")) {
                        runManualSymbolication()
                    }
                    .disabled(isManualResolving || manualHex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Toggle(L10n.t("Use Offset"), isOn: $manualUseTextVMAddr)
                    .toggleStyle(.switch)

                if !manualErrorText.isEmpty {
                    Text(manualErrorText)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }

                if !manualResultText.isEmpty {
                    Text(manualResultText)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Button(L10n.t("Show in Finder")) {
                openPathInFinder()
            }
            .buttonStyle(.borderedProminent)

            Spacer(minLength: 0)

            Button(L10n.t("Close")) { dismiss() }
                .buttonStyle(.bordered)
        }
    }

    private func gridCell(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func architectureText(from details: DSYMInspector.DSYMDetails) -> String {
        if !details.arch.architectures.isEmpty { return details.arch.architectures.joined(separator: ", ") }
        if details.arch.isFat { return L10n.t("fat binary") }
        return "-"
    }

    private func fileSizeText(from details: DSYMInspector.DSYMDetails) -> String {
        guard let size = details.file.fileSize else { return "-" }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    private func modifiedText(from details: DSYMInspector.DSYMDetails) -> String {
        guard let d = details.file.modificationDate else { return "-" }
        return format(date: d)
    }

    private func shortenedPath(_ path: String) -> String {
        let parts = path.split(separator: "/")
        guard parts.count > 3 else { return path }
        return ".../\(parts.suffix(3).joined(separator: "/"))"
    }

    private func openPathInFinder() {
        #if os(macOS)
        NSWorkspace.shared.selectFile(info.url.path, inFileViewerRootedAtPath: "")
        #endif
    }

    private func samplePCsAndOffsets(forUUID uuid: String) -> (pcs: [UInt64], offsets: [Int?]) {
        guard let crash = state.crashLog else { return ([], []) }
        guard let model = state.symbolicatedModel ?? crash.model else { return ([], []) }
        guard let img = model.images.first(where: { ($0.uuid ?? "") == uuid }) else { return ([], []) }
        let imageName = img.name

        let frames = model.threads
            .first(where: { $0.triggered })?.frames ?? model.threads.first?.frames ?? []

        let picked = frames.filter { $0.imageName == imageName }.prefix(3)
        return (picked.map { $0.address }, picked.map { $0.imageOffset })
    }

    private func format(date: Date) -> String {
        let f = DateFormatter()
        f.locale = .current
        f.dateStyle = .medium
        f.timeStyle = .medium
        return f.string(from: date)
    }

    private func runManualSymbolication() {
        manualErrorText = ""
        manualResultText = ""
        isManualResolving = true

        let stop = DSYMAutoDiscoveryStore.shared.startAccessingIfNeeded(for: info.url)

        Task.detached(priority: .userInitiated) {
            defer { stop?() }

            let hex = manualHex.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let pc = parseHexUInt64(hex) else {
                await MainActor.run {
                    isManualResolving = false
                    manualErrorText = L10n.tFormat("Invalid address format: %@", hex)
                }
                return
            }

            let offsetInt: Int? = {
                let s = manualOffset.trimmingCharacters(in: .whitespacesAndNewlines)
                if s.isEmpty { return nil }
                return Int(s)
            }()

            let addrUsed: UInt64 = {
                if manualUseTextVMAddr, let off = offsetInt, let vm = DSYMInspector.readTextVMAddrForUI(dsymURL: info.url) {
                    return vm &+ UInt64(off)
                }
                return pc
            }()

            let res = DSYMInspector.symbolicate(dsymURL: info.url, address: addrUsed)
            await MainActor.run {
                isManualResolving = false
                switch res {
                case .success(let r):
                    let fn = (r.function?.isEmpty == false) ? r.function! : L10n.t("(No function name)")
                    let fl: String = {
                        if let f = r.file, !f.isEmpty, let l = r.line { return "\(f):\(l)" }
                        return L10n.t("(No file line number)")
                    }()
                    manualResultText = String(
                        format: L10n.t("pc=0x%016llx  used=0x%016llx\n%@\n%@"),
                        pc,
                        addrUsed,
                        fn,
                        fl
                    )
                case .failure(let err):
                    manualErrorText = err.localizedDescription
                }
            }
        }
    }

    private func parseHexUInt64(_ s: String) -> UInt64? {
        let t = s.lowercased().hasPrefix("0x") ? String(s.dropFirst(2)) : s
        return UInt64(t, radix: 16)
    }
}

struct CrashAnalyzerInsightPanel: View {
    @EnvironmentObject private var state: SymbolicateWorkspaceState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Insight Analysis")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.secondary)

            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.yellow.opacity(0.9))
                        Text("Anomaly Reason Diagnosis")
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                    }

                    if let crash = state.crashLog, let model = state.symbolicatedModel ?? crash.model {
                        Text(L10n.tFormat("Detected %@.", crash.fileName))
                            .font(.system(size: 11))
                            .foregroundStyle(Color.secondary)

                        Text(L10n.tFormat("Crash type: %@", model.overview.exceptionType))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color.secondary)

                        if let first = model.threads.first(where: { $0.triggered })?.frames.first,
                           let fn = first.symbol, !fn.isEmpty {
                            Text(L10n.tFormat("Top Frame：%@", fn))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Color.secondary)
                                .lineLimit(2)
                        }
                    } else {
                        Text("Show the diagnostic summary after opening a crash file.")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.secondary)
                    }
                }
                .padding(12)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
    }
}

