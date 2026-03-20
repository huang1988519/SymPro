//
//  InputSectionView.swift
//  SymPro
//

import SwiftUI
import UniformTypeIdentifiers

struct InputSectionView: View {
    @ObservedObject var state: SymbolicateWorkspaceState
    @ObservedObject private var discovery = DSYMAutoDiscoveryStore.shared

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            crashLogDropZone
            dSYMDropZone
        }
        .padding()
    }

    private var crashLogDropZone: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Crash Log")
                .font(.headline)
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6]))
                        .foregroundStyle(.secondary)
                    if let crash = state.crashLog {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Image(systemName: "doc.text")
                                    .foregroundStyle(.secondary)
                                Text(crash.fileName)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .font(.subheadline.weight(.medium))

                            Text(
                                L10n.tFormat(
                                    "Parsed %d Mach-O images. Select a dSYM for each image.",
                                    crash.binaryImages.filter { $0.uuid != nil }.count
                                )
                            )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    } else {
                        Text("Drag or click to choose .crash / .ips")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 76)
                .contentShape(Rectangle())
                .onTapGesture { state.pickCrashLog() }
                .onDrop(of: [.fileURL, .plainText], isTargeted: nil) { providers in
                    state.handleCrashLogDrop(providers: providers)
                }

                if let crash = state.crashLog {
                    machoSelectionList(crash: crash)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func machoSelectionList(crash: CrashLog) -> some View {
        let images = uniqueImages(from: crash.binaryImages)
        return VStack(alignment: .leading, spacing: 6) {
            Text("Mach-O & dSYM Selection")
                .font(.subheadline.weight(.semibold))

            if images.isEmpty {
                Text("No image UUIDs found that can match dSYMs")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } else {
                List {
                    ForEach(images, id: \.id) { img in
                        machoRow(img: img)
                    }
                }
                .listStyle(.plain)
                .frame(height: 160)
            }
        }
    }

    private func machoRow(img: BinaryImage) -> some View {
        let uuid = img.uuid ?? ""
        let selected = uuid.isEmpty ? nil : state.selectedDSYMByImageUUID[uuid]
        let matchingImported = uuid.isEmpty ? [] : state.dsymItems.filter { $0.uuid?.uuidString == uuid }
        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(img.name)
                        .lineLimit(1)
                    Text(img.architecture)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if !uuid.isEmpty {
                    Text(uuid)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                if let url = selected {
                    Text(url.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text("No dSYM selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !uuid.isEmpty {
                Menu {
                    if !matchingImported.isEmpty {
                        Section("Choose from imported dSYMs (UUID match)") {
                            ForEach(matchingImported) { item in
                                Button(item.displayName) {
                                    state.assignSelectedDSYM(forImageUUID: uuid, url: item.path)
                                }
                            }
                        }
                        Divider()
                    }
                    Button("Select dSYM…") { state.pickDSYM(forImageUUID: uuid) }
                    if selected != nil {
                        Button("Clear selection") { state.clearSelectedDSYM(forImageUUID: uuid) }
                    }
                } label: {
                    Text("dSYM")
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func uniqueImages(from images: [BinaryImage]) -> [BinaryImage] {
        var seen = Set<String>()
        var result: [BinaryImage] = []
        for img in images {
            guard let uuid = img.uuid, !uuid.isEmpty, uuid != "00000000-0000-0000-0000-000000000000" else { continue }
            guard img.name != "???" else { continue }
            if seen.insert(uuid).inserted {
                result.append(img)
            }
        }
        return result
    }

    private var dSYMDropZone: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Auto-Discovered dSYMs")
                .font(.headline)
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6]))
                    .foregroundStyle(.secondary)
                discoveredDSYMList
            }
            .frame(height: 244)
            .contentShape(Rectangle())
            .onTapGesture { discovery.rescan() }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var discoveredDSYMList: some View {
        if state.crashLog == nil {
            Text("Import a crash log first; then go to Settings -> dSYM Auto Discovery to add search directories and scan.")
                .foregroundStyle(.secondary)
                .padding()
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Match Results")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button(L10n.t("Rescan")) { discovery.rescan() }
                        .buttonStyle(.link)
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)

                List {
                    ForEach(uniqueImages(from: state.crashLog?.binaryImages ?? []), id: \.id) { img in
                        discoveredRow(img: img)
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private func discoveredRow(img: BinaryImage) -> some View {
        let uuid = img.uuid ?? ""
        let resolved = uuid.isEmpty ? nil : discovery.resolveDSYMURL(forUUID: uuid)?.url
        let alreadySelected = uuid.isEmpty ? nil : state.selectedDSYMByImageUUID[uuid]
        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(img.name)
                        .lineLimit(1)
                    Text(img.architecture)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if !uuid.isEmpty {
                    Text(uuid)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                if let url = resolved {
                    Text(url.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text("No matching dSYM found")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let url = resolved, !uuid.isEmpty {
                Button(alreadySelected == nil ? "Assign" : "Assigned") {
                    state.assignSelectedDSYM(forImageUUID: uuid, url: url)
                }
                .disabled(alreadySelected == url)
            }
        }
        .padding(.vertical, 4)
    }
}
