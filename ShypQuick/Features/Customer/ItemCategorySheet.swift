import SwiftUI

struct ItemCategory: Identifiable, Hashable {
    let id: String
    let title: String
    let description: String
    let icon: String
    let size: ItemSize

    static let all: [ItemCategory] = [
        .init(id: "documents",  title: "Documents",  description: "Envelopes, papers",   icon: "doc.fill",               size: .small),
        .init(id: "package",    title: "Small Box",  description: "Up to a shoebox",     icon: "shippingbox.fill",        size: .small),
        .init(id: "food",       title: "Food",       description: "Groceries, takeout",  icon: "takeoutbag.and.cup.and.straw.fill", size: .small),
        .init(id: "clothing",   title: "Clothing",   description: "Retail, laundry",     icon: "tshirt.fill",             size: .medium),
        .init(id: "furniture",  title: "Furniture",  description: "Couches, tables",     icon: "sofa.fill",               size: .large),
        .init(id: "appliance",  title: "Appliance",  description: "Fridge, washer",      icon: "washer.fill",             size: .large)
    ]
}

struct ItemCategorySheet: View {
    let onSelect: (ItemCategory) -> Void
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("What are you shipping?")
                        .font(.title2.bold())
                    Text("Pick the closest match so your driver knows what to bring.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(ItemCategory.all) { category in
                            Button {
                                onSelect(category)
                                dismiss()
                            } label: {
                                categoryCard(category)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Select item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func categoryCard(_ category: ItemCategory) -> some View {
        VStack(spacing: 10) {
            Image(systemName: category.icon)
                .font(.system(size: 36))
                .foregroundStyle(.tint)
            VStack(spacing: 2) {
                Text(category.title).font(.headline)
                Text(category.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Text(priceLabel(for: category.size))
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Color.accentColor.opacity(0.12), in: Capsule())
        }
        .frame(maxWidth: .infinity, minHeight: 150)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }

    private func priceLabel(for size: ItemSize) -> String {
        "from \(PricingService.Quote.format(PricingService.baseCents(for: size)))"
    }
}
