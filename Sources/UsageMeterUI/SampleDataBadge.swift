import SwiftUI

struct SampleDataBadge: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.orange)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.orange.opacity(0.14), in: Capsule())
            .accessibilityLabel("Sample data")
    }
}
