import SwiftUI

struct ManualSymbolicationWindowView: View {
    private enum RightPanel: Hashable {
        case hidden
        case dsymDirectories
    }

    @State private var rightPanel: RightPanel = .hidden

    var body: some View {
        HSplitView {
            VStack(spacing: 10) {
                Button {
                    rightPanel = .hidden
                } label: {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.system(size: 16, weight: rightPanel == .hidden ? .semibold : .regular))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .help("Manual Symbolication")

                Button {
                    rightPanel = (rightPanel == .dsymDirectories) ? .hidden : .dsymDirectories
                } label: {
                    Image(systemName: "folder.badge.gearshape")
                        .font(.system(size: 16, weight: rightPanel == .dsymDirectories ? .semibold : .regular))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .help("dSYM Discovery Directories")

                Spacer(minLength: 0)
            }
            .padding(.top, 12)
            .padding(.horizontal, 6)
            .frame(minWidth: 46, idealWidth: 54, maxWidth: 60)

            ScrollView(.vertical) {
                ManualSymbolicateSheet()
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(minWidth: 560, idealWidth: 720, maxWidth: .infinity)

            if rightPanel == .dsymDirectories {
                ScrollView(.vertical) {
                    DSYMDiscoveryDirectoriesCard()
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(minWidth: 420, idealWidth: 520, maxWidth: 620)
            }
        }
        .frame(minWidth: 1024, minHeight: 640)
    }
}

