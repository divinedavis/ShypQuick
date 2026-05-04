import SwiftUI
import PhotosUI

struct ItemCategory: Identifiable, Hashable {
    let id: String
    let title: String
    let description: String
    let icon: String
    let size: ItemSize
    let vehicleType: String   // "car" or "truck" — sent to the driver alongside the offer

    static let all: [ItemCategory] = [
        .init(id: "small",  title: "Car",   description: "Boxes, bags, small items",       icon: "car.fill",       size: .small, vehicleType: "car"),
        .init(id: "large",  title: "Truck", description: "Furniture, appliances, flatbed", icon: "truck.box.fill", size: .large, vehicleType: "truck")
    ]
}

struct ItemCategorySheet: View {
    let onSelect: (ItemCategory, Data?) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var attachedImage: UIImage?
    @State private var showingCamera = false
    @State private var photoItem: PhotosPickerItem?

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("What are you shipping?")
                        .font(.title2.bold())
                    Text("Pick the closest match so your driver knows what to bring. Add a photo if it helps.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: columns, spacing: 12) {
                        cameraCard
                        ForEach(ItemCategory.all) { category in
                            Button {
                                let data = attachedImage?.jpegData(compressionQuality: 0.85)
                                onSelect(category, data)
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
            .fullScreenCover(isPresented: $showingCamera) {
                CameraPicker { image in
                    attachedImage = image
                    submitWithPhoto(image)
                }
                .ignoresSafeArea()
            }
            .onChange(of: photoItem) { _, newValue in
                guard let newValue else { return }
                Task {
                    if let data = try? await newValue.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        attachedImage = image
                        submitWithPhoto(image)
                    }
                }
            }
        }
        .presentationDetents([.large])
    }

    @ViewBuilder
    private var cameraCard: some View {
        Menu {
            Button {
                showingCamera = true
            } label: {
                Label("Take Photo", systemImage: "camera.fill")
            }
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label("Choose from Library", systemImage: "photo.on.rectangle")
            }
            if attachedImage != nil {
                Button(role: .destructive) {
                    attachedImage = nil
                    photoItem = nil
                } label: {
                    Label("Remove Photo", systemImage: "trash")
                }
            }
        } label: {
            VStack(spacing: 10) {
                if let img = attachedImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    Text("Photo added")
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                    Text("Tap to change")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.tint)
                    VStack(spacing: 2) {
                        Text("Add photo").font(.headline)
                        Text("Take or upload")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("optional")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.gray.opacity(0.15), in: Capsule())
                }
            }
            .frame(maxWidth: .infinity, minHeight: 150)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(attachedImage == nil ? Color(.secondarySystemBackground) : Color.green.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(attachedImage == nil ? Color.gray.opacity(0.2) : Color.green, lineWidth: attachedImage == nil ? 1 : 2)
            )
        }
        .buttonStyle(.plain)
    }

    private func submitWithPhoto(_ image: UIImage) {
        let data = image.jpegData(compressionQuality: 0.85)
        guard let defaultCategory = ItemCategory.all.first else { return }
        onSelect(defaultCategory, data)
        dismiss()
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
