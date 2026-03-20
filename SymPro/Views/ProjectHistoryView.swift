//
//  ProjectHistoryView.swift
//  SymPro
//

import SwiftUI

struct ProjectHistoryView: View {
    @ObservedObject private var historyStore = ProjectHistoryStore.shared

    var body: some View {
        Group {
            if historyStore.projects.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Project History")
                        .font(.title2)
                    Text("After successful symbolication, crash + dSYM combinations are saved to this list")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(historyStore.projects) { project in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(project.crashFileName)
                                .font(.headline)
                                .lineLimit(1)
                            Text(project.createdAt, style: .date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(L10n.tFormat("%d dSYMs", project.dsymPaths.count))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete(perform: historyStore.remove(at:))
                }
                .listStyle(.inset)
                .toolbar {
                    ToolbarItem(placement: .automatic) {
                        Button("Clear") {
                            historyStore.removeAll()
                        }
                        .disabled(historyStore.projects.isEmpty)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ProjectHistoryView()
}
