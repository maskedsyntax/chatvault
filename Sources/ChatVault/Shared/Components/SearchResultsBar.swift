import SwiftUI

struct SearchResultsBar: View {
    let resultCount: Int
    let onPrevious: () -> Void
    let onNext: () -> Void

    private var resultsLabel: String {
        let formatted = resultCount.formatted()
        return resultCount == 1 ? "\(formatted) result" : "\(formatted) results"
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(resultsLabel)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.quaternary, in: Capsule())

            Spacer(minLength: 0)

            HStack(spacing: 2) {
                Button(action: onPrevious) {
                    Image(systemName: "chevron.up")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .help("Previous Result")

                Button(action: onNext) {
                    Image(systemName: "chevron.down")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .help("Next Result")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
