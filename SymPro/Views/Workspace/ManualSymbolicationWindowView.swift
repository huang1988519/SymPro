import SwiftUI

struct ManualSymbolicationWindowView: View {
    var body: some View {
        HSplitView {
            ScrollView(.vertical) {
                DSYMDiscoveryDirectoriesCard()
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(minWidth: 420, idealWidth: 520, maxWidth: 620)

            ScrollView(.vertical) {
                ManualSymbolicateSheet()
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(minWidth: 560, idealWidth: 720, maxWidth: .infinity)
        }
        .frame(minWidth: 1024, minHeight: 640)
    }
}

