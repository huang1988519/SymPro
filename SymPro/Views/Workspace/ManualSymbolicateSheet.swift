import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

struct ManualSymbolicateSheet: View {
    @ObservedObject private var discovery = DSYMAutoDiscoveryStore.shared
    @EnvironmentObject private var state: SymbolicateWorkspaceState
    @Environment(\.dismiss) private var dismiss

    @State private var selectedUUID: String = ""
    @State private var lastCommittedUUID: String = ""
    @State private var selectedDSYMURL: URL?
    @State private var manualSelectedDisplayName: String = ""
    @State private var selectedDisplayUUID: String = ""
    @State private var manualHex: String = ""
    @State private var manualOffset: String = ""
    @State private var useOffset: Bool = true
    @State private var isResolving: Bool = false
    @State private var resultText: String = ""
    @State private var errorText: String = ""
    @State private var invalidDSYMAlertMessage: String?
    @State private var manualOption: (uuid: String, displayName: String, url: URL)?

    private let browsePickerTag = "__browse_dsym__"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox(L10n.t("dSYM")) {
                VStack(alignment: .leading, spacing: 10) {
                    Picker(L10n.t("Indexed dSYM"), selection: $selectedUUID) {
                        Text(L10n.t("Browse…")).tag(browsePickerTag)
                        Divider()
                        Text(L10n.t("Not selected")).tag("")
                        ForEach(mergedOptions, id: \.uuid) { option in
                            Text(option.displayName).tag(option.uuid)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: selectedUUID) { newValue in
                        if newValue == browsePickerTag {
                            selectedUUID = lastCommittedUUID
                            browseDSYM()
                            return
                        }
                        lastCommittedUUID = newValue
                        syncSelectedURLFromUUID()
                    }

                    if let selectedDSYMURL {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(
                                selectedDisplayUUID.isEmpty
                                    ? L10n.t("UUID: -")
                                    : L10n.tFormat("UUID: %@", selectedDisplayUUID)
                            )
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            Text(L10n.tFormat("Path: %@", shortenedPath(selectedDSYMURL.path)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(selectedDSYMURL.path)
                        }
                    } else {
                        Text(L10n.t("No dSYM selected"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }

            GroupBox(L10n.t("Manual Symbolication")) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        TextField(L10n.t("Address (hex, e.g. 0x1044c43b0)"), text: $manualHex)
                            .textFieldStyle(.roundedBorder)
                        TextField(L10n.t("imageOffset (optional, decimal)"), text: $manualOffset)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 220)
                    }
                    Toggle(L10n.t("Use Offset"), isOn: $useOffset)
                        .toggleStyle(.switch)

                    HStack(spacing: 10) {
                        Button(manualSymbolicateButtonTitle) {
                            runManualSymbolication()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isResolving || selectedDSYMURL == nil || manualHex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button(L10n.t("Copy")) {
                            #if os(macOS)
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(resultText, forType: .string)
                            #endif
                        }
                        .buttonStyle(.bordered)
                        .disabled(resultText.isEmpty)
                    }

                    if !errorText.isEmpty {
                        Text(errorText)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }

                    if !resultText.isEmpty {
                        Text(resultText)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .padding(.vertical, 2)
            }

            HStack {
                Spacer()
                Button(L10n.t("Close")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .frame(minWidth: 640, minHeight: 360)
        .onAppear {
            if selectedDSYMURL == nil, let first = mergedOptions.first {
                selectedUUID = first.uuid
                lastCommittedUUID = first.uuid
                selectedDisplayUUID = first.uuid
                selectedDSYMURL = first.url
            }
            normalizePickerSelectionIfNeeded()
        }
        .alert(L10n.t("Invalid dSYM"), isPresented: Binding(
            get: { invalidDSYMAlertMessage != nil },
            set: { newValue in
                if !newValue { invalidDSYMAlertMessage = nil }
            }
        )) {
            Button(L10n.t("Done")) {
                invalidDSYMAlertMessage = nil
            }
        } message: {
            Text(invalidDSYMAlertMessage ?? "")
        }
    }

    private var indexedOptions: [(uuid: String, displayName: String, url: URL)] {
        discovery.indexByUUID.values.compactMap { record in
            guard let resolved = discovery.resolveDSYMURL(forUUID: record.uuid)?.url else { return nil }
            return (record.uuid, record.displayName, resolved)
        }
        .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private var mergedOptions: [(uuid: String, displayName: String, url: URL)] {
        var items = indexedOptions
        if let manualOption, !items.contains(where: { $0.uuid == manualOption.uuid }) {
            items.insert(manualOption, at: 0)
        }
        return items
    }

    private func syncSelectedURLFromUUID() {
        if selectedUUID.isEmpty {
            // Keep manual-picked UUID visible when picker uses empty tag.
            if selectedDSYMURL == nil {
                selectedDisplayUUID = ""
            }
            return
        }
        selectedDisplayUUID = selectedUUID
        if let option = mergedOptions.first(where: { $0.uuid == selectedUUID }) {
            selectedDSYMURL = option.url
            manualSelectedDisplayName = option.displayName
        } else {
            selectedDSYMURL = discovery.resolveDSYMURL(forUUID: selectedUUID)?.url
        }
    }

    private func browseDSYM() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = L10n.t("Select")
        panel.title = L10n.t("Select dSYM")
        if panel.runModal() == .OK, let url = panel.url {
            guard let parsedUUID = DSYMUUIDResolver.resolveUUID(at: url)?.uuidString else {
                invalidDSYMAlertMessage = L10n.t("Cannot read UUID from selected dSYM.")
                return
            }
            selectedDSYMURL = url
            manualSelectedDisplayName = url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
            manualOption = (parsedUUID, manualSelectedDisplayName, url)
            selectedUUID = parsedUUID
            lastCommittedUUID = parsedUUID
            selectedDisplayUUID = parsedUUID
        }
        #endif
    }

    private func normalizePickerSelectionIfNeeded() {
        guard !selectedUUID.isEmpty else { return }
        let exists = indexedOptions.contains { $0.uuid == selectedUUID }
        if !exists {
            // Keep selection when it points to a manual option.
            if let manualOption, selectedUUID == manualOption.uuid {
                return
            }
            selectedUUID = ""
            lastCommittedUUID = ""
        }
    }

    private func shortenedPath(_ path: String) -> String {
        let parts = path.split(separator: "/")
        guard parts.count > 3 else { return path }
        return ".../\(parts.suffix(3).joined(separator: "/"))"
    }

    private func runManualSymbolication() {
        errorText = ""
        resultText = ""
        guard let dsymURL = selectedDSYMURL else {
            errorText = L10n.t("No dSYM selected")
            return
        }
        isResolving = true

        let stop = discovery.startAccessingIfNeeded(for: dsymURL)

        Task.detached(priority: .userInitiated) {
            defer { stop?() }

            let hex = manualHex.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let pc = parseHexUInt64(hex) else {
                await MainActor.run {
                    isResolving = false
                    errorText = L10n.tFormat("Invalid address format: %@", hex)
                }
                return
            }

            let offsetInt: Int? = {
                let s = manualOffset.trimmingCharacters(in: .whitespacesAndNewlines)
                if s.isEmpty { return nil }
                return Int(s)
            }()

            let addrUsed: UInt64 = {
                if useOffset, let off = offsetInt, let vm = DSYMInspector.readTextVMAddrForUI(dsymURL: dsymURL) {
                    return vm &+ UInt64(off)
                }
                return pc
            }()

            let res = DSYMInspector.symbolicate(dsymURL: dsymURL, address: addrUsed)
            await MainActor.run {
                isResolving = false
                switch res {
                case .success(let r):
                    let fn = (r.function?.isEmpty == false) ? r.function! : L10n.t("(No function name)")
                    let fl: String = {
                        if let f = r.file, !f.isEmpty, let l = r.line { return "\(f):\(l)" }
                        return L10n.t("(No file line number)")
                    }()
                    resultText = String(
                        format: L10n.t("pc=0x%016llx  used=0x%016llx\n%@\n%@"),
                        pc,
                        addrUsed,
                        fn,
                        fl
                    )
                case .failure(let err):
                    errorText = err.localizedDescription
                }
            }
        }
    }

    private var manualSymbolicateButtonTitle: String {
        if isResolving {
            return L10n.t("Symbolicating…")
        }
        if selectedDSYMURL == nil {
            return L10n.t("dSYM not found")
        }
        if manualHex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return L10n.t("Raw text")
        }
        return L10n.t("Symbolicate")
    }

    private func parseHexUInt64(_ s: String) -> UInt64? {
        let t = s.lowercased().hasPrefix("0x") ? String(s.dropFirst(2)) : s
        return UInt64(t, radix: 16)
    }
}
