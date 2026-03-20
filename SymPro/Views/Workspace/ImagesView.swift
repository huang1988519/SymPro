//
//  ImagesView.swift
//  SymPro
//

import SwiftUI
import Foundation

struct ImagesView: View {
    @ObservedObject var state: SymbolicateWorkspaceState
    @ObservedObject private var discovery = DSYMAutoDiscoveryStore.shared

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let model = state.crashLog?.model {
                List {
                    ForEach(model.images) { img in
                        imageRow(img)
                    }
                }
                .listStyle(.plain)
            } else {
                // 先兼容现有 BinaryImage（来自 crash 文本也有）
                if let crash = state.crashLog {
                    List {
                        ForEach(crash.binaryImages) { img in
                            legacyImageRow(img)
                        }
                    }
                    .listStyle(.plain)
                } else {
                    Text("Please import a crash log first")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Images")
                .font(.headline)
            Spacer()
            Button("Rescan dSYMs") { discovery.rescan() }
                .buttonStyle(.link)
            if let summary = matchSummaryText {
                Text(summary)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private var matchSummaryText: String? {
        guard let crash = state.crashLog else { return nil }
        let uuids = crash.uuidList
        if uuids.isEmpty { return nil }
        var need = 0
        var ok = 0
        for u in uuids {
            // 简化：uuidList 主要是“需要 dSYM 的候选”。真正不需要的（系统库）这里通常不会出现。
            need += 1
            if state.selectedDSYMByImageUUID[u] != nil { ok += 1 }
        }
        if need == 0 { return nil }
        return "Matched \(ok)/\(need)"
    }

    private func imageRow(_ img: CrashReportModel.Image) -> some View {
        let uuid = img.uuid ?? ""
        let selected = uuid.isEmpty ? nil : state.selectedDSYMByImageUUID[uuid]
        let isManual = uuid.isEmpty ? false : (state.manualDSYMOverrideByImageUUID[uuid] != nil)
        let discovered = uuid.isEmpty ? nil : discovery.resolveDSYMURL(forUUID: uuid)?.url
        let needsDSYM = needsDSYMForModelImage(img)
        return HStack(alignment: .top, spacing: 10) {
            imageIcon(kind: imageKind(name: img.name, path: img.path))
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(img.name)
                        .font(.body.weight(.medium))
                    if let arch = img.arch {
                        Text(arch)
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    Spacer(minLength: 10)
                }

                if let bundleId = img.bundleId, !bundleId.isEmpty {
                    HStack(spacing: 8) {
                        Text(bundleId)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 8)
                        if let size = img.size, size > 0 {
                            Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if let size = img.size, size > 0 {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if !uuid.isEmpty {
                    Text(uuid)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                if let path = img.path, !path.isEmpty {
                    Text(path)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 10)

            if !needsDSYM {
                EmptyView()
            } else {
                HStack(spacing: 8) {
                    dsymStatusPill(selected: selected, discovered: discovered, isManual: isManual)
                    dsymActions(uuid: uuid, selected: selected, discovered: discovered, isManual: isManual)
                }
                .padding(.top, 1)
            }
        }
        .padding(.vertical, 6)
    }

    private func legacyImageRow(_ img: BinaryImage) -> some View {
        let uuid = img.uuid ?? ""
        let selected = uuid.isEmpty ? nil : state.selectedDSYMByImageUUID[uuid]
        let isManual = uuid.isEmpty ? false : (state.manualDSYMOverrideByImageUUID[uuid] != nil)
        let discovered = uuid.isEmpty ? nil : discovery.resolveDSYMURL(forUUID: uuid)?.url
        let needsDSYM = needsDSYMForLegacyImage(img)
        return HStack(alignment: .top, spacing: 10) {
            imageIcon(kind: imageKind(name: img.name, path: nil))
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(img.name)
                        .font(.body.weight(.medium))
                    Text(img.architecture)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 10)
                }
                if !uuid.isEmpty {
                    Text(uuid)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 10)
            if !needsDSYM {
                EmptyView()
            } else {
                HStack(spacing: 8) {
                    dsymStatusPill(selected: selected, discovered: discovered, isManual: isManual)
                    dsymActions(uuid: uuid, selected: selected, discovered: discovered, isManual: isManual)
                }
                .padding(.top, 1)
            }
        }
        .padding(.vertical, 4)
    }

    private enum ImageKind {
        case app
        case swiftUI
        case system
        case other
    }

    private func imageKind(name: String, path: String?) -> ImageKind {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let proc = state.crashLog?.processName, !proc.isEmpty, n == proc { return .app }
        if n == "SwiftUI" { return .swiftUI }
        if let p = path {
            if p.contains("/SwiftUI.framework/") { return .swiftUI }
            if isSystemImagePath(p) { return .system }
        }
        // 常见系统镜像名（legacy/缺 path 时的兜底）
        if n.hasPrefix("libsystem") || n == "dyld" { return .system }
        return .other
    }

    private func imageIcon(kind: ImageKind) -> some View {
        let (symbol, color): (String, Color) = {
            switch kind {
            case .app: return ("person.fill", Color.blue)
            case .swiftUI: return ("square.stack.3d.up.fill", Color.purple)
            case .system: return ("gearshape.fill", Color(red: 0.63, green: 0.43, blue: 0.24))
            case .other: return ("chevron.left.forwardslash.chevron.right", Color.purple)
            }
        }()
        return ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(color)
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 22, height: 22)
    }

    @ViewBuilder
    private func dsymStatusPill(selected: URL?, discovered: URL?, isManual: Bool) -> some View {
        if let _ = selected {
            Text(isManual ? "Manual" : "Auto")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background((isManual ? Color.accentColor : Color.green).opacity(0.18))
                .foregroundStyle(isManual ? Color.accentColor : Color.primary)
                .clipShape(Capsule())
        } else {
            Text(discovered != nil ? "Auto-match available" : "Missing")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.secondary.opacity(0.12))
                .foregroundStyle(.secondary)
                .clipShape(Capsule())
        }
    }

    private func dsymActions(uuid: String, selected: URL?, discovered: URL?, isManual: Bool) -> some View {
        Group {
            if uuid.isEmpty {
                EmptyView()
            } else {
                Menu {
                    Button("Select dSYM…") { state.pickDSYM(forImageUUID: uuid) }
                    if let url = discovered, state.manualDSYMOverrideByImageUUID[uuid] == nil {
                        Button("Use auto-matched dSYM") { state.assignAutoDiscoveredDSYM(forImageUUID: uuid, url: url) }
                    }
                    if isManual {
                        Button("Clear override (back to auto)") { state.clearSelectedDSYM(forImageUUID: uuid) }
                    }
                    if let url = selected {
                        Divider()
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .imageScale(.medium)
                }
                .menuStyle(.borderlessButton)
                .help(L10n.t("dSYM actions"))
            }
        }
    }

    private func needsDSYMForModelImage(_ img: CrashReportModel.Image) -> Bool {
        guard let crash = state.crashLog else { return false }
        let uuid = (img.uuid ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !uuid.isEmpty else { return false }
        let name = img.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name == "???" { return false }

        // 1) 崩溃进程本身永远需要（用户最关心）
        if let proc = crash.processName, !proc.isEmpty, name == proc { return true }

        // 2) 系统镜像：通常不需要也无法提供 dSYM
        if let p = img.path {
            if isSystemImagePath(p) { return false }
        }

        // 3) 其它：默认可选（例如三方动态库/自研 framework）
        return true
    }

    private func needsDSYMForLegacyImage(_ img: BinaryImage) -> Bool {
        let uuid = (img.uuid ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !uuid.isEmpty else { return false }
        let name = img.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name == "???" { return false }
        // legacy 没有 path，保守策略：仅对崩溃进程镜像提示需要
        if let proc = state.crashLog?.processName, !proc.isEmpty, name == proc { return true }
        return false
    }

    private func isSystemImagePath(_ path: String) -> Bool {
        // 常见系统路径
        return path.hasPrefix("/System/") || path.hasPrefix("/usr/lib/") || path.hasPrefix("/usr/libexec/")
    }
}

#Preview {
    ImagesView(state: SymbolicateWorkspaceState())
        .frame(width: 1100, height: 700)
}

