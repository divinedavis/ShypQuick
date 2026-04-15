import SwiftUI
import CoreLocation

struct ProfileView: View {
    @EnvironmentObject var session: SessionStore
    let profile: Profile
    @State private var showingHomeSheet = false

    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    LabeledContent("Name", value: profile.fullName ?? "—")
                    LabeledContent("Role") {
                        Label(roleLabel, systemImage: roleIcon)
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(.tint)
                    }
                }

                Section("Home address") {
                    Button {
                        showingHomeSheet = true
                    } label: {
                        HStack {
                            Image(systemName: "house.fill").foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.homeAddress ?? "Set your home address")
                                    .foregroundStyle(profile.homeAddress == nil ? .secondary : .primary)
                                if profile.homeAddress != nil {
                                    Text("Used to prefill your pickup location")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.tertiary)
                                .font(.caption)
                        }
                    }
                }

                Section {
                    Button("Sign out", role: .destructive) {
                        Task { await session.signOut() }
                    }
                }
            }
            .navigationTitle("Profile")
            .sheet(isPresented: $showingHomeSheet) {
                HomeAddressEditor(currentAddress: profile.homeAddress)
            }
        }
    }

    private var roleLabel: String {
        switch profile.role {
        case .customer: return "Customer"
        case .driver:   return "Driver"
        case .both:     return "Customer & Driver"
        }
    }

    private var roleIcon: String {
        switch profile.role {
        case .customer: return "shippingbox.fill"
        case .driver:   return "car.fill"
        case .both:     return "person.2.fill"
        }
    }
}

struct HomeAddressEditor: View {
    let currentAddress: String?
    @EnvironmentObject var session: SessionStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var search = AddressSearchService(recentsKey: "home_address_history")
    @State private var query: String = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                TextField("Type your home address", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: query) { _, newValue in
                        search.unlock()
                        search.updateQuery(newValue)
                    }
                    .padding(.horizontal)

                List {
                    ForEach(search.suggestions) { suggestion in
                        Button {
                            Task { await save(suggestion) }
                        } label: {
                            HStack {
                                Image(systemName: "mappin.circle.fill").foregroundStyle(.tint)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(suggestion.title).foregroundStyle(.primary)
                                    if !suggestion.subtitle.isEmpty {
                                        Text(suggestion.subtitle).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)

                if let errorMessage {
                    Text(errorMessage).font(.caption).foregroundStyle(.red)
                }
            }
            .navigationTitle("Home address")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                query = currentAddress ?? ""
                if !query.isEmpty { search.updateQuery(query) }
            }
        }
    }

    private func save(_ suggestion: AddressSuggestion) async {
        isSaving = true
        defer { isSaving = false }
        do {
            let coord = try await search.resolveCoordinate(for: suggestion)
            try await session.updateHomeAddress(
                address: suggestion.displayLine,
                lat: coord.latitude,
                lng: coord.longitude
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
