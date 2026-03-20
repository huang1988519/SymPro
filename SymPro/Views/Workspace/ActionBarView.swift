//
//  ActionBarView.swift
//  SymPro
//

import SwiftUI

struct ActionBarView: View {
    @ObservedObject var state: SymbolicateWorkspaceState

    var body: some View {
        HStack {
            if state.isSymbolicating {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Symbolication in progress…")
                    .foregroundStyle(.secondary)
            }
            if let error = state.symbolicationError {
                Text(error)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
            if state.crashLog != nil, state.selectedDSYMByImageUUID.isEmpty, !state.isSymbolicating {
                Text("Select dSYMs for images to resolve addresses into symbols")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}
