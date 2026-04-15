import SwiftUI

struct PurchaseSource: Identifiable, Hashable {
    let id: String
    let title: String
    let icon: String

    static let all: [PurchaseSource] = [
        .init(id: "amazon",     title: "Amazon",      icon: "shippingbox.fill"),
        .init(id: "walmart",    title: "Walmart",     icon: "cart.fill"),
        .init(id: "target",     title: "Target",      icon: "target"),
        .init(id: "ikea",       title: "IKEA",        icon: "sofa.fill"),
        .init(id: "local",      title: "Local store", icon: "building.2.fill"),
        .init(id: "other",      title: "Other",       icon: "questionmark.circle.fill")
    ]
}

struct PurchaseSourceSheet: View {
    let onDone: (PurchaseSource?) -> Void
    @State private var selection: PurchaseSource?

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Where was this purchased?")
                            .font(.title2.bold())
                        Text("Helps us improve ShypQuick for the stores you use most.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(PurchaseSource.all) { source in
                                Button {
                                    selection = source
                                } label: {
                                    sourceCard(source, isSelected: selection == source)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding()
                }

                Button {
                    onDone(selection)
                } label: {
                    Text("OK")
                        .bold()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .padding()
                .background(.regularMaterial)
            }
            .navigationTitle("Receipt")
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled(true)
    }

    private func sourceCard(_ source: PurchaseSource, isSelected: Bool) -> some View {
        VStack(spacing: 10) {
            Image(systemName: source.icon)
                .font(.system(size: 36))
                .foregroundStyle(isSelected ? Color.white : Color.accentColor)
            Text(source.title)
                .font(.headline)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .frame(maxWidth: .infinity, minHeight: 130)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isSelected ? Color.accentColor : Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(isSelected ? Color.accentColor : Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
}
